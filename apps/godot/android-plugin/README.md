# RallyMedia — Godot 4.6.1 Android LiveKit bridge

Standalone Android library and Godot Android **plugin v2**, owned entirely by this
directory. It is independent of the repository's Capacitor/Expo Android projects.
The singleton name is `RallyMedia`. No server credentials, API secrets, or access
tokens are embedded. Supply a short-lived room token obtained from your backend.

## Pinned toolchain and SDK

| Component | Pin | Primary source |
| --- | --- | --- |
| Godot compile-only library | `org.godotengine:godot:4.6.1.stable` | [Published POM](https://repo.maven.apache.org/maven2/org/godotengine/godot/4.6.1.stable/godot-4.6.1.stable.pom) |
| Android Gradle Plugin | `8.6.1` | [Godot 4.6.1 configuration](https://github.com/godotengine/godot/blob/4.6.1-stable/platform/android/java/app/config.gradle) |
| Kotlin | `2.1.20` | Same Godot configuration and POM |
| Gradle | `8.11.1` | [Godot 4.6.1 wrapper](https://github.com/godotengine/godot/blob/4.6.1-stable/platform/android/java/gradle/wrapper/gradle-wrapper.properties) |
| JDK / bytecode | `17` | Godot configuration above |
| Android compile SDK / build tools / minimum SDK | `35` / `35.0.1` / `24` | Godot configuration above |
| LiveKit Android | `io.livekit:livekit-android:2.23.5` | [Tagged installation guide](https://github.com/livekit/client-sdk-android/blob/v2.23.5/README.md), [published POM](https://repo.maven.apache.org/maven2/io/livekit/livekit-android/2.23.5/livekit-android-2.23.5.pom) |
| Coroutines Android | `1.6.0` | [LiveKit 2.23.5 version catalog](https://github.com/livekit/client-sdk-android/blob/v2.23.5/gradle/libs.versions.toml) and POM |

These are published pins aligned to the Godot export toolchain and the tagged
LiveKit APIs, rather than a claim of a tested Godot/LiveKit device combination.
LiveKit's upstream project uses Kotlin 1.9.25; Godot's Kotlin 2.1.20 compiler can
consume that older SDK metadata. Gradle still needs to resolve and compile this
combination on an Android development machine. LiveKit's published dependency
graph pins WebRTC `137.7151.05` and AudioSwitch commit
`89582c47c9a04c62f90aa5e57251af4800a62c9a`; JitPack is required for AudioSwitch.
Do not silently replace these with dynamic versions.

## Build

Install JDK 17, Gradle 8.11.1, Android SDK platform 35 and build-tools 35.0.1.
Set `JAVA_HOME` to your JDK and `ANDROID_HOME` to your Android SDK installation,
or create an ignored `local.properties` in **this** directory with `sdk.dir`.
This scaffold does not include a Gradle wrapper binary; use an installed Gradle
8.11.1 or its absolute `bin/gradle` path. Do not use the Capacitor wrapper.

From this directory:

```sh
gradle --version
gradle :rally-media:assembleDebug :rally-media:assembleRelease :rally-media:lint
gradle packageGodotAddon
```

The AARs are `rally-media/build/outputs/aar/rally-media-{debug,release}.aar`.
The integration package is `build/godot-addon/addons/rally_media/`, containing
`plugin.cfg`, `export_plugin.gd`, and `bin/` with both AAR variants.
The packaging task only writes inside this directory.

An AAR contains this plugin's code and manifest, **not** LiveKit's dependencies.
The supplied export adapter declares LiveKit and Coroutines as Maven dependencies
and adds JitPack, so Godot's Gradle export can package their transitive libraries
and native WebRTC binaries. Keep its pins synchronized with the module build file.
Godot is compile-only because the export template already supplies the engine.
The consumer ProGuard rules preserve the reflected plugin entry point/methods.

## Integrate into the Godot project

After building, copy the generated `addons/rally_media` directory into the target
Godot project's `addons` directory. This is an integration step for the project
owner; no files outside this scaffold were changed.

Use the Godot **4.6.1** editor and matching export/build templates. Enable
RallyMedia in Project Settings → Plugins, install the Android build template,
and enable **Use Gradle Build** in the Android export preset. Use minimum SDK 24
or higher and target SDK 35 to match these pins. Export to an Android device.
Desktop and web exports do not provide the singleton.

Registration uses manifest metadata
`org.godotengine.plugin.v2.RallyMedia = com.rally.godot.media.RallyMedia`,
`GodotPlugin.getPluginSignals()`, and `@UsedByGodot` on the public methods.
The exact snake-case method names are part of the API. This uses
[Godot's v2 export flow](https://docs.godotengine.org/en/4.6/tutorials/platform/android/android_plugin.html);
there is no v1 `.gdap` file.

```gdscript
var media: Object

func setup_media() -> void:
    if Engine.has_singleton("RallyMedia"):
        media = Engine.get_singleton("RallyMedia")
        media.connect("media_status", Callable(self, "_on_media_status"))

func join_media(livekit_url: String, backend_token: String) -> void:
    if media != null:
        media.connect_room(livekit_url, backend_token)

func _on_media_status(status: String, message: String) -> void:
    # Update application state/UI. Never log the backend token.
    print("RallyMedia: ", status, " ", message)

func ask_for_media_access() -> void:
    if media != null:
        media.request_media_permissions()

func enable_microphone_after_consent() -> void:
    if media != null:
        media.set_microphone_enabled(true)

func enable_camera_after_consent() -> void:
    if media != null:
        media.set_camera_enabled(true)

func leave_media() -> void:
    if media != null:
        media.disconnect_room()
```

## Runtime contract

All methods return immediately (`void`); outcomes arrive asynchronously through
`media_status(status: String, message: String)`. Godot queues signal delivery to
its render thread. Android permission requests and plugin state run on the main
dispatcher; LiveKit connection/media operations use Kotlin coroutines.

- `connect_room(url, token)` requires a `wss://` URL without URL user credentials
  and a nonempty token. It cancels/releases a previous session before creating
  another. Each connection explicitly uses `ConnectOptions(audio=false,
  video=false)`, even if permissions were previously granted. Subscribe defaults
  to true; remote audio playback is managed by LiveKit.
- `set_microphone_enabled(enabled)` and `set_camera_enabled(enabled)` require
  a connected room. Enabling additionally requires the corresponding runtime
  permission. Media commands are serialized within the session. Calls made while
  connecting produce an error; they are not remembered for a later connection.
- `request_media_permissions()` requests missing `RECORD_AUDIO` and `CAMERA`
  permissions together, only when invoked. It does not connect or enable media.
  Pending requests are guarded. The game toggle requires both permissions. Permanent
  denial requires the user to grant permission in Android Settings. Permission
  revocation/device errors are reported when an operation fails.
- `disconnect_room()` cancels session coroutine work and releases the room.
  Repeating it is safe. Engine destruction also cancels/releases the session and
  suppresses further status signals. Replacement and failure cleanup are scoped
  to the current session so stale callbacks cannot dispose a newer room.

Status values: `connecting`, `connected`, `reconnecting`, `reconnected`,
`disconnected`, `microphone_enabled`, `microphone_disabled`, `camera_enabled`,
`camera_disabled`, `permissions_requested`, `permissions_pending`,
`permissions_granted`, `permissions_denied`, `permission_required`, and `error`.
Treat `status` as the machine-readable value and `message` as display text.
`permissions_denied` also covers a cancelled/partial request; its message contains
a user-facing permission instruction. This scaffold exposes no SDK exception
text or token in its own signals/logging; application and SDK logging policies
still need review for production.

The implementation follows the pinned SDK's
[connection options](https://github.com/livekit/client-sdk-android/blob/v2.23.5/livekit-android-sdk/src/main/java/io/livekit/android/ConnectOptions.kt),
[Room lifecycle](https://github.com/livekit/client-sdk-android/blob/v2.23.5/livekit-android-sdk/src/main/java/io/livekit/android/room/Room.kt),
and [participant media methods](https://github.com/livekit/client-sdk-android/blob/v2.23.5/livekit-android-sdk/src/main/java/io/livekit/android/room/participant/LocalParticipant.kt).
In this SDK, disabling the microphone **mutes its publication**; it is not a
guarantee that microphone capture resources are released. Disabling the camera
stops its capture. Disconnect/release is the full session teardown path.

## Validation and limits

Both debug and release AARs were compiled with JDK 17, Gradle 8.11.1,
Android SDK 35 and the pinned LiveKit SDK. The addon is now installed automatically
by `npm run godot:media:android` and included by `npm run godot:build:android`.
The native singleton still needs physical-phone permission/audio/video testing.

Native video uses LiveKit `TextureViewRenderer` overlays at the existing avatar
rectangles, with centered aspect-fill cropping and rounded clipping. Both local
and remote participant tracks are rendered; remote audio uses the SDK's normal
playback. The Godot bridge hides these views behind dialogs and reconnect UI.
`set_publishing_enabled(true)` requests both missing runtime permissions, then
publishes microphone and camera together only after both are granted. Passing
false unpublishes/stops both tracks immediately, while retaining remote audio
and video. `set_video_layout(json)` maps stable player identities to UI rectangles.

Video starts at 640×360 / 15 FPS. Adaptive stream, dynacast and simulcast are
on; echo cancellation, noise suppression and automatic gain control are enabled.
These are quality targets, not a guarantee against every hardware/network noise.
See [the integrated media guide](../MEDIA.md) for backend configuration and web
interoperability. No credentials are bundled in the plugin or APK.

Bluetooth selection, screen sharing, foreground/background-call services and
background camera publishing are outside this playing-screen integration.
Validate mixed web/APK calls, runtime permission denial, rotation, speaker and
headset behavior on an Android device before publishing.
