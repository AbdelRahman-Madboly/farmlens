# Changelog

All notable changes to this project are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `docs/SETUP-GUIDE.md`: step-by-step setup for a new user, from Raspberry Pi
  Imager settings to the live camera, with screenshots and troubleshooting.
- `install.sh` at the repository root: a shorter install command for the Pi.
- `farmlens-wifi.timer` on the Pi: moves it to the FarmLens hotspot within
  about 30 s when the hotspot comes on after the Pi booted on another network.
- `node/rpi/status.sh`: one-screen health check (service, API, camera, Wi-Fi,
  log); `setup.sh` prints where it is.
- Case CAD in `hardware/pi-cam-case`: STEP files for the parts and the
  assembly, the parametric build123d source with a standalone `build.py`, a
  sliced Bambu Lab A1 plate with the nut pauses, and CAD renders.
- README: app and web dashboard screenshots, a diagram of how the parts
  connect, a quick start and a hardware section with the case files.

### Fixed

- Case README: the saddle screws are M3 x 16, not M3 x 10 (from the CAD
  dimensions). Added the screw totals and the nut size.
- A Pi whose camera was not seen during setup stayed on simulated frames for
  good. The node now detects the camera at every start (`CAMERA_BACKEND=auto`,
  written by `setup.sh`), reports why it fell back (`camera_note` in
  `/api/status`, shown by `status.sh`), and `setup.sh` turns on
  `camera_auto_detect=1` in the boot config when it is off.

### Changed

- README restyled to the shared layout: centred header with badges, why,
  highlights, status and roadmap.
- Setup flow in the README and the guide: install over normal Wi-Fi, then turn
  on the hotspot and reboot.
- Web dashboard: the camera view is at most 640 px wide, so the readings stay
  on screen on a laptop.

## [0.2.0] - 2026-11-02

Makes the Pi and the phone app work together for a field demo over a phone
hotspot.

### Added

- `node/rpi/setup.sh`: one script that installs and updates the node. It pulls
  the latest code, installs packages, moves settings from an older install,
  finds the camera, names the Pi `farmlens`, saves the phone hotspot so the Pi
  joins it at every boot, and installs a service that starts on boot.
- `node/rpi/bootstrap.sh`: one command that clones or updates the repo on the
  Pi and runs `setup.sh`.
- `GET /api/stream`: live MJPEG camera stream. The web dashboard uses it.
- `/api/status` now sends `service`, `node_name`, `version` and `stream`.
- App: "Find my node" scans the phone's Wi-Fi and hotspot network and connects
  to the node. On start the app finds the node again if its address changed.
- App: the Camera tab plays the live stream, reconnects after a drop, falls
  back to snapshots for older nodes, and pauses when the tab is not shown.
- `.github/workflows/release-apk.yml`: pushing a `v*` tag builds the APK and
  attaches `farmlens.apk` to a GitHub release.

### Fixed

- Pi camera module frames had red and blue swapped (picamera2 `RGB888` is
  stored as BGR). The camera now uses `BGR888`, which gives RGB arrays.
- Camera captures are serialised, so the cycle loop, snapshots and streams do
  not use the camera at the same time.

### Changed

- `install.sh` now runs `setup.sh`.
- Android app label is "FarmLens".

## [0.1.0] - 2026-11-01

First public prototype. Runs end to end on simulated data. No trained model,
dataset, assembled hardware or measurement is included.

### Added

- Monorepo layout: `node/rpi` (Pi server), `node/firmware` (ESP32), `app`
  (Flutter), `docs`.
- `node/rpi/mock_sensor.py` and `SENSOR_MODE=mock|esp32`: the server generates
  moving sensor readings itself, so the demo no longer shows frozen values.
- `CAMERA_BACKEND=mock` with synthetic, labelled frames.
- Optional `API_KEY` for `POST /api/sensor` and `POST /api/settings`
  (`X-API-Key` header), supported by the app and the firmware.
- Request validation for both write endpoints; cycle ids are validated before
  they reach the filesystem.
- `/api/status` reports `ai_mode`, `sensor_mode`, `simulated` and
  `auth_required`; the web dashboard shows a banner while data is simulated.
- Firmware `lib/sensor_model`: pure sensor logic shared with host-side Unity
  tests; optional analog-probe build (`USE_ANALOG_PROBES`).
- App: optional API key on the Connect screen, cycle images in Log detail.
- Tests: 55 pytest tests (including a dummy TFLite model), 7 Unity tests,
  42 Flutter unit and widget tests. GitHub Actions workflow running all of them
  plus the ESP32 build.
- `SECURITY.md`, `docs/ARCHITECTURE.md`, `docs/roadmap.md`, MIT licence.

### Changed

- Inference: mock mode is the default; `AI_MODE=tflite` falls back to mock with
  a logged reason when the model file, the runtime or a `[1, N]` output is
  missing. The score passed to fusion is now a disease score (a confident
  healthy result no longer raises the combined score), and low-confidence
  results are reported as `none`.
- Mock inference only reports disease labels when its score is above 0.6.
- `API_HOST` defaults to `127.0.0.1`; `.env.example` sets `0.0.0.0` for the Pi.
- The ESP32 is only reported as connected when real ESP32 posts arrive.
- Firmware reads the Pi address, node id and key from `secrets.h` instead of a
  hard-coded LAN address; ArduinoJson pinned to v7.
- `install.sh` installs from `requirements.txt` and creates `.env`.

### Fixed

- App log entries now read `cycle_id`, so opening a cycle from the Log tab works.
- Opening an alert that is not yet in the loaded log no longer shows
  "Cycle not found".
- Alert cards threw a paint error (rounded border with mixed colours).
- Mock overlay label no longer shows the disease score as the label's confidence.

### Removed

- Dark mode and push notification toggles in the app: neither was implemented.
- Unused app dependencies (`mqtt_client`, `fl_chart`, `intl`,
  `flutter_local_notifications`, `path_provider`).
- The Node.js mock server: the Pi server in mock mode replaces it.
- The design-reference export and planning documents from the private
  repositories.
