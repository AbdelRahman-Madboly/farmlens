# Security

FarmLens is a **LAN-only prototype**. Do not expose a node to the internet.

## What the node does and does not protect

| Item | State |
|---|---|
| Transport | Plain HTTP. No TLS. Anyone on the network can read the traffic, including the API key. |
| Write endpoints (`POST /api/sensor`, `POST /api/settings`) | Open by default. Set `API_KEY` in `node/rpi/.env` to require the header `X-API-Key`. The key is compared in constant time. |
| Read endpoints (`/api/live`, `/api/logs`, `/api/image/*`, `/api/snapshot`, `/api/stream`, `/`) | Always open. Anyone who can reach the node can see readings and camera frames. |
| Bind address | `127.0.0.1` by default. `.env.example` sets `0.0.0.0` so phones on the LAN can connect. |
| Input validation | Request bodies are validated (types and ranges); bad input gets a 422. Image ids are restricted to `[A-Za-z0-9_-]`. |
| CORS | Any origin may call the API, so the dashboard and app work from any address. |
| Phone hotspot password | The demo default (`FarmLens` / `00000000`) is public in the README and `setup.sh`, so anyone nearby who reads it can join the hotspot while it is on. Turn the hotspot off after a demo, or pass your own with `--ssid` and `--password`; a custom password is stored only by NetworkManager on the Pi (`/etc/NetworkManager/system-connections/`, root only), never in the repository. |
| Secrets in git | `node/rpi/.env` and `node/firmware/include/secrets.h` are gitignored. Only `.example` files are committed. |

## Using the API key

1. Set `API_KEY=<long random string>` in `node/rpi/.env` and restart the node.
2. Put the same value in `API_KEY` in `node/firmware/include/secrets.h` and reflash.
3. Enter it in the app's Connect screen (API key field). The app stores it in
   the phone's shared preferences, unencrypted.

`GET /api/status` reports `auth_required: true` when a key is set.

## Before any real deployment

Add TLS (for example a reverse proxy on the Pi), authenticate read endpoints,
and move from one shared key to per-device keys. The roadmap in
`docs/roadmap.md` lists this as future work.

## Reporting a problem

Open a private security advisory on the repository, or contact the VINEX
maintainers through the organisation profile. Please do not file public issues
for security problems.
