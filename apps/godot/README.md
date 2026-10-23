# Rally Ludo — Godot migration

Active direction: Godot 4.6.1 + GDScript for the Android/web game; Kotlin for
Android-specific LiveKit integration. The previous Expo client is preserved in
`apps/mobile`, not deleted or silently redeployed.

## Play vs Computer

The home dashboard shows a larger avatar selector and player-name field above two
illustrated mode cards. Both modes use this shared identity. **Play with Friends**
opens a separate screen containing create-room and join-code controls.
Back navigation preserves entered values. **Play with Bot** immediately starts a
red-versus-yellow match against a server-controlled computer, using the saved
player name or Guest. Leaving a game returns to the mode dashboard.
The dashboard uses red Friends and blue Bot accent borders, gradient navy
surfaces, a live connection badge, and an avatar pencil button. Each card's
Play Now button calls the same action as the card itself. The browser name
input hides behind the avatar picker and restores unchanged when it closes.
This mode requires an internet connection and the updated game server.
Mode navigation and room requests show a compact translucent loading overlay,
which clears when the screen is ready or a request fails. In-game names sit
above the profile frame, leaving room for larger portraits inside it.

`scripts/mode_card.gd` draws the scalable dice/pawn and robot icons procedurally;
no bitmap downloads are required. The navy dice-pattern background and gameplay
layout remain in place. `tests/dashboard.gd` checks navigation and mode-card layout
at five viewport sizes, including narrow portrait and landscape screens.
Mode cards and the dice use short press/release tweens; friend-screen navigation
fades in, including the web's native input overlay. Reduce motion disables these
effects. Dice use a closer camera and larger available card slots, preserving
avatar spacing. Pawn landing taps retain their timing and soft tone with a 6 dB
volume increase; captures and dice generation are unchanged.
Dice start a visual spin immediately after a roll request is sent, then settle
on the server's result in 600 ms. The shared dice presentation duration also
keeps the server's input lock and automatic moves in sync with this faster roll.
Publish the updated server together with the client for matching timing.
During a match, a connection loss shows a Wi-Fi popup and reconnect spinner.
Pawn/dice input stays blocked until the recovered match snapshot is applied;
the popup then closes automatically. Browser offline/online events provide
immediate feedback when the device loses its network connection.

The computer uses the shared legal-move engine and the normal server dice. It
prefers finishing, captures and safe squares, waits for animations, and does not
consume inactivity dots. Human timeout rules remain unchanged. Friend rooms
continue to use their existing create/join flow. Computer matches support session
reconnection, Play again and Back to home; unused computer rooms are removed when
the human leaves. Chat and gifts are hidden for computer opponents.

`CREATE_COMPUTER_GAME` accepts the same `name` field as `CREATE_ROOM`. Snapshots
identify the opponent with optional player metadata `isComputer: true`.
Deploy both the server and web export to enable the option on the hosted site.

Run `npm test` for engine/server coverage, including complete computer matches,
and `npm run godot:test:computer` for the native client/server flow.
`npm run godot:test:computer:browser` builds the web client and checks the actual
mobile start button, computer turns and return home in Chrome.

## Premium restyle — section 1: board

The board uses one editable Theme: [`resources/theme_tokens.tres`](resources/theme_tokens.tres).
Open it in the Godot Inspector to edit red `#F2131B`, green `#00A64B`, blue
`#23ACE8`, yellow `#FFEB00`, grid/symbol ink and gradient strength. Under the
Theme's `Board` styleboxes, edit `frame`/`rim` for exterior radii/borders/shadows,
`yard_floor` for white-yard radii/shadows and `yard_inset` for inset shading.
Style dimensions are in artwork pixels (64 pixels per board cell).
Restart the scene after editing; artwork and the shared palette are cached.
Pawn step shadows use the same player palette. Departures and intermediate landings leave a
soft colored mark that holds for 0.35 seconds and fades over 1.10 seconds.
Tune `step_shadow_opacity`, `step_shadow_hold` and `step_shadow_fade` in the same
Theme resource. Sixteen reusable marks share one 128×128 radial texture;
reduced motion suppresses trails. Movement timing and coordinates are unchanged.
The final landing gets no colored mark or selection aura: only the existing
metal rings and a faint neutral contact shadow remain under the pawn.
Player portraits have no surrounding frame/background, and Bot appears once
in its profile heading, leaving the other slot for its turn timer.
Manual legal pawn taps start the first visual hop immediately at the normal
240 ms pace. The server confirms the rest of the move; rejected requests and
connection losses cancel the preview and restore its original position.

