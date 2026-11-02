# Architecture

## Components

```
+------------------+  POST /api/sensor   +-------------------+   REST, port 8000   +-------------+
| node/firmware    | ------------------> | node/rpi          | <-----------------> | app         |
| ESP32 bridge     |  every 5 s          | FastAPI server    |                     | Flutter     |
| (optional)       |                     | + web dashboard   |                     |             |
+------------------+                     +-------------------+                     +-------------+
```

The ESP32 is optional. With `SENSOR_MODE=mock` (the default) the Pi server
generates its own readings and the whole system runs on one computer.

## Data flow inside `node/rpi`

```
SENSOR_MODE=mock:  mock_sensor.py thread  --+
                                            +--> fusion.update_sensor(reading, source)
SENSOR_MODE=esp32: POST /api/sensor -------+         (lock-protected store)
                                                          |
main.py cycle loop, every CYCLE_INTERVAL_S:               v
  camera.capture() -> inference.run() -> fusion.compute() -> camera.draw_overlay()
                                                          |
                                     logger.save_cycle() (SQLite) + JPEG per cycle
                                                          |
                                     api.update_latest() -> GET /api/live, /api/logs
```

`fusion.update_sensor()` is the single entry point for readings. Each reading
is tagged with its source (`mock` or `esp32`), and `GET /api/status` only
reports `esp32_connected: true` for real ESP32 posts.

## Modes

| Setting | Default | Options | Notes |
|---|---|---|---|
| `SENSOR_MODE` | `mock` | `mock`, `esp32` | `mock` runs `mock_sensor.py`: moisture 20-80 % on a 300 s sine, water 20-70 % on a 240 s sine, plus small noise. Same curves as the firmware's `lib/sensor_model`. |
| `AI_MODE` | `mock` | `mock`, `tflite` | `mock` is a random walk of the disease score. `tflite` loads a classifier from `models/`; if the file, the runtime or the expected `[1, N]` output is missing it logs why and falls back to `mock`. No trained model is shipped. |
| `CAMERA_BACKEND` | `mock` | `mock`, `picamera2`, `opencv` | `mock` draws a synthetic leaf labelled "SIMULATED FRAME". |

In mock inference mode the overlay draws a fixed placeholder box labelled
"MOCK MODE". It is not a detection. The TFLite path is a whole-image
classifier and draws no box.

## Visual score Cv

`InferenceEngine.run()` returns `(label, cv, latency_ms)`, where `cv` is a
disease score in [0, 1]:

| Model output | Label | cv |
|---|---|---|
| Top class is a disease, probability p | that class | p |
| Top class is healthy, probability p | that class | 1 - p |
| Top probability below `CONFIDENCE_THRESHOLD` | `none` | 0 |

Logits are passed through softmax; quantised outputs are dequantised.

## Fusion formula

```
moisture_stress = 1 if moisture_pct < MOISTURE_STRESS_THRESHOLD (30) else 0
water_stress    = 1 if water_pct    < WATER_STRESS_THRESHOLD (20)    else 0
Cs              = 0.6 * moisture_stress + 0.4 * water_stress
Ccombined       = clamp(w1 * Cv + w2 * Cs, 0, 1)      defaults w1 = 0.6, w2 = 0.4
Alert           = Ccombined > theta                    default theta = 0.5
```

`w1`, `w2`, `theta` and `crop_type` can be changed at runtime with
`POST /api/settings`. The values are prototype defaults, not tuned against data.

## API contract

| Method | Endpoint | Description |
|---|---|---|
| GET | `/` | Web dashboard |
| GET | `/api/status` | `service: farmlens` (used by app discovery), node id and name, version, `stream`, `ai_mode`, `sensor_mode`, `simulated`, uptime, cycle count, ESP32 and camera state, `auth_required` |
| POST | `/api/sensor` | Sensor reading from the ESP32. Validated; needs `X-API-Key` if `API_KEY` is set |
| GET | `/api/live` | Latest cycle (see `schema.CycleResult`). Before the first cycle: current sensor values and `detection_class: "none"` |
| GET | `/api/logs?limit=50` | Cycle history, newest first, limit clamped to 1-200 |
| GET | `/api/image/{cycle_id}` | JPEG for a cycle; 400 for a malformed id, 404 if missing |
| GET | `/api/snapshot` | Fresh camera frame as JPEG |
| GET | `/api/stream` | Live MJPEG stream (`multipart/x-mixed-replace`), `STREAM_FPS` frames per second (default 10). Optional `fps` and `frames` query parameters |
| GET | `/api/settings` | Fusion weights and crop type |
| POST | `/api/settings` | Partial update of `w1`, `w2`, `theta` (0-1) and `crop_type`. Needs `X-API-Key` if set |

The cycle payload is documented field by field in `node/rpi/schema.py`.

## App structure

```
ApiService (HTTP, injectable client, optional X-API-Key)
   |
   +-- ConnectionProvider   GET /api/status on connect
   +-- LiveProvider         polls /api/live every 5 s, de-duplicates alerts by
   |                        cycle id, marks the node offline after 3 failed polls
   +-- LogProvider          loads /api/logs when the Log tab opens
   +-- SettingsProvider     node address, API key, fusion settings
   |
Screens: Dashboard, Camera, Alerts, Log, Log detail, Settings, Connect
```

## Firmware structure

| File | Role |
|---|---|
| `lib/sensor_model/sensor_model.h` | Pure logic: mock curves, ADC to percent conversion, stress flags, Cs. No Arduino headers, so it is unit-tested on the host. |
| `src/main.cpp` | WiFi, LED, JSON and HTTP POST to the Pi every 5 s. |
| `include/secrets.h` | WiFi credentials, Pi address, node id, API key. Gitignored; copy from `secrets.h.example`. |
