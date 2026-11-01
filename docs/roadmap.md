# Roadmap

Everything on this page is **future work**. None of it exists in this
repository yet.

## Near term: from simulation to one real node

| Step | What it needs |
|---|---|
| Run the server on a Raspberry Pi 4 with a camera | Pi, camera module, `install.sh` |
| Wire and calibrate soil-moisture and water-level probes | ESP32, two analog probes, real `MOISTURE_DRY/WET` and `WATER_DRY/WET` values |
| Collect and label images, train a classifier, export to TFLite | A dataset with a licence that allows this use, a training pipeline, an evaluation on held-out data |
| Measure the system | Inference latency and power on the Pi, measured rather than estimated |
| Harden the API | TLS, authenticated reads, per-device keys (see `SECURITY.md`) |

Results from any of these steps go into the README only after they have been
measured.

## Later: multi-node platform

A central service that collects cycles from several field nodes. It is only
worth building once two or more real nodes exist.

```
node 1 --+
node 2 --+--> POST /api/v1/nodes/{node_id}/telemetry --> platform --> web dashboard
node N --+        (per-node API key)                     (history, alerts)
```

Sketch:

- Ingestion body: the same `CycleResult` payload the node already serves at
  `/api/live` (`node/rpi/schema.py`), so there is one schema to maintain.
- Auth: a per-node token issued at registration and sent as `X-API-Key`, the
  same header the node already accepts.
- Data model: a `nodes` table (id, name, location, key hash, last seen) and a
  `cycles` table mirroring `CycleResult`, plus an image URL.
- Stack: Python/FastAPI to match the node, SQLite first, Postgres when data
  volume needs it.