Client presentation now queues focus/reconnection snapshots behind pending dice
and pawn animations. A recovery snapshot cannot discard `TOKEN_MOVED` while the
active player's dice is rolling. Visible per-pawn progress also lets a missing
move event recover its intermediate hops without replaying completed movement.
These changes affect the Godot display/queue; server messages and rules are
unchanged. Refresh both clients after rebuilding the web export.

Offline actor/observer regression check:

```bash
.tools/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --path apps/godot --script res://tests/presentation.gd
```

Shadow/queue-update files: `scripts/board.gd`, `pawn.gd`, `design.gd`, `main.gd`,
`theme_tokens.gd`, `resources/theme_tokens.tres`, `tests/board_visuals.gd`,
`tests/presentation.gd` and its `.uid` sidecar, plus this README.

`scripts/board_surface.gd` draws matte StyleBoxFlat frames and home trays,
restrained GradientTexture2D fills, shared grid edges, recessed circular docks,
safe stars at the existing safe coordinates, inward arrows, subtle home-lane
chevrons and inlaid center triangles. Every cell uses the same 64×64 rectangle;
decorative bevels remain inside its bounds. The player palette and all pawn
anchors retain their existing values.
StyleBoxFlat does not offer gradient fills or inner shadows: gradient textures
and a layered translucent inset border provide those effects on both targets.
The artwork is rendered once in a 1024×1024 SubViewport and applied to one unlit
plane under the existing pawns. Four 128×128 procedural gradients are reused.
There are no new downloaded textures, custom shaders or per-frame art nodes.
The cache is a runtime render texture, so ETC2/ASTC asset compression does not
apply to it (approximately 4 MiB for the RGBA color attachment).

The final animated board viewport follows screen pixel density, with a maximum
1024-pixel edge, so dense phone screens do not upscale a UI-resolution image.
This does not resize or redraw the square artwork cache. Pointer coordinates
and completion badges account for the render density. Completion badges are
also restored after a layout change reparents the board.

The current token models, dice, cards, screen layout, background, rules, turn
timing and room/network implementation remain in place. Compatibility rendering
and `canvas_items`/`expand` are already configured in `project.godot`.

Focused offline checks (art/pawn alignment, home lanes and selectable pins):

```bash
.tools/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --path apps/godot --script res://tests/board_visuals.gd
```

Run this from the repository root. The board checks cover shared cell edges,
art/pawn alignment, safe zones, movement and cache reuse. Run
`res://tests/ui_regressions.gd` for portrait/landscape layouts and simulated
three-times pixel density, and `npm run godot:test` for two-client gameplay.
Android hardware and mobile Safari performance require device verification;
this section does not certify the 60 FPS target.

Changed sources: `scripts/board.gd`, `scripts/board_surface.gd`,
`scripts/design.gd`, `scripts/theme_tokens.gd`, `resources/theme_tokens.tres`,
`tests/board_visuals.gd`, `tests/check.gd`, this README, and Godot-generated `.uid`
sidecars for the three new scripts. The board is built dynamically; no `.tscn`
change is needed. No deployment is included.

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
  gold ring and countdown. The server gives separate 30-second roll and move
  clocks (configurable with `TURN_TIMEOUT_MS`, 1–120 s). An expired roll clock
  rolls automatically; an expired move clock chooses a random legal pawn.
  Blocked rolls pass immediately. Each new phase/bonus turn gets a full clock
  starting after the animation lock. Older deployed servers without this metadata
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
  compact navy captions face away from the board (with an edge fallback) and keep
  the sender identity and dice visible. Full text remains in the chat dialog.
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

Pawn completion now happens immediately on the colored center triangle:
positions 1–51 are the shared track, 52–56 the home lane, and `HOME = 57` the
terminal triangle. Finished pins stay there, arranged in four small slots with
gold checks. They never return to the yard or become selectable on another roll.
Legacy finished values of 58 also display as completed. The shared engine and
Godot adapter use the same endpoint. Finishing now requires an exact roll;
finishing bonuses, captures and ranked turn order keep their existing behavior.
These are requested gameplay changes following the visual-only board work above.
Rebuild the client and restart the server with the updated engine together;
existing rooms are cleared by a local watcher restart. Hosted servers need the
same engine update before this behavior can be used there.
Completion-correction files: `packages/game-engine/src/types.ts`, `board.ts`,
`index.ts`, `index.test.ts`, `rankings.test.ts`, `motion.test.ts`;
`apps/godot/scripts/board_math.gd`, `board.gd`, `pawn.gd`, `main.gd`;
`apps/godot/tests/board_visuals.gd`, `check.gd`; `scripts/godot-contract.test.ts`,
`test-godot-browser.mjs`; and this README.

