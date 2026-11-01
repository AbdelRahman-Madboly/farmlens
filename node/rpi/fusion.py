"""
FarmLens Sensor Fusion
=======================
- Holds the latest sensor reading (from the ESP32 over POST /api/sensor, or
  from mock_sensor.py when SENSOR_MODE=mock)
- Combines the visual score (Cv) with the soil stress score (Cs)
- Computes Ccombined = w1*Cv + w2*Cs
- Fires an alert when Ccombined > theta

All state is lock-protected. Weights are editable live via POST /api/settings.
"""
import threading
import time
import logging

from config import (
    DEFAULT_W1, DEFAULT_W2, DEFAULT_THETA, DEFAULT_CROP,
    MOISTURE_STRESS_THRESHOLD, WATER_STRESS_THRESHOLD,
    NODE_ID,
)

log = logging.getLogger("farmlens.fusion")

_lock = threading.Lock()

# Seconds without an ESP32 packet before the ESP32 is reported as disconnected
ESP32_TIMEOUT_S = 30

SOURCE_NONE  = "none"
SOURCE_MOCK  = "mock"
SOURCE_ESP32 = "esp32"


def _initial_sensor() -> dict:
    return {
        "node_id":         NODE_ID,
        "moisture_raw":    2048,
        "moisture_pct":    50.0,
        "water_raw":       2048,
        "water_pct":       50.0,
        "ts":              0,
        "fault":           1,        # 1 = no sensor reading received yet
        "source":          SOURCE_NONE,
        "last_esp32_ts":   0.0,
    }


def _initial_settings() -> dict:
    return {
        "w1":        DEFAULT_W1,
        "w2":        DEFAULT_W2,
        "theta":     DEFAULT_THETA,
        "crop_type": DEFAULT_CROP,
    }


_sensor: dict = _initial_sensor()
_settings: dict = _initial_settings()
_cycle_count = 0


def reset():
    """Restore the initial state. Used by tests."""
    global _cycle_count
    with _lock:
        _sensor.clear()
        _sensor.update(_initial_sensor())
        _settings.clear()
        _settings.update(_initial_settings())
        _cycle_count = 0


def update_sensor(data: dict, source: str = SOURCE_ESP32):
    """Store a new sensor reading. `source` is "esp32" or "mock"."""
    with _lock:
        _sensor.update({
            "node_id":         str(data.get("node_id", NODE_ID)),
            "moisture_raw":    int(data.get("moisture_raw", 2048)),
            "moisture_pct":    float(data.get("moisture_pct", 50.0)),
            "water_raw":       int(data.get("water_raw", 2048)),
            "water_pct":       float(data.get("water_pct", 50.0)),
            "ts":              int(data.get("ts", 0)),
            "fault":           int(data.get("fault", 0)),
            "source":          source,
        })
        if source == SOURCE_ESP32:
            _sensor["last_esp32_ts"] = time.time()


def get_sensor() -> dict:
    with _lock:
        return dict(_sensor)


def get_settings() -> dict:
    with _lock:
        return dict(_settings)


def update_settings(data: dict):
    """Apply any of w1, w2, theta, crop_type present (and not None) in `data`."""
    with _lock:
        for key in ("w1", "w2", "theta"):
            if data.get(key) is not None:
                _settings[key] = float(data[key])
        if data.get("crop_type") is not None:
            _settings["crop_type"] = str(data["crop_type"])
        snapshot = dict(_settings)
    log.info("Settings updated: %s", snapshot)


def stress_flags(moisture_pct: float, water_pct: float) -> tuple[int, int]:
    """Return (moisture_stress, water_stress) as 0/1 flags."""
    m_stress = 1 if moisture_pct < MOISTURE_STRESS_THRESHOLD else 0
    w_stress = 1 if water_pct < WATER_STRESS_THRESHOLD else 0
    return m_stress, w_stress


def soil_stress(m_stress: int, w_stress: int) -> float:
    """Cs = 0.6 * moisture_stress + 0.4 * water_stress"""
    return round(0.6 * m_stress + 0.4 * w_stress, 3)


def combined_score(cv: float, cs: float, w1: float, w2: float) -> float:
    """Ccombined = w1*Cv + w2*Cs, clamped to [0, 1]."""
    return round(max(0.0, min(1.0, w1 * cv + w2 * cs)), 3)


def compute(detection_class: str, confidence: float, now: float | None = None) -> dict:
    """
    Run one fusion cycle. `confidence` is the visual disease score Cv in [0, 1]
    as returned by InferenceEngine.run(). Returns the full result dict: it is
    served at /api/live and saved to SQLite. Fields are documented in schema.py.
    """
    with _lock:
        s   = dict(_sensor)
        cfg = dict(_settings)

    now = time.time() if now is None else now
    m_stress, w_stress = stress_flags(s["moisture_pct"], s["water_pct"])
    cs = soil_stress(m_stress, w_stress)
    cc = combined_score(confidence, cs, cfg["w1"], cfg["w2"])
    alert = cc > cfg["theta"]

    cycle_id = f"{NODE_ID}-{time.strftime('%Y%m%d-%H%M%S', time.localtime(now))}"

    return {
        "ts":              int(now),
        "node_id":         s["node_id"],
        "moisture_raw":    s["moisture_raw"],
        "moisture_pct":    round(s["moisture_pct"], 1),
        "water_raw":       s["water_raw"],
        "water_pct":       round(s["water_pct"], 1),
        "moisture_stress": m_stress,
        "water_stress":    w_stress,
        "cs":              cs,
        "cv":              round(confidence, 3),
        "ccombined":       cc,
        "alert":           alert,
        "detection_class": detection_class,
        "detection_conf":  round(confidence, 3),
        "cycle_id":        cycle_id,
        "has_image":       False,
        "fault":           s["fault"],
        "sensor_source":   s["source"],
    }


def esp32_connected() -> bool:
    """True if an ESP32 packet arrived in the last ESP32_TIMEOUT_S seconds."""
    with _lock:
        last = _sensor["last_esp32_ts"]
    return last > 0 and (time.time() - last) < ESP32_TIMEOUT_S


def increment_cycle() -> int:
    global _cycle_count
    with _lock:
        _cycle_count += 1
        return _cycle_count


def get_cycle_count() -> int:
    with _lock:
        return _cycle_count
