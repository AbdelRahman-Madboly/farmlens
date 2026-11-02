# FarmLens

<img src="docs/readme-icon.png" width="96" align="right" alt="FarmLens icon">

Crop-health node prototype: a Raspberry Pi server that combines a camera
image score with soil-moisture and water-level readings into one risk score,
an ESP32 firmware that sends sensor readings to it, and a Flutter app that
shows the result.

**Status: prototype / MVP on simulated data.** There is no trained model, no
dataset and no field measurement. The camera can be real (Pi camera module or
USB webcam); sensor readings and the disease score still come from
simulators in this repository.

**Download the Android app:**
[farmlens.apk](https://github.com/AbdelRahman-Madboly/farmlens/releases/latest/download/farmlens.apk)
(all versions on the [releases page](https://github.com/AbdelRahman-Madboly/farmlens/releases)).

| Case design | In the field | Close up |
|---|---|---|
| ![Pi camera case on a 100 mm trunk](hardware/pi-cam-case/images/pi-cam-case-on-trunk.png) | ![FarmLens node in a tomato field](hardware/pi-cam-case/images/concept-field.jpg) | ![FarmLens case on a trunk](hardware/pi-cam-case/images/concept-on-trunk.jpg) |

The first picture is the 3D design. The other two are concept images of the planned field setup,
not photos of a built unit.

## Demo with a Raspberry Pi and a phone hotspot

The Pi joins the phone's hotspot, and the app on the same phone finds it and
shows the live camera. Nothing else is needed: no router, no laptop, no IP
addresses to type.

### One-time setup

**1. Install the app on the Android phone.** Open
[farmlens.apk](https://github.com/AbdelRahman-Madboly/farmlens/releases/latest/download/farmlens.apk)
on the phone, download it, open it and allow "install from this source" when
Android asks. If an older FarmLens is installed and Android refuses to update
it, uninstall the old one first.

**2. Set up the phone hotspot.** The Pi is set up to join one hotspot by
default, so set the phone's hotspot settings to exactly this:

| Setting | Value |
|---|---|
| Hotspot name (network name, SSID) | `FarmLens` (capital F and L) |
| Password | `00000000` (eight zeros) |
| Security | WPA2-Personal (or "WPA2/WPA3"). Not WPA3-only, most Pis cannot join it |
| Band | 2.4 GHz (needed for Pi Zero 2 W and Pi 3; safe for every Pi) |

> **Note:** this name and password are public in this README. Turn the hotspot
> off after the demo. To use your own name and password instead, add
> `--ssid "<name>" --password "<password>"` to the setup command in step 4.

**3. Open a terminal on the Pi.** Either plug in a screen and keyboard, or
SSH from a laptop on the same network as the Pi (`ssh <user>@<hostname>.local`,
for example `ssh pi@raspberrypi.local`, or `ssh pi@farmlens.local` after the
first setup). The Pi needs internet for this step: turn the hotspot on with
mobile data, or use home Wi-Fi or Ethernet. With only a keyboard and no Wi-Fi
yet, run `sudo nmtui` and join a network first.

**4. Run the setup command on the Pi.** Copy this line, paste it into the Pi
terminal and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/AbdelRahman-Madboly/farmlens/main/node/rpi/bootstrap.sh | bash
```

It downloads the project to `~/farmlens` (or updates it), installs everything,
finds the camera, saves the `FarmLens` hotspot, and makes the node start on
every boot. Nothing has to be typed except, maybe, the Pi user's password for
`sudo`. It takes about five to ten minutes the first time and ends with
"FarmLens node is running".

The same with git, if you prefer:

```bash
git clone https://github.com/AbdelRahman-Madboly/farmlens.git ~/farmlens
~/farmlens/node/rpi/setup.sh
```

**5. Reboot the Pi with the hotspot on:** `sudo reboot`. About a minute later
the hotspot's "connected devices" list shows `farmlens`.

**6. Open the FarmLens app.** It finds the node by itself and opens the
dashboard. If it shows the Connect screen, tap **Find my node**. The
**Camera** tab shows the live stream.

### Every demo after that

1. Turn on the phone hotspot (`FarmLens` / `00000000`).
2. Power on the Pi and wait about a minute.
3. Open the FarmLens app.

The node starts on every boot and joins the hotspot by itself. The app finds
it again even if its address changed.

### Using the app

| Screen | What to do there |
|---|---|
| Dashboard | The combined risk score, the moisture and water cards and the latest label. An alert banner appears when the score passes the alert threshold |
| Camera | The live stream from the Pi camera with its frame rate. It reconnects by itself after a drop |
| Alerts | Every cycle that passed the threshold while the app was open |
| Log | One row per 30 s cycle. Pull down to refresh, tap a row to see that cycle's image and numbers, export the list as JSON |
| Settings | Move the two weight sliders and the threshold, pick the crop, test the connection. Saving writes the values to the node |
| Connect | Opens when no node is found: **Find my node** scans again, or type the address and port `8000` |

### Update the Pi

Run the same command from step 4 again (or `~/farmlens/node/rpi/setup.sh`).
It pulls the latest code, keeps the settings, and restarts the node. An older install
(the old `install.sh`, or a copy in `~/farmlens-rpi`) is replaced and its
`.env` and history are carried over.

### If something does not work

| Problem | What to do |
|---|---|
| The Pi does not appear in the hotspot's connected devices | Check the hotspot name is exactly `FarmLens`, the password `00000000`, the band 2.4 GHz and the security WPA2. On the Pi run `nmcli device wifi list` to see if it sees the hotspot, then `sudo nmcli connection up farmlens-hotspot`. For a different hotspot run `~/farmlens/node/rpi/setup.sh --no-apt --ssid "<name>" --password "<password>"` |
| The app says "No node found" | Wait a minute after power on and try again. Make sure the phone running the app is the one sharing the hotspot (or on the same Wi-Fi as the Pi). As a fallback, find the Pi's address in the hotspot's connected devices list and type it in the Connect screen, port `8000` |
| The camera shows "Simulated frames" | The camera was not found. Power off, check the ribbon cable is pushed fully into the camera port on both ends, then run `~/farmlens/node/rpi/setup.sh --no-apt` again |
| The stream is slow | Set `STREAM_FPS=5` or `STREAM_QUALITY=50` in `~/farmlens/node/rpi/.env`, then `sudo systemctl restart farmlens` |
| Anything else | `journalctl -u farmlens -n 50` shows the node's log. `sudo systemctl restart farmlens` restarts it |

You can also open `http://farmlens.local:8000` in the phone's browser for the
web dashboard.

## Working now vs not built yet

| Area | Working now | Not built yet |
|---|---|---|
| Pi server (`node/rpi`) | FastAPI server, 30 s capture-infer-fuse-log cycle, SQLite history, JPEG per cycle, live MJPEG stream, web dashboard, REST API used by the app. `setup.sh` installs or updates it, joins a phone hotspot and starts it on boot | `setup.sh` has not yet been run on a physical Pi for this release |
| Sensors | `mock_sensor.py` generates moving moisture and water readings in-process (`SENSOR_MODE=mock`); `POST /api/sensor` accepts readings from the ESP32 | No probes wired or calibrated |
| Inference | Mock mode (random-walk score, default). TFLite classifier path with fallback to mock when no model or runtime is present | No trained model is shipped. The TFLite path is tested only with a dummy, untrained model generated for the tests |
| Camera | Mock backend (synthetic, labelled frames); picamera2 and OpenCV backends. `setup.sh` picks the one it finds | Not yet tested against a physical camera |
| Firmware (`node/firmware`) | Compiles for ESP32 (`esp32dev`); posts simulated readings over WiFi; optional analog-probe build | Not flashed or run on a board for this release |
| App (`app`) | Finds the node on the phone's Wi-Fi or hotspot, live dashboard, alerts, cycle log with images, live camera stream, fusion settings, optional API key. APK on the releases page | Not in any store; not yet tested on a physical phone |
| Security | Optional API key on write endpoints | No TLS, no user accounts. LAN-only prototype, see [SECURITY.md](SECURITY.md) |
| Multi-node platform | - | Future work, see [docs/roadmap.md](docs/roadmap.md) |

## Run the demo on a computer (no hardware)

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

## Hardware

| Part | Used | Notes |
|---|---|---|
| Computer | Raspberry Pi 4 Model B | Runs the FastAPI node, camera capture and the web dashboard |
| Camera | Raspberry Pi camera module v1.3, or a USB webcam | picamera2 or OpenCV, picked by `setup.sh` |
| Sensor board | ESP32 (`esp32dev`) | Sends moisture and water readings to `POST /api/sensor`; simulated readings by default |
| Case | 3D-printed PETG case with rain hood and a tree saddle | STLs, part list and screws in [`hardware/pi-cam-case`](hardware/pi-cam-case) |

## Repository layout

| Path | What it is |
|---|---|
| `node/rpi/` | Python/FastAPI server for the Raspberry Pi, with tests. `setup.sh` and `bootstrap.sh` install it |
| `node/firmware/` | ESP32 firmware (PlatformIO), with host-side unit tests |
| `app/` | Flutter companion app, with unit and widget tests |
| `hardware/pi-cam-case/` | Printable case for the Pi and camera: STLs, pictures, part list |
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

| Part | Command | Result at v0.2.0 |
|---|---|---|
| Pi server | `cd node/rpi && pytest` | 59 passed |
| Firmware logic | `cd node/firmware && pio test -e native` | 7 passed |
| Firmware build | `cd node/firmware && pio run -e esp32dev` | builds |
| App | `cd app && flutter analyze && flutter test` | no issues, 62 passed |

CI runs all of these on every push, see `.github/workflows/ci.yml`.

## Release the app

Push a version tag and GitHub builds the APK and attaches it to a release:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

`.github/workflows/release-apk.yml` runs the tests, builds
`farmlens.apk`, and publishes it. The download link at the top of this file
always points to the newest release. The APK is signed with a build-time debug
key, so a phone may need the old version uninstalled before a new one installs.

## Licence

MIT, see [LICENSE](LICENSE). Credit: VINEX.

## Author

Designed and built by Abdel Rahman Mohamad EL-Sayed ([AbdelRahman-Madboly](https://github.com/AbdelRahman-Madboly) on GitHub) as a VINEX product.