The screenshot regression fixes keep red/green at the top left/right and
blue/yellow at the bottom left/right, with expanding row spacers that preserve
corners even when the opposite seat is absent. Finished cards show a persistent
gold “Winner · 1st”/placing label and no active dice or timer. The server skips
players with four terminal pawns even if a recovered room lacks their finish
entry; existing recorded ranks retain their order. Missing historical ranks
cannot reveal the original finish sequence and are appended in seat order.
When only base and completed pawns remain, rolls 1–5 pass immediately; six
still opens a base pawn. Shared grid strokes now draw after all cell fills,
with darker ink on every lane, including green. Chat networking is unchanged.

Files for these screenshot fixes: `scripts/main.gd`, `player_card.gd`,
`chat_bubbles.gd`, `board_surface.gd`, `theme_tokens.gd`,
`tests/ui_regressions.gd` (and generated UID); repository-root
`packages/game-engine/src/index.ts`, `rankings.test.ts`; and this README.
Run the focused UI checks with:

```bash
.tools/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --path apps/godot --script res://tests/ui_regressions.gd
```

Finish/movement rule follow-up: a pawn may advance only when the full roll
fits before or exactly on `HOME`; an oversized roll cannot highlight, tap, or
move that pawn. The dice-animation cue also filters by the actual rolled value;
pawns no longer show selection highlights before a roll. A friendly pawn blocks
landing on its square unless the destination is a star. This applies to the
shared track and private home lane; passing over a friendly pawn is allowed.
Finished pawns keep their separate center docks. Server validation, automatic
moves, timeout choices, and Godot/Vite/Expo selection use these same checks.
If every pawn is blocked, the server passes immediately.
Automatic movement now covers six as well as 1–5 when there is exactly one
legal choice (including the last remaining base pawn). Finishing the first,
second or third pawn grants the same player another roll; finishing the fourth
records their place and advances to an unfinished player. Automatic and manual
moves share this bonus rule. Both clients wait for landing before enabling the
next roll.

Follow-up files: repository-root `packages/game-engine/src/index.ts`,
`index.test.ts`, `finish-rules.test.ts`; Godot `scripts/board_math.gd`, `board.gd`,
`tests/finish_rules.gd` (and generated UID), `tests/presentation.gd`; this README.
The finish tests exercise every color, distances 1–6, all six dice outcomes,
first/second/third-pawn bonuses, fourth-pawn retirement, six-only base entry,
and owner/observer highlights and presentation. Run them with:

```bash
npx vitest run packages/game-engine/src/finish-rules.test.ts packages/game-engine/src/occupancy.test.ts
.tools/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --path apps/godot --script res://tests/finish_rules.gd
.tools/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --path apps/godot --script res://tests/presentation.gd
```

Timeout follow-up: both roll and move-selection phases default to 30 seconds.
The authoritative server rolls on roll timeout, resets the selection deadline
after the dice animation, and randomly chooses from legal pawns on move timeout.
Completed pawns, opponents, overshoots and base pawns without six are excluded.
No legal choices pass without movement. The previous immediate single-choice
auto-move remains enabled; multiple choices receive the full selection clock.
Normal capture/finish/six bonuses and completed-player retirement also apply to
timeout moves. Each timeout uses standard dice/move broadcasts, so Android and
web clients follow the same animation queue. Late inputs cannot apply twice.
`TURN_TIMEOUT_MS` still allows accelerated test clocks; unset it or use `30000`
for the requested 30/30 behavior.

Timeout files: repository-root `.env.example`, `apps/game-server/src/index.ts`,
`turn-clock.ts`, `turn-clock.test.ts`, `turn-clock.integration.test.ts`,
`rooms.test.ts`, `packages/game-engine/src/rankings.test.ts`; Godot
`scripts/main.gd`, `player_card.gd`, `tests/check.gd`, `ui_regressions.gd`,
`presentation.gd`; and this README. Live WebSocket tests use a child-only dice
preload and 1-second clocks to verify automatic roll/move, both-client event and
deadline equality, animation locks, manual-roll timer reset and blocked rolls.

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
movement runs whenever exactly one legal pawn exists, including a roll of six.
Base entry still needs six, and two or more legal pawns still require a choice.

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

Godot alone does not solve latency or networking reliability. Active matches
and sessions remain in server memory. Temporary disconnects can resume with the
same session token during the default 90-second grace period; full page refresh
does not preserve that token. A server restart or replacement still loses matches.
The Supabase adapter stores room/member metadata and chat, not a restorable game
snapshot. Durable match/session recovery remains separate work.

### Connection recovery

The server handles each WebSocket's protocol errors and terminates only the
faulty connection. Previously, an unhandled socket error could crash the process,
losing unrelated matches. Handshake/health responses and startup logs include a
server-instance identifier so a replacement can be distinguished during recovery.

