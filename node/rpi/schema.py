"""
FarmLens API Schemas
=====================
CycleResult documents the dict returned by fusion.compute(): the payload
served at GET /api/live, stored per cycle in SQLite (logger.py), and the body
a future multi-node platform would ingest (see docs/roadmap.md).
fusion.compute() returns a plain dict; tests validate it against CycleResult.

SensorReading and SettingsUpdate validate the bodies of the two write
endpoints, so a malformed request gets a 422 instead of a server error.
"""
from pydantic import BaseModel, Field


class CycleResult(BaseModel):
    ts: int                      # Unix timestamp of this fusion cycle
    node_id: str                 # NODE_ID of the reporting node
    moisture_raw: int            # Raw ADC reading, soil moisture probe
    moisture_pct: float          # Soil moisture, 0-100 %
    water_raw: int               # Raw ADC reading, water level probe
    water_pct: float             # Water level, 0-100 %
    moisture_stress: int         # 1 if moisture_pct < MOISTURE_STRESS_THRESHOLD, else 0
    water_stress: int            # 1 if water_pct < WATER_STRESS_THRESHOLD, else 0
    cs: float                    # Soil stress score: 0.6*moisture_stress + 0.4*water_stress
    cv: float                    # Visual disease score, 0-1 (mock or TFLite)
    ccombined: float             # w1*cv + w2*cs, clamped to [0, 1]
    alert: bool                  # True if ccombined > theta
    detection_class: str         # e.g. "Tomato_healthy", "Tomato_Late_blight", "none"
    detection_conf: float        # Same value as cv (kept distinct for API clarity)
    cycle_id: str                # f"{NODE_ID}-{YYYYmmdd-HHMMSS}", unique per cycle
    has_image: bool              # True if a JPEG was saved for this cycle
    fault: int                   # 1 if no sensor reading received yet, else 0
    sensor_source: str           # "mock", "esp32" or "none"


class SensorReading(BaseModel):
    """Body of POST /api/sensor, as sent by the ESP32 firmware."""
    node_id: str | None = None
    moisture_raw: int = Field(2048, ge=0, le=4095)
    moisture_pct: float = Field(..., ge=0, le=100)
    water_raw: int = Field(2048, ge=0, le=4095)
    water_pct: float = Field(..., ge=0, le=100)
    ts: int = 0
    fault: int = Field(0, ge=0, le=1)
    # Older firmware also sends these; the server recomputes them.
    moisture_stress: int | None = None
    water_stress: int | None = None


class SettingsUpdate(BaseModel):
    """Body of POST /api/settings. Every field is optional."""
    w1: float | None = Field(None, ge=0, le=1)
    w2: float | None = Field(None, ge=0, le=1)
    theta: float | None = Field(None, ge=0, le=1)
    crop_type: str | None = Field(None, min_length=1, max_length=32)
