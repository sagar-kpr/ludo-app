package com.rally.godot.media

import android.app.Activity
import android.graphics.Outline
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import org.json.JSONObject
import io.livekit.android.RoomOptions
import io.livekit.android.renderer.TextureViewRenderer
import io.livekit.android.room.track.LocalAudioTrackOptions
import io.livekit.android.room.track.LocalVideoTrackOptions
import io.livekit.android.room.track.VideoPreset169
import io.livekit.android.room.track.RemoteAudioTrack
import io.livekit.android.room.track.Track
import io.livekit.android.room.track.VideoTrack
import io.livekit.android.room.participant.VideoTrackPublishDefaults
import livekit.org.webrtc.RendererCommon
import kotlin.math.roundToInt
import android.Manifest
import android.content.pm.PackageManager
import android.util.Log
import io.livekit.android.ConnectOptions
import io.livekit.android.LiveKit
import io.livekit.android.events.RoomEvent
import io.livekit.android.events.collect
import io.livekit.android.room.Room
import java.net.URI
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/** Android-only Godot v2 singleton. No tokens are persisted or logged here. */
class RallyMedia(godot: Godot) : GodotPlugin(godot) {
    private val ownerJob = SupervisorJob()
    private val scope = CoroutineScope(ownerJob + Dispatchers.Main.immediate)
    private val transitions = Mutex()
    private var session: Session? = null
    private var permissionsPending = false
    private var desiredCamera = false
    private var desiredMicrophone = false
    private var permissionRequest = emptyList<String>()
    private val mutedParticipants = mutableSetOf<String>()
    private val remoteAudio = mutableMapOf<String, MutableMap<RemoteAudioTrack, Boolean>>()
    private var publicationGeneration = 0
    private var videoLayer: FrameLayout? = null
    private var videoLayout = JSONObject()
    private data class VideoSlot(val container: FrameLayout, val renderer: TextureViewRenderer, val track: VideoTrack, var muted: Boolean = false)
    private val videos = mutableMapOf<String, VideoSlot>()
    @Volatile private var destroyed = false

    init {
        Log.i(TAG, "Godot v2 RallyMedia plugin instance created")
    }

    private class Session(val room: Room, parent: kotlinx.coroutines.Job) {
        val job = SupervisorJob(parent)
        val scope = CoroutineScope(job + Dispatchers.Main.immediate)
        val mediaChanges = Mutex()
    }

    override fun getPluginName() = "RallyMedia"

