# FarmLens app (`app`)

Flutter companion app for a FarmLens node. It connects to the node's REST API
over the local network and shows live readings, alerts, the cycle log and the
live camera stream.

Download the built app:
[farmlens.apk](https://github.com/AbdelRahman-Madboly/farmlens/releases/latest/download/farmlens.apk).
Pushing a `v*` tag builds a new one (`.github/workflows/release-apk.yml`).

**Status:** prototype. Tested with unit and widget tests and against the node
server in mock mode. Not tested on a physical phone for this release and not
published to any store. All data it shows today is simulated by the node.

## Run

```bash
flutter pub get
flutter run
```

Start the node first (see `../node/rpi/README.md`) with `API_HOST=0.0.0.0`.
On the Connect screen tap **Find my node**, or enter the node's address and
port `8000`. An Android
emulator reaches the host computer at `10.0.2.2`. If the node has `API_KEY`
set, enter it in the optional API key field; it is sent as `X-API-Key` when
saving settings.

## Test

```bash
flutter analyze
flutter test
```

| File | Covers |
|---|---|
| `test/models_test.dart` | JSON parsing of node payloads, lenient number handling, `cycle_id` mapping, round trips |
| `test/api_service_test.dart` | `ApiService` with a mocked HTTP client: success, errors, timeouts, API key header |
| `test/live_provider_test.dart` | Polling, alert de-duplication, offline after 3 failures, recovery, alert cap, timer start and stop |
| `test/formatters_validators_test.dart` | Label formatting, score colours, address and port validation |
| `test/mjpeg_stream_test.dart` | MJPEG parsing (frames split across chunks and markers, buffer limit) and the HTTP stream |
| `test/node_discovery_test.dart` | Subnet list from phone interfaces (hotspot first, carrier addresses skipped), probing, scan, de-duplication |
| `test/widgets_test.dart` | Settings, Alerts, Log detail, Connect (manual and Find my node), Splash rediscovery and Camera stream |

## Screens

| Screen | What it shows |
|---|---|
| Splash | Finds the node: saved address, `farmlens.local`, then a scan of the phone's Wi-Fi and hotspot subnets |
| Connect | Find my node (scan), or node address, port and optional API key; recent addresses |
| Dashboard | Combined score, sensor cards, latest label, alert banner, offline state |
| Camera | Live MJPEG stream from `/api/stream`, with fps; reconnects after a drop, falls back to `/api/snapshot` every 5 s for older nodes, pauses when the tab is hidden |
| Alerts | Alert cycles seen while polling |
| Log | Cycle history from `/api/logs`, pull to refresh, export as JSON |
| Log detail | One cycle with its stored image |
| Settings | Fusion weight and alert threshold sliders, crop type, connection test |

## Layout

```
lib/
  main.dart, router.dart, theme.dart, constants.dart
  models/      LiveData, CycleLog, NodeStatus, FusionSettings, json_utils
  services/    ApiService, NodeDiscovery, MJPEG stream
  providers/   Connection, Live, Log, Settings
  screens/     one file per screen
  utils/       formatters, validators
test/          unit and widget tests
```

The app has a light theme only.

## How the app finds the node

When the Pi is joined to the phone's own hotspot, the hotspot is one of the
phone's network interfaces. The app lists the phone's private IPv4 addresses
(`NetworkInterface.list`), and for each /24 subnet asks every address for
`GET :8000/api/status` with a short timeout, 64 at a time. A node is a host
whose answer has `service: farmlens` (older nodes: `node_id` plus
`camera_backend`). A full subnet takes a few seconds. The saved address and
`farmlens.local` are asked first, so a known node connects at once.