The client polls and drains queued replies before checking heartbeat deadlines.
A quiet connection receives a ping/state probe with a four-second reply window
before replacement. Repeated focus notifications preserve an in-flight connection;
recovery URLs retain a slash before query parameters for native Godot. Leaving
clears the network room flag. A confirmed missing session shows a lost-match
dialog rather than silently returning to the dashboard. These changes do not
alter dice, moves, inactivity dots or grace periods.

`npm run godot:test:recovery` exercises queued replies after a simulated stall,
quiet-socket probes, reconnecting with the same player/room and all dots, failed
recovery feedback, and dashboard probing after leaving. `npm test` includes a
malformed-frame regression that verifies another Bot match remains alive.

### Leaving a match

Each player can use the exit icon beside chat and camera on their own profile.
The confirmation offers Stay or Yes, leave. The server removes their pawns and
future turns immediately; clients present a shadow dissolve and rising smoke,
then keep a large LEFT THE GAME label over the empty home corner. Reduced motion
skips the effect. When only one player remains, the client announces the winner
for four seconds and returns them to home, releasing their room membership.

Run `npm run godot:test:leaving` for the three-client server/UI regression test.
The same `res://tests/leaving.gd` test can run with a graphics renderer to save
smoke and departure screenshots under `test-results/`.

### Emoji picker

The emoji button opens a compact navy picker anchored eight pixels below that
player's icon. It follows the icon on resize, clamps horizontally to the screen,
and flips above only when there is no room below for the header and a row.
The four-column grid scrolls when vertical space is limited; all 24 stickers and emotions,
recipient selection, outside-click dismissal and the close button remain available.

Check placement at each corner and multiple mobile/desktop sizes with:

```bash
.tools/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --path apps/godot --script res://tests/emoji_picker.gd
```

Emotion reactions appear first: Like (thumbs up), Happy, Angry, Sad, Cry, Wow,
Wink, and Thinking. They preview their expression in the picker and animate on
the recipient's profile after delivery (tears, steam, winks, smiles, and hand
gestures). Reduced motion shows still artwork. The server validates all 24 IDs
against `packages/shared/src/stickers.ts`; a contract test keeps the GDScript
catalog aligned. `emoji_picker.gd` checks effect animation, reduced motion and
cleanup, while the WebSocket suite verifies every emotion reaches both players.

### Five timeout chances

Five dots below each profile's action icons span the enlarged portrait width and use that player's
board color. Filled dots show the remaining chances; used dots become hollow.
Each missed roll or move-selection deadline costs one chance from the same
per-player pool. Manual actions do not charge or refill it. A normal automatic
single-choice move, or a pass with no legal move, does not cost a chance. A
missed roll followed by its single-choice move costs one, rather than two.

The server includes balances in match snapshots, so reconnecting preserves them.
The fifth timeout action uses the last dot and completes normally. At zero dots,
the player can still play manually. Only their next missed deadline removes them
through the normal leave flow, without another automatic roll or move. Clients finish queued dice/movement, dissolve the pawns
into smoke, mark the empty corner, and return the removed player home with an
inactivity notice. The final remaining player wins. A fresh match restores five.

`npm run godot:test:lives` runs two real Godot clients against a temporary server
with a one-second clock and child-only deterministic dice. It checks every life
count, smoke departure, winner handling, home navigation, and fresh-game reset.
The WebSocket suite also checks shared roll/move accounting and the manual-roll
single-choice exemption. UI layout checks cover dot alignment and player colors.

### Mobile browser keyboard

The exported web page loads `web/native_inputs.js` before the engine. The canvas
and native name/code inputs share one positioned container sized to the browser's
visible viewport. Keyboard resize/scroll events update both together; policy 0
keeps Godot's window sizing from competing with that container. The Godot layout
reference adapts to the visible height, so controls keep their normal size and
the setup panel scrolls rather than shrinking. The layout-only LineEdits are
transparent and cannot open a second virtual keyboard on web; native clients
retain their normal LineEdits. Focus and viewport changes reveal the active
field once after layout, instead of repeatedly fighting the browser's scroll.

The JavaScript is also included in the PCK as a fallback, and Firebase's root
HTML response now uses no-cache so new bootstrap code is fetched on reload.
The viewport model follows the [VisualViewport API](https://developer.mozilla.org/en-US/docs/Web/API/VisualViewport).

Run `npm run godot:test:keyboard` for a real exported-game browser check. It
simulates Safari's visual viewport shrinking/panning while the layout viewport
stays tall, plus focus switching, rotation, keyboard dismissal, value preservation,
and an actual canvas create-room tap. These are desktop browser simulations;
physical iPhone Safari keyboard behavior still needs device confirmation.
