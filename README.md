# Rally Ludo

Premium multiplayer Ludo MVP foundation for Android/web expansion.

## Run locally

```bash
npm install
npm run dev
```

Start the local realtime server in a second terminal:

```bash
npm run server
```

The same web client can be packaged for Android with Capacitor after Android Studio/SDK is installed:

```bash
npx cap add android
npm run android:sync
npm run android:open
```

## Expo mobile app

The native Expo client lives in `apps/mobile`. To run it on a phone with Expo Go:

```bash
cd apps/mobile
npm install
npx expo start
```

Scan the QR code from Expo Go. For a downloadable Android build, use an Expo EAS development or preview build after configuring an Expo account:

```bash
npx eas build:configure
npx eas build --platform android --profile preview
```

Open the Vite URL shown in the terminal. The current demo includes:

- Premium responsive landing screen.
- Guest-friendly create/join room flow.
- Lobby with room code, players, ready state, and invite affordance.
- Interactive board demo with server-shaped game state and dice/move interactions.
- Token movement animation states, turn banner, chat composer, media controls, and connection indicators.
- Shared deterministic game engine with tests for six-to-enter, dice, movement, and turn progression.
- Local WebSocket server for guest connections, rooms, lobby state, authoritative dice/move validation, and chat events.

## Verification

The Expo client now uses server state for room membership, match start, dice, token moves, turns, and room chat. Only the creator can start, after at least two players join. Other players wait in the lobby and enter the board automatically when the server starts the match.

To test: start the server, open two app sessions, create a room in one and join its code in the other, then start from the host. A six brings a token out of base; dice with no legal moves automatically pass the turn. Tokens highlight only for the active player's legal moves.

Pawns now hop through each square (160 ms per square) rather than sliding directly to the destination. Captured pawns return after the moving pawn lands. Match controls wait until movement completes. Reduced-motion preferences skip visual hops.

On rolls 1–5, the server automatically moves when exactly one pawn can legally move. Rolls of six and multiple legal choices always wait for a tap. A second open pawn that would overshoot home does not count as a legal choice.

Run `npm run test:browser` to verify an Expo web player and a Vite web player in the same room, including per-square animation and automatic moves. This uses Chrome at `/usr/bin/google-chrome`; set `CHROME_PATH` if your installation is elsewhere. Browser screenshots are generated under `test-results/`.

Restart the server after code changes and create a fresh room. Rooms are held in memory; server restarts or client refreshes do not currently restore match membership. Database persistence and reconnect recovery still need completion. Voice/video controls in the original Vite client remain placeholders.

```bash
npm test
npm run build
```

## Production integrations still required

The workspace started empty, so the current slice is a polished local client demo. Cloud-backed gameplay still needs wiring to:

- Supabase guest sessions, optional Google OAuth, rooms, persistence, and chat.
- An authoritative WebSocket game server using `packages/game-engine`.
- LiveKit Cloud for real camera/microphone streams.
- Android packaging through React Native/Expo or a native shell around the shared client UI.

The UI and game-engine boundaries are intentionally separated so Supabase and LiveKit can be added without changing board rules or interaction design.

For server-side Supabase persistence, set `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` only in the server environment. Never expose the service-role key through Vite, Expo, or the browser.

## Configuration

Copy `.env.example` to `.env` for local configuration. For Expo Go on a physical phone, replace `EXPO_PUBLIC_REALTIME_URL` with your computer's LAN IP address; `localhost` means the phone itself.

The Supabase schema is in `supabase/migrations/001_initial.sql`. Apply it with the Supabase CLI or dashboard before enabling production persistence.

## Deploy the current Expo website: Firebase + Render

Deployment configuration is ready, but no cloud resources have been created.
This is a beta deployment: rooms are in memory and disappear on server restart;
refresh/reconnect recovery, authentication, persistence and live media are not
production-complete. Render's free service sleeps after idle periods and can
take about a minute to wake. Free tiers have quotas, not an unlimited uptime promise.

### 1. Protect credentials and upload the repository

The example environment file has been cleaned. Replace/deactivate the previously
exposed Supabase service-role key in your dashboard; removing it from this file
does not invalidate it. Keep fresh secrets only in local ignored `.env` files or
the server host's environment settings. Never prefix a secret with `EXPO_PUBLIC_`
or `VITE_`. `.gitignore` excludes environment files, dependencies and build output.
If a secret was committed previously, ignoring it does not remove it from history.

Create a GitHub repository and upload the source, including `apps`, `packages`,
`scripts`, `render.yaml`, `firebase.json` and both package lockfiles. Git is not
initialized automatically by these deployment scripts.

### 2. Deploy the game server on Render

In Render, choose **New → Blueprint**, connect the repository and approve the
free `rally-ludo-server` service defined in `render.yaml`. The settings are:

- Runtime: Node; root directory: repository root.
- Build: `npm ci --include=dev`.
- Start: `npm run server:start`.
- Health check: `/`; Render supplies the `PORT` environment variable.

You can initially test rooms without Supabase credentials. Adding Supabase keys
does not by itself implement match recovery. If enabling the existing persistence
adapter, put `SUPABASE_URL` and a fresh `SUPABASE_SERVICE_ROLE_KEY` in Render's
server environment, never in the blueprint or website.

After deployment, open the HTTPS address Render provides. It should return JSON
with `service: "rally-ludo-realtime"`. Change the `https://` prefix to `wss://`
for the client's game-server URL. Do not add `:8787` to the public Render address.

### 3. Configure and build the website

Create `apps/mobile/.env.production.local` using the production example as a
template, replacing the placeholder with your actual public server address:

```dotenv
EXPO_PUBLIC_REALTIME_URL=wss://YOUR_ACTUAL_SERVER.onrender.com
```

Then, from the repository root:

```bash
npm ci --include=dev
npm --prefix apps/mobile ci --include=dev
npm run build:web
```

Alternatively, provide the real URL directly in the command:

```bash
EXPO_PUBLIC_REALTIME_URL=wss://YOUR_ACTUAL_SERVER.onrender.com npm run build:web
```

The placeholder above must be replaced; the build intentionally rejects it.
The output is `apps/mobile/dist`, not the older Vite client's root `dist`.
URL validation checks format only, not whether your server is available.
Use `npm run preview:web` to preview the exported site. The WebSocket endpoint is
embedded at build time; changing it requires rebuilding and redeploying.

### 4. Select your Firebase project and publish

Create/select a Firebase Hosting project in your own account. Pick a new project
or site if you do not intend to overwrite a previous website.

```bash
npx firebase-tools login
npx firebase-tools projects:list
npm run deploy:web -- --project YOUR_FIREBASE_PROJECT_ID
```

Replace the project-ID placeholder with your actual project ID, not its display
name or URL. `firebase.json` is already configured, so do not run `init hosting`
or overwrite the app's `index.html`. This command rebuilds the app, then publishes
only Hosting to the explicitly selected project. The Firebase CLI prints the
public website address. No Firebase project is hardcoded in this repository.

### 5. Check gameplay from two devices

Open the Firebase website on two devices, create a room in one, join its code
from the other, and start from the host. Verify chat, server-controlled dice,
automatic single-legal-token movement (except on six), and matching board states.
If the free server is cold, open its HTTPS health URL first and wait for it to
wake before refreshing the game. Do not test restart recovery as a supported feature.

References: [Render Blueprint configuration](https://render.com/docs/blueprint-spec),
[Render free limits](https://render.com/docs/free), and
[Firebase Hosting configuration](https://firebase.google.com/docs/hosting/full-config).
