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
import io.livekit.android.room.track.VideoTrack
import io.livekit.android.room.participant.VideoTrackPublishDefaults
import livekit.org.webrtc.RendererCommon
import kotlin.math.roundToInt
import android.Manifest
import android.content.pm.PackageManager
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
    private var desiredPublishing = false
    private var publicationGeneration = 0
    private var videoLayer: FrameLayout? = null
    private var videoLayout = JSONObject()
    private data class VideoSlot(val container: FrameLayout, val renderer: TextureViewRenderer, val track: VideoTrack, var muted: Boolean = false)
    private val videos = mutableMapOf<String, VideoSlot>()
    @Volatile private var destroyed = false

    private class Session(val room: Room, parent: kotlinx.coroutines.Job) {
        val job = SupervisorJob(parent)
        val scope = CoroutineScope(job + Dispatchers.Main.immediate)
        val mediaChanges = Mutex()
    }

    override fun getPluginName() = "RallyMedia"

    override fun onMainCreate(activity: Activity?): View? {
        if (activity == null) return null
        return FrameLayout(activity).also { layer ->
            layer.isClickable = false
            layer.isFocusable = false
            layer.clipChildren = true
            layer.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> applyVideoLayout() }
            videoLayer = layer
        }
    }

    override fun shouldBeOnTop() = true

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("media_status", String::class.java, String::class.java),
    )

    private fun status(value: String, message: String) {
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
                    status("error", "Room creation failed (${error.javaClass.simpleName})")
                    return@withLock
                }
                session = current
                status("connecting", "Connecting with microphone and camera off")
                current.scope.launch(start = CoroutineStart.UNDISPATCHED) {
                    current.room.events.collect { event ->
                        if (session !== current) return@collect
                        when (event) {
                            is RoomEvent.Reconnecting -> status("reconnecting", "Reconnecting")
                            is RoomEvent.Reconnected -> status("reconnected", "Connection restored")
                            is RoomEvent.Disconnected -> finishSession(
                                current, "disconnected", "Room disconnected (${event.reason})",
                            )
                            is RoomEvent.TrackSubscribed -> (event.track as? VideoTrack)?.let {
                                attachVideo(current, event.participant.identity?.value.orEmpty(), it, false)
                            }
                            is RoomEvent.TrackPublished -> if (event.participant == current.room.localParticipant) {
                                (event.publication.track as? VideoTrack)?.let {
                                    attachVideo(current, event.participant.identity?.value.orEmpty(), it, true)
                                }
                            }
                            is RoomEvent.TrackUnsubscribed -> removeVideo(event.participant.identity?.value.orEmpty(), event.track as? VideoTrack)
                            is RoomEvent.TrackUnpublished -> if (event.publication.kind == io.livekit.android.room.track.Track.Kind.VIDEO) {
                                removeVideo(event.participant.identity?.value.orEmpty())
                            }
                            is RoomEvent.TrackMuted -> {
                                if (event.publication.kind == io.livekit.android.room.track.Track.Kind.VIDEO) {
                                    videos[event.participant.identity?.value.orEmpty()]?.muted = true
                                    applyVideoLayout()
                                }
                            }
                            is RoomEvent.TrackUnmuted -> {
                                if (event.publication.kind == io.livekit.android.room.track.Track.Kind.VIDEO) {
                                    videos[event.participant.identity?.value.orEmpty()]?.muted = false
                                    applyVideoLayout()
                                }
                            }
                            is RoomEvent.ParticipantDisconnected -> removeVideo(event.participant.identity?.value.orEmpty())
                            else -> Unit
                        }
                    }
                }
                current.scope.launch {
                    try {
                        current.room.connect(url, token, ConnectOptions(audio = false, video = false))
                        if (session === current) {
                            status("connected", "Connected; microphone and camera off")
                        }
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (error: Exception) {
                        // SDK exception text may contain connection details; expose only the type.
                        finishSession(current, "error", "Connection failed (${error.javaClass.simpleName})")
                    }
                }
            }
        }
    }

    @UsedByGodot
    fun set_microphone_enabled(enabled: Boolean) {
        setMediaEnabled(enabled, Manifest.permission.RECORD_AUDIO, "microphone")
    }

    @UsedByGodot
    fun set_camera_enabled(enabled: Boolean) {
        setMediaEnabled(enabled, Manifest.permission.CAMERA, "camera")
    }

    private fun setMediaEnabled(enabled: Boolean, permission: String, kind: String) {
        scope.launch {
            if (destroyed) return@launch
            val current = session
            if (current == null || current.room.state != Room.State.CONNECTED) {
                status("error", "$kind requires a connected room")
                return@launch
            }
            if (enabled && !hasPermission(permission)) {
                status("permission_required", "$kind permission missing; call request_media_permissions")
                return@launch
            }
            current.scope.launch {
                current.mediaChanges.withLock {
                    if (session !== current || current.room.state != Room.State.CONNECTED) return@withLock
                    try {
                        val changed = if (kind == "microphone") {
                            current.room.localParticipant.setMicrophoneEnabled(enabled)
                        } else {
                            current.room.localParticipant.setCameraEnabled(enabled)
                        }
                        if (changed) {
                            status("${kind}_${if (enabled) "enabled" else "disabled"}", "$kind ${if (enabled) "enabled" else "disabled"}")
                        } else {
                            status("error", "$kind change rejected by SDK")
                        }
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (error: Exception) {
                        status("error", "$kind change failed (${error.javaClass.simpleName})")
                    }
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
        desiredPublishing = false
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

    @UsedByGodot
    fun set_publishing_enabled(enabled: Boolean) {
        scope.launch {
            if (destroyed) return@launch
            desiredPublishing = enabled
            val generation = ++publicationGeneration
            val current = session
            if (!enabled) {
                if (current != null) stopPublishing(current)
                status("publishing_disabled", "Camera and microphone off")
                return@launch
            }
            if (current == null || current.room.state != Room.State.CONNECTED) {
                desiredPublishing = false
                status("error", "Camera and voice require a connected friend room")
                return@launch
            }
            if (!MEDIA_PERMISSIONS.all { hasPermission(it) }) {
                request_media_permissions()
                return@launch
            }
            current.scope.launch {
                current.mediaChanges.withLock {
                    if (session !== current || !desiredPublishing || generation != publicationGeneration) return@withLock
                    try {
                        val camera = current.room.localParticipant.setCameraEnabled(true)
                        if (!desiredPublishing || generation != publicationGeneration) {
                            stopPublishing(current)
                            return@withLock
                        }
                        val microphone = current.room.localParticipant.setMicrophoneEnabled(true)
                        if (!camera || !microphone) throw IllegalStateException("Media unavailable")
                        if (!desiredPublishing || generation != publicationGeneration) {
                            stopPublishing(current)
                            return@withLock
                        }
                        status("publishing_enabled", "Camera and microphone on. Tap again to turn both off.")
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (_: Exception) {
                        stopPublishing(current)
                        desiredPublishing = false
                        status("error", "Camera or microphone could not start. Check permissions and close other camera apps.")
                    }
                }
            }
        }
    }

    private fun stopPublishing(current: Session) {
        for (publication in current.room.localParticipant.trackPublications.values.toList()) {
            publication.track?.let { current.room.localParticipant.unpublishTrack(it, stopOnUnpublish = true) }
        }
        removeVideo(current.room.localParticipant.identity?.value.orEmpty())
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
        scope.launch {
            if (destroyed) return@launch
            val host = activity
            if (host == null) {
                status("error", "Android activity is unavailable")
                return@launch
            }
            if (permissionsPending) {
                status("permissions_pending", "Media permission request already pending")
                return@launch
            }
            val missing = MEDIA_PERMISSIONS.filterNot { hasPermission(it) }
            if (missing.isEmpty()) {
                reportPermissions()
            } else {
                permissionsPending = true
                status("permissions_requested", "Requesting microphone and camera permissions")
                try {
                    host.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
                } catch (error: Exception) {
                    permissionsPending = false
                    status("error", "Permission request failed (${error.javaClass.simpleName})")
                }
            }
        }
    }

    override fun onMainRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ) {
        if (requestCode != PERMISSION_REQUEST) return
        scope.launch {
            permissionsPending = false
            reportPermissions()
            if (desiredPublishing && MEDIA_PERMISSIONS.all { hasPermission(it) }) set_publishing_enabled(true)
            else if (desiredPublishing) {
                desiredPublishing = false
                session?.let { stopPublishing(it) }
            }
        }
    }

    private fun hasPermission(permission: String): Boolean =
        activity?.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun reportPermissions() {
        val microphone = hasPermission(Manifest.permission.RECORD_AUDIO)
        val camera = hasPermission(Manifest.permission.CAMERA)
        status(
            if (microphone && camera) "permissions_granted" else "permissions_denied",
            if (microphone && camera) "Camera and microphone permission granted."
            else "Allow both camera and microphone permissions to join the call. You can also enable them in Android Settings.",
        )
    }

    override fun onMainDestroy() {
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
        const val PERMISSION_REQUEST = 0x524D
        val MEDIA_PERMISSIONS = listOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA)
    }
}

