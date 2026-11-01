# FarmLens firmware (`node/firmware`)

ESP32 sensor bridge. Every 5 seconds it builds a sensor reading and posts it as
JSON to the Pi server's `POST /api/sensor`.

**Status:** compiles for `esp32dev`. It has not been flashed or run on a board
for this release. By default it sends simulated readings (the same curves as
the Pi's `SENSOR_MODE=mock`). A build with `-D USE_ANALOG_PROBES` reads two
analog probes on GPIO 34 and 35 instead; that path is untested on real probes.

## Configure

```bash
cp include/secrets.h.example include/secrets.h
```

Edit `include/secrets.h`: WiFi SSID and password, the Pi's address
(`RPI_HOST`), `NODE_ID`, and `API_KEY` if the Pi has one set. `secrets.h` is
gitignored. Without it the firmware still compiles with placeholder values and
a warning, which is what CI does.

## Build, flash, monitor

```bash
pio run -e esp32dev                    # build
pio run -e esp32dev -t upload          # flash
pio device monitor                     # serial log, 115200 baud
```

To build the analog-probe variant:

```bash
pio run -e esp32dev -t clean           # PlatformIO does not rebuild on env flag changes
PLATFORMIO_BUILD_FLAGS=-DUSE_ANALOG_PROBES pio run -e esp32dev
```

## Test

```bash
pio test -e native
```

Runs the Unity tests in `test/test_sensor_model` on the host against
`lib/sensor_model/sensor_model.h`: the mock curves, ADC conversion, stress
thresholds and the Cs score.

## LED

| Pattern | Meaning |
|---|---|
| 2 slow blinks | Booting |
| Fast toggling | Connecting to WiFi |
| Solid on | Connected |
| 1 quick blink every 5 s | Reading posted |
| 3 rapid blinks | Post failed |
