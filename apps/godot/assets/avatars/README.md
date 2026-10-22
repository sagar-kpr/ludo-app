Add square PNG, JPG, JPEG or WebP preset images here (512 × 512 recommended).
Use stable filenames containing letters, digits, underscores or hyphens.
The filename identifies a player's selection across clients; avoid renaming
existing presets. Add a file named `default.png` to choose the default explicitly.
Otherwise, the first filename in alphabetical order is the default.

No source-code edits are needed when adding an image. Restart the running app
for local testing; rebuild and redeploy the web/Android client to include new
images in installed or hosted builds. The picker scans imported resources,
including their export sidecars, and reuses cached textures. Missing or removed
selections fall back to the default; an empty folder retains the drawn avatar.

Players choose from this collection using Choose avatar on the dashboard.
Their choice is saved on that device/browser and sent as a preset filename when
creating or joining a room, including Play with AI. No user uploads are offered.
Deploy the updated game server to share avatar choices with other players.

Run `npm run godot:test:avatars` for mobile picker, saved selection, exported
resource loading and computer-match smoke coverage.
