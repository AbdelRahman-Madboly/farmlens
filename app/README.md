# FarmLens app (`app`)

Flutter companion app for a FarmLens node. It connects to the node's REST API
over the local network and shows live readings, alerts, the cycle log and the
camera frame.

**Status:** prototype. Tested with unit and widget tests and against the node
server in mock mode. Not tested on a physical phone for this release and not
published to any store. All data it shows today is simulated by the node.

## Run

```bash
flutter pub get
flutter run
```

Start the node first (see `../node/rpi/README.md`) with `API_HOST=0.0.0.0`.
On the Connect screen enter the node's address and port `8000`. An Android
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
| `test/widgets_test.dart` | Settings, Alerts, Log detail and Connect screens, including a connect flow against a mocked node |

## Screens

| Screen | What it shows |
|---|---|
| Connect | Node address, port and optional API key; recent addresses |
| Dashboard | Combined score, sensor cards, latest label, alert banner, offline state |
| Camera | `/api/snapshot` every 5 s. In mock mode the node draws a placeholder box labelled MOCK; it is not a detection |
| Alerts | Alert cycles seen while polling |
| Log | Cycle history from `/api/logs`, pull to refresh, export as JSON |
| Log detail | One cycle with its stored image |
| Settings | Fusion weight and alert threshold sliders, crop type, connection test |

## Layout

```
lib/
  main.dart, router.dart, theme.dart, constants.dart
  models/      LiveData, CycleLog, NodeStatus, FusionSettings, json_utils
  services/    ApiService
  providers/   Connection, Live, Log, Settings
  screens/     one file per screen
  utils/       formatters, validators
test/          unit and widget tests
```

The app has a light theme only.
