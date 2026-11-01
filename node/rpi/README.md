# FarmLens node server (`node/rpi`)

FastAPI server that runs a capture, infer, fuse and log cycle every 30 seconds
and serves the results to the app and a web dashboard.

All three inputs have a mock mode, and mock is the default, so the server runs
on a laptop with no hardware:

| Input | Default | Real option |
|---|---|---|
| Sensors | `SENSOR_MODE=mock` (simulated readings, `mock_sensor.py`) | `esp32`: wait for `POST /api/sensor` from the firmware |
| Inference | `AI_MODE=mock` (random-walk score) | `tflite`: classifier in `models/`. No model is shipped |
| Camera | `CAMERA_BACKEND=mock` (synthetic frames) | `picamera2` or `opencv` |

## Run locally

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
python main.py
```

Dashboard at `http://127.0.0.1:8000`. Settings are read from environment
variables, then from `.env` (copy `.env.example`).

## Test

```bash
pytest
```

The tests use a temporary SQLite database and image folder, force all mock
modes, and cover fusion scoring, the logger, the mock sensor, inference (mock
mode, missing model, missing runtime, bad output shapes, post-processing, and
one run of a dummy model) and the API through FastAPI's TestClient, including
the API key and one full cycle end to end.

`tests/fixtures/dummy_classifier.tflite` is a 3 KB untrained network made by
`tests/fixtures/make_dummy_model.py`. It only proves the TFLite code path runs;
its predictions mean nothing.

## Install on a Raspberry Pi

Raspberry Pi OS Bookworm, 64-bit. This has not been run on a Pi for this
release.

```bash
scp -r node/rpi pi@<pi-address>:~/farmlens-rpi
ssh pi@<pi-address>
cd ~/farmlens-rpi
./install.sh        # apt packages, venv, .env from .env.example, systemd service
```

Then edit `.env` (for example `CAMERA_BACKEND=picamera2`, `SENSOR_MODE=esp32`)
and `sudo systemctl restart farmlens`. Logs: `journalctl -u farmlens -f`.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `NODE_ID` | `FL-001` | Node identifier, also used in cycle ids |
| `API_HOST` | `127.0.0.1` | Use `0.0.0.0` on the Pi so phones can connect |
| `API_PORT` | `8000` | HTTP port |
| `API_KEY` | empty | If set, write endpoints need `X-API-Key` (see `SECURITY.md`) |
| `SENSOR_MODE` | `mock` | `mock` or `esp32` |
| `SENSOR_INTERVAL_S` | `5` | Mock sensor update interval |
| `AI_MODE` | `mock` | `mock` or `tflite` |
| `MODEL_FILE` | `plant_disease.tflite` | Model file name inside `models/` |
| `CONFIDENCE_THRESHOLD` | `0.25` | Below this top probability the result is `none` |
| `CAMERA_BACKEND` | `mock` | `mock`, `picamera2` or `opencv` |
| `CYCLE_INTERVAL_S` | `30` | Seconds between cycles |
| `DEFAULT_W1`, `DEFAULT_W2`, `DEFAULT_THETA` | `0.6`, `0.4`, `0.5` | Fusion defaults |
| `MOISTURE_STRESS_THRESHOLD`, `WATER_STRESS_THRESHOLD` | `30`, `20` | Stress thresholds in % |

## Using a TFLite model

No model ships with this repository. To try one:

1. `pip install ai-edge-litert` (or `tflite-runtime`).
2. Put a classifier with input `[1, H, W, 3]` and output `[1, N]` at
   `models/plant_disease.tflite`. Its output order must match
   `DISEASE_CLASSES` in `config.py`, or edit that list.
3. Set `AI_MODE=tflite` and restart. `/api/status` reports `ai_mode: tflite`
   only if the model loaded; otherwise the log says why it fell back to mock.

## Files

| File | Role |
|---|---|
| `main.py` | Entry point, cycle loop, starts the mock sensor |
| `config.py` | Settings from environment and `.env` |
| `mock_sensor.py` | Simulated sensor readings |
| `inference.py` | Mock and TFLite inference |
| `fusion.py` | Sensor store and fusion scoring |
| `camera.py` | Camera backends, overlay, JPEG helpers |
| `logger.py` | SQLite history, image paths |
| `api.py` | REST API and web dashboard |
| `schema.py` | Response and request models |
| `install.sh` | Raspberry Pi installer |