    override fun onMainCreate(activity: Activity?): View? {
        if (activity == null) {
            Log.e(TAG, "Plugin view initialization failed: Android activity is unavailable")
            return null
        }
        return try {
            FrameLayout(activity).also { layer ->
                layer.isClickable = false
                layer.isFocusable = false
                layer.clipChildren = true
                layer.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> applyVideoLayout() }
                videoLayer = layer
                Log.i(TAG, "Godot v2 RallyMedia plugin initialized")
            }
        } catch (error: Exception) {
            Log.e(TAG, "Plugin view initialization failed (${error.javaClass.simpleName})")
            null
        }
    }

    override fun shouldBeOnTop() = true

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("media_status", String::class.java, String::class.java),
    )

    private fun status(value: String, message: String) {
        if (value in setOf("error", "permission_required", "permissions_denied")) {
            Log.w(TAG, "$value: $message")
        }
        if (!destroyed) emitSignal("media_status", value, message)
    }

    // All mutable state and Android/LiveKit calls run on the main dispatcher.
    // GodotPlugin.emitSignal itself queues delivery to Godot's render thread.
    @UsedByGodot
    fun connect_room(url: String, token: String) {
        scope.launch {
            if (destroyed) return@launch
            val validUrl = try {
                val uri = URI(url)
                uri.scheme == "wss" && !uri.host.isNullOrBlank() && uri.userInfo == null
            } catch (_: Exception) {
                false
            }
            if (!validUrl || token.isBlank()) {
                status("error", "connect_room requires a wss URL and nonempty token")
                return@launch
            }
            transitions.withLock {
                disposeSession()
                if (destroyed) return@withLock
                val appContext = activity?.applicationContext
                if (appContext == null) {
                    Log.e(TAG, "Room initialization failed: Android application context is unavailable")
                    status("error", "Android activity is unavailable")
                    return@withLock
                }
                val current = try {
                    Session(LiveKit.create(appContext, RoomOptions(
                        adaptiveStream = true,
                        dynacast = true,
                        audioTrackCaptureDefaults = LocalAudioTrackOptions(noiseSuppression = true, echoCancellation = true, autoGainControl = true),
                        videoTrackCaptureDefaults = LocalVideoTrackOptions(captureParams = VideoPreset169.H360.capture.copy(maxFps = 15)),
                        videoTrackPublishDefaults = VideoTrackPublishDefaults(videoEncoding = VideoPreset169.H360.encoding.copy(maxFps = 15)),
                    )), ownerJob)
                } catch (error: Exception) {
                    Log.e(TAG, "LiveKit room creation failed (${error.javaClass.simpleName})")
                    status("error", "Room creation failed (${error.javaClass.simpleName})")
                    return@withLock
                }
                session = current
                status("connecting", "Connecting with microphone and camera off")
                current.scope.launch(start = CoroutineStart.UNDISPATCHED) {
                    current.room.events.collect { event ->
                        if (session !== current) return@collect
                        when (event) {
                            is RoomEvent.Connected -> status("connected", "Connected; microphone and camera off")
                            is RoomEvent.Reconnecting -> status("reconnecting", "Reconnecting")
                            is RoomEvent.Reconnected -> status("reconnected", "Connection restored")
                            is RoomEvent.Disconnected -> finishSession(
                                current, "disconnected", "Room disconnected (${event.reason})",
                            )
                            is RoomEvent.TrackSubscribed -> {
                                val identity = event.participant.identity?.value.orEmpty()
                                (event.track as? VideoTrack)?.let { attachVideo(current, identity, it, false) }
                                (event.track as? RemoteAudioTrack)?.let { track ->
                                    track.setVolume(if (identity in mutedParticipants) 0.0 else 1.0)
                                    remoteAudio.getOrPut(identity) { mutableMapOf() }[track] = event.publication.muted
                                    reportRemoteAudio()
                                }
                            }
                            is RoomEvent.TrackPublished -> if (event.participant == current.room.localParticipant) {
                                (event.publication.track as? VideoTrack)?.let {
                                    attachVideo(current, event.participant.identity?.value.orEmpty(), it, true)
                                }
                            }
                            is RoomEvent.TrackUnsubscribed -> {
                                val identity = event.participant.identity?.value.orEmpty()
                                (event.track as? VideoTrack)?.let { removeVideo(identity, it) }
                                (event.track as? RemoteAudioTrack)?.let {
                                    remoteAudio[identity]?.remove(it)
                                    reportRemoteAudio()
                                }
                            }
                            is RoomEvent.TrackUnpublished -> if (event.publication.kind == io.livekit.android.room.track.Track.Kind.VIDEO) {
                                removeVideo(event.participant.identity?.value.orEmpty())
                            }
                            is RoomEvent.TrackMuted -> {
                                (event.publication.track as? RemoteAudioTrack)?.let {
                                    remoteAudio[event.participant.identity?.value.orEmpty()]?.set(it,true)
                                    reportRemoteAudio()
                                }
                                if (event.publication.kind == io.livekit.android.room.track.Track.Kind.VIDEO) {
                                    videos[event.participant.identity?.value.orEmpty()]?.muted = true
                                    applyVideoLayout()
                                }
                            }
                            is RoomEvent.TrackUnmuted -> {
                                (event.publication.track as? RemoteAudioTrack)?.let {
                                    remoteAudio[event.participant.identity?.value.orEmpty()]?.set(it,false)
                                    reportRemoteAudio()
                                }
                                if (event.publication.kind == io.livekit.android.room.track.Track.Kind.VIDEO) {
                                    videos[event.participant.identity?.value.orEmpty()]?.muted = false
                                    applyVideoLayout()
                                }
                            }
                            is RoomEvent.ParticipantDisconnected -> {
                                val identity = event.participant.identity?.value.orEmpty()
                                removeVideo(identity)
                                remoteAudio.remove(identity)
                                reportRemoteAudio()
                            }
                            else -> Unit
                        }
                    }
                }
                current.scope.launch {
                    try {
                        current.room.connect(url, token, ConnectOptions(audio = false, video = false))
                        // connect() can finish signaling before the RTC transport
                        // reaches CONNECTED. Publish only after RoomEvent.Connected.
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (error: Exception) {
                        // SDK exception text may contain connection details; expose only the type.
                        Log.e(TAG, "LiveKit connection failed (${error.javaClass.simpleName})")
                        finishSession(current, "error", "Connection failed (${error.javaClass.simpleName})")
                    }
                }
            }
        }
    }

    @UsedByGodot
    fun set_microphone_enabled(enabled: Boolean) {
        scope.launch { set_local_media(desiredCamera, enabled) }
    }

    @UsedByGodot
    fun set_camera_enabled(enabled: Boolean) {
        scope.launch { set_local_media(enabled, desiredMicrophone) }
    }

    @UsedByGodot
    fun set_participant_muted(identity: String, muted: Boolean) {
        scope.launch {
            if (muted) mutedParticipants.add(identity) else mutedParticipants.remove(identity)
            session?.room?.remoteParticipants?.values?.filter { it.identity?.value == identity }?.forEach { participant ->
                participant.trackPublications.values.forEach { publication ->
                    (publication.track as? RemoteAudioTrack)?.setVolume(if (muted) 0.0 else 1.0)
                }
            }
        }
    }

    @UsedByGodot
    fun disconnect_room() {
        scope.launch {
            if (destroyed) return@launch
            transitions.withLock {
                disposeSession()
                mutedParticipants.clear()
                status("disconnected", "Room disconnected")
            }
        }
    }

    private fun finishSession(current: Session, value: String, message: String) {
        // Run cleanup outside the session being cancelled, so it can join its jobs.
        scope.launch {
            transitions.withLock {
                if (session === current) {
                    disposeSession()
                    status(value, message)
                }
            }
        }
    }

    private suspend fun disposeSession() {
        remoteAudio.clear()
        reportRemoteAudio()
        desiredCamera = false
        desiredMicrophone = false
        publicationGeneration++
        for (identity in videos.keys.toList()) removeVideo(identity)
        val previous = session ?: return
        session = null
        previous.job.cancelAndJoin()
        try {
            previous.room.release() // Includes disconnect and native resource cleanup.
        } catch (error: Exception) {
            status("error", "Room cleanup failed (${error.javaClass.simpleName})")
        }
    }

    private fun reportRemoteAudio() {
        val active = remoteAudio.filterValues { tracks -> tracks.values.any { !it } }.keys
        status("remote_audio_state", org.json.JSONArray(active.toList()).toString())
    }

    @UsedByGodot
    fun set_publishing_enabled(enabled: Boolean) = set_local_media(enabled, enabled)

    @UsedByGodot
    fun set_local_media(camera: Boolean, microphone: Boolean) {
        scope.launch {
            if (destroyed) return@launch
            desiredCamera = camera
            desiredMicrophone = microphone
            val generation = ++publicationGeneration
            val current = session
            // Privacy controls stop unwanted devices even before a pending
            // enable operation has completed. Generation checks discard it later.
            if (current != null) {
                if (!camera) stopKind(current, Track.Kind.VIDEO)
                if (!microphone) stopKind(current, Track.Kind.AUDIO)
            }
            if (!camera && !microphone) {
                reportLocalState(current)
                return@launch
            }
            if (current == null) {
                status("error", "Camera and voice require a connected friend room")
                return@launch
            }
            if (current.room.state != Room.State.CONNECTED) {
                // Off switches above still release capture during a reconnect.
                // Keep the latest target for the Reconnected event to reapply.
                reportLocalState(current)
                return@launch
            }
            val needed = buildList {
                if (camera) add(Manifest.permission.CAMERA)
                if (microphone) add(Manifest.permission.RECORD_AUDIO)
            }
            if (needed.any { !hasPermission(it) }) {
                requestMediaPermissions(needed)
                return@launch
            }
            current.scope.launch {
                current.mediaChanges.withLock {
                    if (session !== current || generation != publicationGeneration) return@withLock
                    for ((kind, enabled) in listOf(Track.Kind.VIDEO to camera, Track.Kind.AUDIO to microphone)) {
                        if (generation != publicationGeneration) break
                        if (!enabled) continue
                        try {
                            val changed = if (kind == Track.Kind.VIDEO) current.room.localParticipant.setCameraEnabled(true)
                                else current.room.localParticipant.setMicrophoneEnabled(true)
                            if (!changed) throw IllegalStateException("Media unavailable")
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (error: Exception) {
                            if (generation == publicationGeneration) {
                                stopKind(current, kind)
                                if (kind == Track.Kind.VIDEO) desiredCamera = false else desiredMicrophone = false
                                val device = if (kind == Track.Kind.VIDEO) "camera" else "microphone"
                                status("${device}_error", "$device could not start. Check permissions and close other apps using it.")
                            }
                        }
                    }
                    if (session !== current) return@withLock
                    if (!desiredCamera) stopKind(current, Track.Kind.VIDEO)
                    if (!desiredMicrophone) stopKind(current, Track.Kind.AUDIO)
                    if (generation == publicationGeneration) reportLocalState(current)
                }
            }
        }
    }

    private fun stopKind(current: Session, kind: Track.Kind) {
        for (publication in current.room.localParticipant.trackPublications.values.toList()) {
            if (publication.kind == kind) publication.track?.let {
                current.room.localParticipant.unpublishTrack(it, stopOnUnpublish = true)
            }
        }
        if (kind == Track.Kind.VIDEO) removeVideo(current.room.localParticipant.identity?.value.orEmpty())
    }

    private fun reportLocalState(current: Session?) {
        val publications = current?.room?.localParticipant?.trackPublications?.values.orEmpty()
        val camera = publications.any { it.kind == Track.Kind.VIDEO && it.track != null && !it.muted }
        val microphone = publications.any { it.kind == Track.Kind.AUDIO && it.track != null && !it.muted }
        status(if (camera) "camera_enabled" else "camera_disabled", if (camera) "Camera on" else "Camera off")
        status(if (microphone) "microphone_enabled" else "microphone_disabled", if (microphone) "Microphone on" else "Microphone off")
        if (camera && microphone) status("publishing_enabled", "Camera and microphone on")
        if (!camera && !microphone) status("publishing_disabled", "Camera and microphone off")
    }

    @UsedByGodot
    fun set_video_layout(json: String) {
        scope.launch {
            try {
                videoLayout = JSONObject(json)
                applyVideoLayout()
            } catch (_: Exception) { /* Ignore a stale or incomplete layout during shutdown. */ }
        }
    }

    private fun attachVideo(current: Session, identity: String, track: VideoTrack, mirror: Boolean) {
        if (identity.isBlank() || videos[identity]?.track === track) return
        val host = activity ?: return
        val layer = videoLayer ?: return
        removeVideo(identity)
        val renderer = TextureViewRenderer(host)
        current.room.initVideoRenderer(renderer)
        renderer.setMirror(mirror)
        renderer.setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL)
        renderer.isClickable = false
        renderer.isFocusable = false
        val container = FrameLayout(host)
        container.clipToOutline = true
        container.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                val scale = layer.width.toFloat() / videoLayout.optDouble("width", 420.0).toFloat().coerceAtLeast(1f)
                outline.setRoundRect(0, 0, view.width, view.height, 12f * scale)
            }
        }
        container.addView(renderer, FrameLayout.LayoutParams(-1, -1))
        layer.addView(container)
        videos[identity] = VideoSlot(container, renderer, track)
        track.addRenderer(renderer)
        applyVideoLayout()
    }

    private fun removeVideo(identity: String, track: VideoTrack? = null) {
        val previous = videos[identity] ?: return
        if (track != null && previous.track !== track) return
        videos.remove(identity)
        previous.track.removeRenderer(previous.renderer)
        videoLayer?.removeView(previous.container)
        previous.renderer.release()
    }

    private fun applyVideoLayout() {
        val layer = videoLayer ?: return
        val entries = videoLayout.optJSONArray("entries")
        val sx = layer.width / videoLayout.optDouble("width", 420.0).coerceAtLeast(1.0)
        val sy = layer.height / videoLayout.optDouble("height", 860.0).coerceAtLeast(1.0)
        for ((identity, slot) in videos) {
            var rectangle: org.json.JSONArray? = null
            if (entries != null) for (index in 0 until entries.length()) {
                val entry = entries.getJSONObject(index)
                if (entry.optString("id") == identity) rectangle = entry.optJSONArray("rect")
            }
            if (!videoLayout.optBoolean("visible", false) || slot.muted || rectangle == null) {
                slot.container.visibility = View.INVISIBLE
                continue
            }
            slot.container.visibility = View.VISIBLE
            slot.container.layoutParams = FrameLayout.LayoutParams(
                (rectangle.getDouble(2) * sx).roundToInt().coerceAtLeast(1),
                (rectangle.getDouble(3) * sy).roundToInt().coerceAtLeast(1),
            ).apply {
                leftMargin = (rectangle.getDouble(0) * sx).roundToInt()
                topMargin = (rectangle.getDouble(1) * sy).roundToInt()
            }
            slot.container.invalidateOutline()
        }
    }

    @UsedByGodot
    fun request_media_permissions() {
        scope.launch { requestMediaPermissions(MEDIA_PERMISSIONS) }
    }

    private fun requestMediaPermissions(permissions: List<String>) {
        val host = activity
        if (host == null) { status("error", "Android activity is unavailable"); return }
        if (permissionsPending) return
        val missing = permissions.filterNot { hasPermission(it) }
        if (missing.isEmpty()) { status("permissions_granted", "Media permission granted"); return }
        permissionsPending = true
        permissionRequest = missing
        status("permissions_requested", "Allow access to the camera or microphone you turn on")
        try {
            host.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
        } catch (error: Exception) {
            permissionsPending = false
            status("error", "Permission request failed (${error.javaClass.simpleName})")
        }
    }

    override fun onMainRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ) {
        if (requestCode != PERMISSION_REQUEST) return
        scope.launch {
            permissionsPending = false
            if (desiredCamera && Manifest.permission.CAMERA in permissionRequest && !hasPermission(Manifest.permission.CAMERA)) {
                desiredCamera = false
                status("camera_error", "Allow camera access in Android Settings to show your video")
            }
            if (desiredMicrophone && Manifest.permission.RECORD_AUDIO in permissionRequest && !hasPermission(Manifest.permission.RECORD_AUDIO)) {
                desiredMicrophone = false
                status("microphone_error", "Allow microphone access in Android Settings to speak")
            }
            permissionRequest = emptyList()
            if (!destroyed && session != null) set_local_media(desiredCamera, desiredMicrophone)
        }
    }

    private fun hasPermission(permission: String): Boolean =
        activity?.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    override fun onMainDestroy() {
        Log.i(TAG, "Godot v2 RallyMedia plugin shutting down")
        destroyed = true
        scope.launch {
            try {
                transitions.withLock { disposeSession() }
            } finally {
                scope.cancel()
            }
        }
        super.onMainDestroy()
    }

    private companion object {
        const val TAG = "RallyMedia"
        const val PERMISSION_REQUEST = 0x524D
        val MEDIA_PERMISSIONS = listOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA)
    }
}

