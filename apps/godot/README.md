# Rally Ludo — Godot migration

Active direction: Godot 4.6.1 + GDScript for the Android/web game; Kotlin for
Android-specific LiveKit integration. The previous Expo client is preserved in
`apps/mobile`, not deleted or silently redeployed.

## Implemented migration slice

- Actual 3D geometry: raised board/frame, rounded cell tiles and home trays,
  extruded location-pin tokens and six-sided dice with correctly paired pip faces.
- Compatibility rendering for Android and web, orthographic board camera,
  lighting/shadows and shared material caching. No commercial asset licenses.
- Light setup screens and white player cards with indigo actions. During play,
  an original blue dice-pattern shader replaces the plain background; no leaf,
  wood or competitor artwork is used. The prior artwork is retained unused.
- Red/green/yellow/blue board with rounded home panels, softer color surrounds,
  rounded inset floors and individual rounded path tiles, gray safe stars and
  colored directional arrows. Location-pin tokens have white outlines and round
  badges, glossy colored faces, a pointed cell anchor and soft contact shadows.
  Legal pins gently float and their floor rings pulse (disabled in reduced motion).
  Light cards have subtle elevation; buttons give restrained press feedback.
- Premium-reference polish: bevel-capped glossy pin faces, brighter ivory dice
  with flush dark pip discs, a navy/metal/cyan layered frame and warm layered
  tiles. Active cards have a player-color glow; empty seats and secondary controls use
  coordinated navy surfaces. Open-seat plus controls copy the existing room code.
  Background motif contrast is reduced. Layout, turn rules and die truth are unchanged.
- Legal-move polish: only the local player's legally selectable pins show a matching-color
  base ring/aura and a one-second 1–1.12 scale/bob loop anchored at the pin tip.
  Reduced motion keeps the static ring and removes the loop. A gold dice instruction
  chip appears beneath the board. Safe stars are slate on cream and white on color.
- Card borders/glows follow the player's color; the active avatar has a shrinking
  gold ring and countdown. The server publishes real turn deadlines (default 15 s,
  configurable with `TURN_TIMEOUT_MS`, 1–120 s), advances expired turns and rejects
  stale actions. Moving selection uses the remaining turn time; new/extra turns
  start after the animation lock. Older deployed servers without this metadata
  show no countdown. Restart/redeploy the server as well as rebuilding the client.
- Full-pin selection includes animated heads, centers and feet. Per-step colored
  trails fade away automatically; reduced motion suppresses them. Shared squares
  fan out pins and show separate color-coded counts, including mixed-color stacks.
- Ranked matches continue after the first finisher, skipping completed players.
  They end after N−1 finishers (third in a four-player room); the remaining player
  receives last place. Animated home badges and results list placements and home
  counts. Only the host sees and can send `RESTART_GAME`; the server enforces this
  and resets the same room with a monotonically increasing match version.
- Original locally drawn cartoon avatar fallbacks (not camera/profile images).
- Four persistent player cards; active player's animated dice lives in their
  card, never a permanent center-board control. Empty seats stay present.
- Guest name, create/join private rooms, copy code, lobby, host start, 2–4 players,
  authoritative dice/pawn/turn/winner state and room chat using the existing server.
- Ordered local dice/move presentation queue; eased per-cell pin hops with a
  minimum 220 ms per step and restrained squash/stretch, legal selection
  matching-color rings for local legal moves, duplicate-tap lock and reduced-motion setting.
- Fixed game composition rather than scrolling during play; setup screens scroll.
- Four-second profile chat previews, fade in/out and latest-message replacement;
  they never cover the board or active dice. Full text remains in the chat dialog.
  Chat receipt bypasses gameplay animation waits.
- Original cached PCM dice, walking, capture and incoming-chat cues. Local-player
  roll/step and involved-player capture vibration, separate persisted sound and
  vibration settings, and Android vibration permission. Browser sound requires
  normal user interaction; vibration is not supported in all browsers/devices.
  Actual phone sound/vibration feel has not yet been device-tested.
- Dice feedback now follows eight progressively spaced contacts during the
  1.2-second roll, plus a separate final settle cue. Each completed cell hop plays
  a quiet landing tick. Captures have a distinct cue and 55/30 ms double pulse
  for involved players, while rolls/steps use lighter feedback. Reduced motion
  retains the roll rhythm; sound and vibration remain independently switchable.
- Godot Web/Android export presets and separate Firebase Godot config.
- Kotlin Android plugin source with explicit permissions, LiveKit room lifecycle,
  mic/camera publishing controls and status signals. **Not yet built/device-tested.**

The engine's wire colors remain `coral/sun/mint/violet`, mapped visually to
red/green/yellow/blue. This is an adapter, not a new second rules engine.
The server's existing 9-character `XXXX-XXXX` codes are preserved; this differs
from the document's 6-character input. Changing that contract is a separate step.

## Open and run

