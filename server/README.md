# EEAccess Tesla relay (server)

A tiny zero-dependency Node service, **multi-tenant**: it holds ONE shared
Tesla Developer app (so end users never register their own), but each user
gets their own Tesla OAuth session (own refresh token, own vehicles), stored
in their own file under `users/`. It keeps each user's access token fresh,
relays commands, and — the point — schedules **Unlock + Drive server-side**
so it fires even when a user's phone/watch has no signal in a garage. Runs on
`elbaeverywhere-wsl`, public at `https://eeaccess.elbaeverywhere.com` (nginx
TLS in front of `127.0.0.1:8737`).

## Auth model — no username or password, ever

The app never asks a human for a login. Instead:

1. The app calls `GET /oauth/start` → gets Tesla's login URL (server-generated
   PKCE) + a `state`.
2. The user logs into Tesla in-app (`ASWebAuthenticationSession`). Tesla
   redirects to **this server** (`/oauth/callback`, not the app) — the
   server-hosted redirect is required because the shared Client Secret must
   never reach the app binary.
3. A tiny bounce page hands the resulting `code`+`state` to the app via the
   `eeaccess://tesla/relay-callback` custom scheme.
4. The app posts `{ code, state }` to `POST /oauth/complete`. The server does
   the real token exchange (holding the secret), creates a new user record,
   and returns a random **API key** — auto-provisioned, never typed by anyone.
5. The app stores that key in Keychain and uses it as `Authorization: Bearer
   <key>` from then on.

## Setup

1. `cp config.example.json config.json` and fill in `clientId`, `clientSecret`,
   `regionBase`, and `redirectUri` (must exactly match an Allowed Redirect URI
   registered on the Tesla app — e.g.
   `https://eeaccess.elbaeverywhere.com/oauth/callback`). `config.json` is
   gitignored.
2. `mkdir -p users` (per-user session files; also gitignored).
3. Run: `node server.mjs` (or the systemd unit below).

## Endpoints

`/health`, `/oauth/start`, `/oauth/callback`, `/oauth/complete` need no auth.
Everything else requires `Authorization: Bearer <per-user apiKey>`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | liveness |
| GET | `/oauth/start` | begin sign-in — returns `{ authorizeUrl, state }` |
| GET | `/oauth/callback` | Tesla's redirect target — bounces into the app |
| POST | `/oauth/complete` `{ code, state }` | finishes sign-in — returns `{ apiKey, userId }` |
| DELETE | `/account` | delete this user's data on the relay (works even if rate-limited) |
| GET | `/vehicles` | list this user's vehicles |
| GET | `/vehicles/:vin/state` | vehicle_data snapshot |
| POST | `/vehicles/:vin/wake` | wake |
| POST | `/vehicles/:vin/unlock` \| `/lock` \| `/drive` \| `/climate_on` \| `/climate_off` | command |
| POST | `/vehicles/:vin/schedule` `{ "delay": 60 }` | **server-side Unlock+Drive in N s** |
| GET | `/schedules` | this user's pending schedules |
| DELETE | `/schedules/:id` | cancel a schedule (must be yours) |

Every `vin`-scoped call verifies the VIN actually belongs to the caller's
Tesla account (`assertOwnsVehicle`) — refreshed from Tesla if not already
cached, so one user can never steer commands at another user's car. Requests
are rate-limited per user (30/min) to bound the blast radius of a runaway
client against the shared Tesla app's standing. Commands are sent **unsigned**
(works for pre-2021 S/X). 2021+ cars need the signing proxy — a later phase.

## Data & privacy

Each user's Tesla refresh token lives only in their own `users/<uuid>.json`
file — nothing links a user record back to a real identity beyond whatever
Tesla itself associates with the account. `DELETE /account` removes the file
and any pending schedules for that user's cars immediately.

## Run as a service (systemd)

`eeaccess-tesla.service` is a template. Install as a user service:

```bash
mkdir -p ~/.config/systemd/user
cp eeaccess-tesla.service ~/.config/systemd/user/
# set ExecStart to your absolute node path (which node)
systemctl --user daemon-reload
systemctl --user enable --now eeaccess-tesla
loginctl enable-linger "$USER"   # keep it running without an active login
```

## Example

```bash
curl -s localhost:8737/health
curl -s localhost:8737/oauth/start
# ... complete sign-in in the app, then use the returned apiKey:
curl -s -H "Authorization: Bearer $API_KEY" localhost:8737/vehicles
curl -s -X POST -H "Authorization: Bearer $API_KEY" localhost:8737/vehicles/<VIN>/schedule -d '{"delay":60}'
```
