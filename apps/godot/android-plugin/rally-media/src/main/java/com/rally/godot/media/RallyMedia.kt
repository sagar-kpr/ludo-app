package com.rally.godot.media

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
    @Volatile private var destroyed = false

    private class Session(val room: Room, parent: kotlinx.coroutines.Job) {
        val job = SupervisorJob(parent)
        val scope = CoroutineScope(job + Dispatchers.Main.immediate)
        val mediaChanges = Mutex()
    }

    override fun getPluginName() = "RallyMedia"

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
                    Session(LiveKit.create(appContext), ownerJob)
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
        }
    }

    private fun hasPermission(permission: String): Boolean =
        activity?.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun reportPermissions() {
        val microphone = hasPermission(Manifest.permission.RECORD_AUDIO)
        val camera = hasPermission(Manifest.permission.CAMERA)
        status(
            if (microphone && camera) "permissions_granted" else "permissions_denied",
            "microphone=$microphone camera=$camera; enable media explicitly after permission grant",
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

