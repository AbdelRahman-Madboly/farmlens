"""
FarmLens Mock Sensor
=====================
Simulated soil-moisture and water-level readings for running the node with no
ESP32 attached (SENSOR_MODE=mock, the default).

The curves are the same ones the ESP32 firmware uses in its own mock mode
(firmware/lib/sensor_model): moisture drifts 20-80 % on a 300 s sine wave and
water level drifts 20-70 % on a 240 s sine wave. A small amount of random noise
is added so values do not repeat exactly. These numbers are synthetic; they
are not measurements of anything.

A background thread calls fusion.update_sensor(..., source="mock") every
SENSOR_INTERVAL_S seconds, the same entry point POST /api/sensor uses.
"""
import math
import random
import threading
import time
import logging

import fusion
from config import (
    NODE_ID, SENSOR_INTERVAL_S,
    MOISTURE_DRY, MOISTURE_WET, WATER_DRY, WATER_WET,
)

log = logging.getLogger("farmlens.mock_sensor")

MOISTURE_MEAN, MOISTURE_AMP, MOISTURE_PERIOD_S = 50.0, 30.0, 300.0
WATER_MEAN,    WATER_AMP,    WATER_PERIOD_S    = 45.0, 25.0, 240.0
WATER_PHASE = 1.0


def _clamp(v: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, v))


def pct_to_raw(pct: float, dry: int, wet: int) -> int:
    """Map 0-100 % onto the ADC range, where `dry` is 0 % and `wet` is 100 %."""
    return int(round(dry - (pct / 100.0) * (dry - wet)))


def reading_at(t: float, noise: float = 0.0, rng: random.Random | None = None) -> dict:
    """
    Simulated reading `t` seconds after start. With noise=0 the result is
    deterministic, which is what the tests use.
    """
    rng = rng or random
    m = MOISTURE_MEAN + MOISTURE_AMP * math.sin(2 * math.pi * t / MOISTURE_PERIOD_S)
    w = WATER_MEAN + WATER_AMP * math.sin(2 * math.pi * t / WATER_PERIOD_S + WATER_PHASE)
    if noise:
        m += rng.uniform(-noise, noise)
        w += rng.uniform(-noise, noise)
    m, w = round(_clamp(m), 1), round(_clamp(w), 1)
    return {
        "node_id":      NODE_ID,
        "moisture_pct": m,
        "moisture_raw": pct_to_raw(m, MOISTURE_DRY, MOISTURE_WET),
        "water_pct":    w,
        "water_raw":    pct_to_raw(w, WATER_DRY, WATER_WET),
        "ts":           int(time.time()),
        "fault":        0,
    }


class MockSensor:
    """Background thread that feeds simulated readings into fusion."""

    def __init__(self, interval_s: float = SENSOR_INTERVAL_S, noise: float = 1.5,
                 seed: int | None = None, clock=time.monotonic):
        self._interval = interval_s
        self._noise = noise
        self._rng = random.Random(seed)
        self._clock = clock
        self._t0 = clock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def tick(self) -> dict:
        """Generate one reading and push it into fusion. Returns the reading."""
        reading = reading_at(self._clock() - self._t0, self._noise, self._rng)
        fusion.update_sensor(reading, source=fusion.SOURCE_MOCK)
        return reading

    def _run(self):
        log.info("Mock sensor started, every %.1fs", self._interval)
        while not self._stop.wait(self._interval):
            try:
                self.tick()
            except Exception as e:  # keep the thread alive on a bad reading
                log.error("mock sensor tick failed: %s", e)
        log.info("Mock sensor stopped")

    def start(self):
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self.tick()  # first reading immediately, so the first cycle is not stale
        self._thread = threading.Thread(target=self._run, name="mock-sensor", daemon=True)
        self._thread.start()

    def stop(self, timeout: float = 2.0):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout)

    def is_running(self) -> bool:
        return bool(self._thread and self._thread.is_alive())
