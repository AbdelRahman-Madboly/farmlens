# FarmLens node

The hardware side of FarmLens.

| Folder | What it is |
|---|---|
| [`rpi/`](rpi/README.md) | Python/FastAPI server for a Raspberry Pi: camera, inference, sensor fusion, SQLite log, REST API and web dashboard on port 8000. Runs on any computer in mock mode. |
| [`firmware/`](firmware/README.md) | ESP32 firmware (PlatformIO). Sends sensor readings to the Pi every 5 s. Optional: the Pi simulates readings without it. |

See [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) for the data flow and
API contract. Status: prototype on simulated data; no hardware has been
assembled.