Godot 4.6.1 is available locally at
`.tools/godot/Godot_v4.6.1-stable_linux.x86_64`. This downloaded executable is
ignored by Git; another machine needs the standard GDScript Godot editor from
[the official archive](https://godotengine.org/download/archive/4.6.1-stable/).
Use matching export templates, not C#/.NET for the web client.

From repository root:

```bash
npm run godot:editor
```

Use the editor's Play button, or `npm run godot`. By default the client points
to the existing public Render WebSocket URL. It does not require Expo or a QR code.
Only public connection configuration is in `project.godot`; never put secrets there.

`npm run web` from repository root now builds and serves the Godot browser preview
at `http://127.0.0.1:4175`. The legacy Expo web command is `npm run expo:web`.
The legacy `build:web`/`deploy:web` commands are unchanged and still deploy Expo;
the explicit Godot build/deployment commands below target the new client.

For local development, use two terminals:

```bash
npm run server
```

```bash
npm run godot -- --server=ws://127.0.0.1:8787
```

Run the second command twice to open two client windows. Create in one, join the
code in the other and start as host. Use a six to open a pawn. Server automatic
movement remains enabled only when exactly one legal pawn exists on rolls 1–5.

If your Godot is elsewhere:

```bash
GODOT_BIN=/absolute/path/to/godot npm run godot:editor
```

## Checks

```bash
npm run godot:check
npm run godot:test
npm run godot:test:browser
npm test
```

`godot:test` starts its own temporary local server with database writes disabled,
then tests two real Godot clients: room creation/join, host start, dice timing,
authoritative snapshots, legal pawn selection, movement landing and chat.
It also checks coordinate bounds and UI move affordances. This is headless
functional verification, **not** 60 FPS, hardware, visual or media certification.
Random dice may make the integration test take longer than a typical unit test.

`godot:test:browser` needs the web templates and Chrome (`CHROME_PATH` can override
the executable). It opens two real WebGL clients against its own local server,
checks room/start/dice delivery and browser errors, and captures home/lobby/board
screenshots at phone and desktop sizes. Network intents are injected through a
test-only WebSocket interceptor; this is not a full canvas-input regression test.

## Browser build

Install the matching web templates (only two web files are downloaded from the
official archive, ZIP CRC-checked; Android templates are not installed by this):

```bash
npm run godot:templates:web
npm run godot:build:web
npm run godot:preview:web
```

The single-threaded Compatibility export uses WebAssembly/WebGL2. It avoids the
threaded export's cross-origin-isolation requirement. Browser performance,
Safari, permissions, tab backgrounding and camera/voice must still be tested on
target phones. No guarantee of native-level performance on every browser.

The old Firebase hosting config is intentionally unchanged. **Only when ready
to replace the live site**, deploy explicitly using the new config:

```bash
npx firebase-tools deploy --only hosting --config firebase.godot.json --project ludo-86848
```

This publishes `apps/godot/dist`, not the Expo folder. No deployment was performed
as part of the migration. Web builds take their server URL from `project.godot`.
Rebuild after changing it. Never deploy `ws://localhost` or a private LAN URL.

## Android APK

No APK has been produced. Godot's Android export needs JDK 17, Android SDK, and
matching Godot Android export/Gradle build templates. These are not available
in the current environment. Configure them in Godot Editor Settings → Export →
Android, install the Android build template through Project → Install Android
Build Template, then use the Android export preset.

The new package is `com.rallyludo.godot` so migration builds do not overwrite an
existing Expo installation. Choose the final package/signing identity before a
store release. The preset creates a debug APK for device testing:

```bash
npm run godot:build:android
```

For media, first build and install the plugin addon as described in
[`android-plugin/README.md`](android-plugin/README.md). It is separate from the
old root `android/` Capacitor project. Publishing camera tracks is **not** the
same as rendering them in player cards; the latter is still missing.

## Remaining spec work — not production ready

1. Compile/test the Kotlin bridge, add participant video rendering and bind
   camera/mic state to stable player cards. Add browser JavaScript LiveKit bridge.
2. Issue short-lived room-scoped media tokens on the server after checking
   membership; keep API secrets server-only. Current preview never enables media.
3. Durable guest identity and authenticated room resume, event sequence/idempotency,
   timeouts, presence, state recovery after disconnect/server restart.
4. Complete room readiness/leave/rematch lifecycle, invitations, avatars, Google
   login, profile/settings, leave confirmation and full result/standings flow.
5. Local animated stickers with lightweight server events, SFX/music/haptics,
   splash/setup polish and animation/capture/winner effects.
6. Phone/font/safe-area responsiveness, actual 3D/visual refinement, optimized
   authored assets if needed, real Android/iPhone-browser profiling and media QA.
7. Runtime schema validation/rate limits, persistence repair, monitoring and
   complete-match/network-fault/visual acceptance tests.

Godot alone does not solve latency or networking reliability. The existing
server still keeps active rooms in memory, does not restore membership after
refresh/disconnect, and does not implement every regional Ludo rule variant.
The UI says so rather than showing a fake successful reconnection. The current
Supabase adapter is partial; this migration makes no claim that Firebase auth,
Redis or durable PostgreSQL match history have been implemented.
