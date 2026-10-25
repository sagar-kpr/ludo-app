# Local board perspective

The authoritative server still owns player IDs, turn order, unique logical
colors, integer path positions, legal moves, captures and rankings. No client
preference is sent to the server and no authoritative fields are recolored.

`scripts/board_perspective.gd` is the shared client display adapter. Logical
corners run clockwise: coral (Red), sun (Green), mint (Yellow), violet (Blue).
For local logical corner `L` and chosen display-color index `P`:

- Clockwise quarter-turns: `(3 - L) mod 4`, placing the local home bottom-left.
- Logical corner `i` appears at `(i + turns) mod 4`.
- Its displayed color is `COLORS[(i - L + P) mod 4]`.
- Each clockwise turn maps grid `(row, col)` to `(col, 14 - row)` and world
  `(x, y, z)` to `(-z, y, x)`.

Both identity and preference are necessary: two clients may choose Red while
occupying different logical paths. Each sees their own home Red at bottom-left;
both still send the original token IDs and consume the same server snapshots.

The dashboard selector renders the existing 3D pawn model into one small cached
atlas shared by all four buttons. Red, the first pawn, is the default. A selected preference is saved
in local `preferences.cfg` and can be changed before creating/joining a match.
The guarded selector never changes an active match's perspective.

`board.gd` transforms movement, capture returns, finish docks, picking and
markers. Its printed plane rotates by the same quarter-turns. `BoardSurface`
draws the mapped palette across all home areas, lanes, starting cells, arrows
and center triangles, retaining the square 1024px SubViewport cache. The cache
updates once when the adapter changes, rather than on every snapshot.

Player cards remain keyed by logical color internally, preserving chat, video,
turn controls and identity bindings. Only their corner/container placement and
accent change. Lobby borders, pawn enamel, selection inlays, trails and results
avatars use the same palette. Tokens and avatars remain upright.

Validation:

```sh
npm run godot:test:perspective
npm run godot:test:perspective:browser
npm run godot:test
npm run godot:test:captures
npm test
```

The perspective matrix covers every local player in 2-, 3- and 4-player matches
with all four preferences, all path cells, touch selection, shared safe stars,
captures, home entry, rankings and independent identical color preferences.
