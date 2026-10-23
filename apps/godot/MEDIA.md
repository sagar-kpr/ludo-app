# Camera and voice during friend games

Web and native Android use the same LiveKit room and server-issued player
identity. A player joins receive-only when an online friend game starts. They
can see and hear other players without sharing their own camera or microphone.
The camera icon toggles both devices. Missing permissions are requested together;
already-granted permissions are reused. Turning off unpublishes and stops local
tracks, restores the preset avatar, and leaves incoming audio/video connected.
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
does not request camera or microphone access. Camera permission denial leaves
the player receive-only and displays a retry instruction.

## Android build

Install JDK 17, Gradle 8.11.1, Android SDK 35 / build-tools 35.0.1 and Godot 4.6.1.
Set `JAVA_HOME`, `ANDROID_HOME`, and optionally `GRADLE_BIN`, and configure the
same SDK/JDK in Godot's Android export settings.

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
```

The media browser test needs `.tools/livekit/livekit-server` or `LIVEKIT_BIN`.
It starts a local development LiveKit server with test-only credentials and
checks two real WebRTC clients (desktop and Android-sized Chrome), receive-only
join, both directions of video/audio, camera-off resource release, continued
receiving and leave cleanup. Browser emulation is not a physical Android APK
test; validate runtime permissions, speaker/earpiece behavior, backgrounding,
and video placement on an Android phone before publishing the APK.
