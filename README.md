# FarmLens

Crop-health node prototype: a Raspberry Pi server that combines a camera
image score with soil-moisture and water-level readings into one risk score,
an ESP32 firmware that sends sensor readings to it, and a Flutter app that
shows the result.

**Status: prototype / MVP on simulated data.** There is no trained model, no
dataset, no assembled hardware and no field measurement. Every number the
system shows today comes from simulators in this repository.

## Working now vs not built yet

| Area | Working now | Not built yet |
|---|---|---|
| Pi server (`node/rpi`) | FastAPI server, 30 s capture-infer-fuse-log cycle, SQLite history, JPEG per cycle, web dashboard, REST API used by the app | Running on a real Pi with a real camera has not been verified for this release |
| Sensors | `mock_sensor.py` generates moving moisture and water readings in-process (`SENSOR_MODE=mock`); `POST /api/sensor` accepts readings from the ESP32 | No probes wired or calibrated |
| Inference | Mock mode (random-walk score, default). TFLite classifier path with fallback to mock when no model or runtime is present | No trained model is shipped. The TFLite path is tested only with a dummy, untrained model generated for the tests |
| Camera | Mock backend (synthetic, labelled frames, default); picamera2 and OpenCV backends in code | Not tested against a physical camera in this release |
| Firmware (`node/firmware`) | Compiles for ESP32 (`esp32dev`); posts simulated readings over WiFi; optional analog-probe build | Not flashed or run on a board for this release |
| App (`app`) | Connect to a node, live dashboard, alerts, cycle log with images, camera tab, fusion settings, optional API key | Not published to any store; not tested on a physical phone for this release |
| Security | Optional API key on write endpoints | No TLS, no user accounts. LAN-only prototype, see [SECURITY.md](SECURITY.md) |
| Multi-node platform | - | Future work, see [docs/roadmap.md](docs/roadmap.md) |

## Run the demo (no hardware)

Needs Python 3.11+ and, for the app, Flutter 3.x.

```bash
cd node/rpi
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
python main.py                    # serves http://127.0.0.1:8000
```

Open `http://127.0.0.1:8000` for the web dashboard. It shows a banner while
any part of the data is simulated. Sensor values move every few seconds and a
new cycle is logged every 30 seconds (`CYCLE_INTERVAL_S` to change it).

To use the app, run the node with `API_HOST=0.0.0.0` so a phone or emulator on
the same network can reach it, then:

```bash
cd app
flutter pub get
flutter run
```

Enter the computer's LAN address and port `8000` on the Connect screen. An
Android emulator reaches the host machine at `10.0.2.2`.

## Repository layout

| Path | What it is |
|---|---|
| `node/rpi/` | Python/FastAPI server for the Raspberry Pi, with tests |
| `node/firmware/` | ESP32 firmware (PlatformIO), with host-side unit tests |
| `app/` | Flutter companion app, with unit and widget tests |
| `docs/ARCHITECTURE.md` | Data flow, fusion formula, API contract |
| `docs/roadmap.md` | Future work, including the multi-node platform |

## Fusion formula

```
Cs        = 0.6 * moisture_stress + 0.4 * water_stress
Ccombined = w1 * Cv + w2 * Cs        (defaults w1 = 0.6, w2 = 0.4)
Alert     = Ccombined > theta         (default theta = 0.5)
```

`Cv` is the visual disease score in [0, 1]. The weights and threshold are
starting values for the prototype, not tuned against data.

## Tests

| Part | Command | Result at v0.1.0 |
|---|---|---|
| Pi server | `cd node/rpi && pytest` | 55 passed |
| Firmware logic | `cd node/firmware && pio test -e native` | 7 passed |
| Firmware build | `cd node/firmware && pio run -e esp32dev` | builds |
| App | `cd app && flutter analyze && flutter test` | no issues, 42 passed |

CI runs all of these on every push, see `.github/workflows/ci.yml`.

## Licence

MIT, see [LICENSE](LICENSE). Credit: VINEX.
