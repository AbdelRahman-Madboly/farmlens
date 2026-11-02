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
the API key, the MJPEG stream and one full cycle end to end.

`tests/fixtures/dummy_classifier.tflite` is a 3 KB untrained network made by
`tests/fixtures/make_dummy_model.py`. It only proves the TFLite code path runs;
its predictions mean nothing.

## Install or update on a Raspberry Pi

Raspberry Pi OS Bookworm or newer (it uses NetworkManager). On the Pi, as your
normal user:

```bash
curl -fsSL https://raw.githubusercontent.com/AbdelRahman-Madboly/farmlens/main/node/rpi/bootstrap.sh | bash
```

or, from a clone, `./setup.sh`. The step-by-step guide for a demo over a phone
hotspot is in the [main README](../../README.md#demo-with-a-raspberry-pi-and-a-phone-hotspot).

`setup.sh` is safe to run again; that is how the node is updated. It:

1. runs `git pull` and restarts itself if the script changed
2. stops an older `farmlens` service and copies its `.env` and `farmlens.db`
   (also from the old `~/farmlens-rpi` location)
3. installs apt packages (python3-picamera2, OpenCV, avahi) and the venv
4. finds the camera (`picamera2`, then a USB webcam, else `mock`) and writes
   `.env` with `API_HOST=0.0.0.0`
5. sets the hostname to `farmlens`, so the node answers at `farmlens.local`
6. saves the phone hotspot as the NetworkManager connection
   `farmlens-hotspot` with priority 100, so the Pi joins it at every boot.
   The default hotspot is name `FarmLens`, password `00000000`
7. installs and starts the `farmlens` systemd service

| Option | Meaning |
|---|---|
| `--ssid NAME --password PASS` | A hotspot other than the default `FarmLens` / `00000000` |
| `--ask-wifi` | Ask for the hotspot name and password |
| `--skip-wifi` | Leave Wi-Fi settings alone |
| `--connect-now` | Switch to the hotspot now. Without it, a Pi already on Wi-Fi switches at the next boot, so an SSH session over that Wi-Fi is not cut |
| `--country CC` | Wi-Fi country (default `EG`) |
| `--hostname NAME` | Hostname (default `farmlens`) |
| `--camera MODE` | `auto` (default), `picamera2`, `opencv` or `mock` |
| `--no-pull`, `--no-apt` | Skip `git pull` or apt, for quick re-runs |

Health check: `./status.sh` shows the service, camera, Wi-Fi and last log lines on one screen.

Useful commands: `journalctl -u farmlens -f` (live log),
`sudo systemctl restart farmlens`, `nmcli connection show` (saved networks).

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
| `CAMERA_BACKEND` | `mock` | `mock`, `picamera2` or `opencv`. `setup.sh` sets it from the camera it finds |
| `STREAM_FPS` | `10` | Frames per second of `/api/stream` |
| `STREAM_QUALITY` | `70` | JPEG quality of `/api/stream` (1 to 100) |
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
| `api.py` | REST API, MJPEG stream and web dashboard |
| `schema.py` | Response and request models |
| `setup.sh` | Raspberry Pi install and update |
| `bootstrap.sh` | Clones or updates the repo, then runs `setup.sh` |
| `install.sh` | Old name, runs `setup.sh` |
| `status.sh` | Health check: service, API, camera, Wi-Fi, log |
