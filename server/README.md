# EEAccess Tesla relay (server)

A tiny zero-dependency Node service that holds your Tesla Fleet credentials,
keeps the access token fresh, relays commands, and — the point — schedules
**Unlock + Drive server-side** so it fires even when your phone/watch has no
signal in a garage. Runs on `elbaeverywhere-wsl`, reachable only over your
tailnet.

## Setup

1. `cp config.example.json config.json` and fill in `clientId`, `clientSecret`,
   `regionBase`, and a long random `serverToken`. (`config.json` is gitignored.)
2. Seed a refresh token: `node login.mjs` → open the printed URL, log in, paste
   the code shown on `braapais.github.io/tesla/manual`. Requires that redirect
   URI to be registered on your developer.tesla.com app.
3. Run: `node server.mjs` (or the systemd unit below).

## Endpoints

All except `/health` require `Authorization: Bearer <serverToken>`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | liveness (no auth) |
| GET | `/vehicles` | list account vehicles |
| GET | `/vehicles/:vin/state` | vehicle_data snapshot |
| POST | `/vehicles/:vin/wake` | wake |
| POST | `/vehicles/:vin/unlock` \| `/lock` \| `/drive` \| `/climate_on` \| `/climate_off` | command |
| POST | `/vehicles/:vin/schedule` `{ "delay": 60 }` | **server-side Unlock+Drive in N s** |
| GET | `/schedules` | pending schedules |
| DELETE | `/schedules/:id` | cancel a schedule |

Commands are sent **unsigned** (works for pre-2021 S/X). 2021+ cars need the
signing proxy — a later phase.

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
TOK=... # serverToken
curl -s localhost:8737/health
curl -s -H "Authorization: Bearer $TOK" localhost:8737/vehicles
curl -s -X POST -H "Authorization: Bearer $TOK" localhost:8737/vehicles/<VIN>/schedule -d '{"delay":60}'
```
