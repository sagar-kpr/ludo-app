# Camera and voice during friend games

Web and native Android use the same LiveKit room and server-issued player
identity. A player joins receive-only when an online friend game starts. They
can see and hear other players without sharing their own camera or microphone.
The first camera-icon tap starts camera and microphone. Extra controls stay hidden
until sharing starts: a microphone button appears on your card. Separately, every
listener sees a speaker button next to any other player who is actually sending
audio, including listeners who have never enabled their own camera or microphone.
Avatar-only or video-only players have no speaker button. Afterward, the camera icon
hides/restores video independently; the microphone button mutes/unmutes your own
outgoing voice. Hiding the camera restores the avatar while audio continues.
Both can be turned off and restarted independently without losing the controls.
The speaker button mutes only that player's audio on your device; it never mutes
the sender for other listeners or hides their video. Multiple senders can be muted
independently. The sender's own microphone switch stops outgoing audio for everyone.
Mute choices survive track
replacement and media reconnects in the same match, and reset when leaving.
Permissions are requested only for devices being enabled, and existing grants
are reused. A camera failure does not stop a working microphone (or vice versa).
Disabled devices are unpublished and capture is stopped; incoming media continues.
Bot games never join media and hide the camera button.

Video targets 640×360 at 15 fps, with adaptive subscription and simulcast so small
avatar boxes do not waste bandwidth. Voice enables echo cancellation, noise
suppression and automatic gain control. Actual clarity depends on the network,
microphone/camera and device processing; these settings cannot remove every noise.

## Configure hosted calls

Create a LiveKit Cloud project or deploy a LiveKit server. On the **game server**
(currently the Render service), set these environment variables:

```dotenv
LIVEKIT_URL=wss://YOUR-LIVEKIT-SERVER
LIVEKIT_API_KEY=YOUR-SERVER-KEY
LIVEKIT_API_SECRET=YOUR-SERVER-SECRET
```

Keep the API key and secret on the game server, never in Firebase Hosting,
Godot project settings, an APK, frontend environment variables, or git. Restart
the game server after setting them and deploy the updated web client. No LiveKit
account or hosted deployment has been created automatically by this change.
Without configuration the game continues normally, and tapping the camera
explains that calls are not configured.

For local testing with the credentials in the ignored root `.env`, use two terminals:

```sh
npm run server:start
```

```sh
RALLY_PREVIEW_REALTIME_URL=ws://127.0.0.1:8787 npm run web
```

For the hosted game, set the same three variables in the game server's hosting
environment, redeploy that server, then publish the web build. The APK's default
game-server endpoint also needs the updated backend before its camera can connect.

The backend accepts `MEDIA_JOIN` only for a player in an active friend game.
It issues a 120-second room-scoped token for that player's actual identity,
with publishing/subscription access and no room administration. Clients cannot
select another player's identity or another room. Leaving revokes the participant.

Browser calls require HTTPS (localhost HTTP works for development). If mobile
Safari blocks incoming audio, use the small **Tap to hear players** button; this
does not request camera or microphone access. Permission denial displays a retry
instruction for the affected device while preserving any other active device.

## Android build

Install JDK 17, Gradle 8.11.1, Android SDK 35 / build-tools 35.0.1 and Godot 4.6.1.
The build automatically uses the project-local toolchain in
`.tools/media-android` when available. To use a different installation, set
`JAVA_HOME`, `ANDROID_HOME` (or `ANDROID_SDK_ROOT`), and optionally `GRADLE_BIN`.
The export command writes the matching SDK/JDK paths into project-local Godot
editor settings under `.tools/godot-config`, so no manual editor setup is needed.

```sh
npm run godot:templates:android
npm run godot:build:android
```

The build compiles and installs the `RallyMedia` addon automatically before
exporting. Both debug and release AARs are generated, and the export adapter
includes LiveKit's Maven dependencies. The Android preset requests `CAMERA`
and `RECORD_AUDIO` at runtime, uses minimum SDK 24, and keeps the robot/preset
avatar until an actual camera track is available. Native `TextureViewRenderer`
views fit the same avatar rectangles as the browser video elements, including
rotation/resizing and modal visibility. No per-frame bitmap/base64 copy is used.

## Validation

```sh
npm run server:check
npm test
npm run godot:check
npm run godot:test:computer
npm run godot:test:media
npm run godot:test:media:native
```

The native API regression test reproduces Android's separate JNI method registry.
Use `JNISingleton.has_java_method()` when checking Kotlin/Java plugin functions;
`Object.has_method()` does not enumerate that registry. This applies both to
plugin discovery and to the video-layout capability check. See the
[Godot 4.6 JNI API](https://docs.godotengine.org/en/4.6/classes/class_jnisingleton.html).

The Android bridge reports readiness from `RoomEvent.Connected`, rather than
assuming completion of signaling means the RTC transport is ready to publish.
In the 0.2.1 fix, an isolated x86_64 Android 35 emulator build verified JNI
discovery, both Android permission dialogs, and native camera/microphone
publication to a browser subscriber. The browser decoded 360×640 camera video;
the emulator also displayed the browser's test video in its avatar overlay.
The distributed signed APK remains ARM64. This emulator check does not replace
testing physical-phone microphones, cameras, audio routing or rendering.

The 0.2.2 controls were also exercised in the Android emulator against a real
browser subscriber: microphone mute/unmute with video retained, audio-only mode,
both devices stopped, audio-only restart, camera restoration, and the native
receiver-mute/unmute API. Browser integration tests check actual receiver playback
mute, independent capture release, microphone continuity after camera denial,
audio-only restart, and continued incoming audio/video. The native API/unit suite
also checks that controls stay hidden before successful startup and remain usable
when both devices are disabled. A native playback-volume call was exercised; an
audible volume comparison on physical phones is still a device QA step.

Version 0.2.3 ties each remote speaker button to actual incoming audio track
state, independently of the receiver's local call. The native API/UI suite covers
all publisher/receiver combinations for 2-, 3- and 4-player rooms, including
multiple independent mutes. Live four-player browser integration verifies two
broadcasters and two additional receive-only listeners, receiver-local mute,
sender-wide microphone mute, silent-player controls, and broadcaster tab closure.
An Android emulator receiving from a web broadcaster also verifies that the
speaker button appears without starting local capture, hides on sender mic-off,
returns on mic-on, and disappears on broadcaster disconnect.

Android's engine boot splash uses `assets/rally_splash.png`, captured from the
existing web loader's branding with animations frozen. `project.godot` sets this
image explicitly so Android does not fall back to the Godot logo. Android's brief
system launch screen can still show the app icon before the branded engine
splash. The Android splash is static; the web loader keeps its existing animation.

The media browser test needs `.tools/livekit/livekit-server` or `LIVEKIT_BIN`.
It starts a local development LiveKit server with test-only credentials and
checks two real WebRTC clients (desktop and Android-sized Chrome), receive-only
join, both directions of video/audio, camera-off resource release, continued
receiving and leave cleanup. Browser emulation is not a physical Android APK
test; validate runtime permissions, speaker/earpiece behavior, backgrounding,
and video placement on an Android phone before publishing the APK.
