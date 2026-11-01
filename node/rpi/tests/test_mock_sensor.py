import math
import random
import time

import pytest

import fusion
import mock_sensor
from mock_sensor import MockSensor, pct_to_raw, reading_at


def test_reading_at_start_matches_firmware_curve():
    r = reading_at(0)
    assert r["moisture_pct"] == 50.0
    assert r["water_pct"] == pytest.approx(round(45 + 25 * math.sin(1.0), 1))
    assert r["fault"] == 0


def test_moisture_peaks_at_quarter_period():
    assert reading_at(75)["moisture_pct"] == pytest.approx(80.0)
    assert reading_at(225)["moisture_pct"] == pytest.approx(20.0)


def test_full_sweep_stays_in_documented_ranges():
    readings = [reading_at(t) for t in range(0, 1200, 3)]
    m = [r["moisture_pct"] for r in readings]
    w = [r["water_pct"] for r in readings]
    assert 19.9 <= min(m) and max(m) <= 80.1
    assert 19.9 <= min(w) and max(w) <= 70.1
    # The sweep crosses the moisture stress threshold (30 %) in both directions
    assert min(m) < 30 < max(m)


def test_pct_to_raw_maps_dry_and_wet_ends():
    assert pct_to_raw(0, 2800, 1200) == 2800
    assert pct_to_raw(100, 2800, 1200) == 1200
    assert pct_to_raw(50, 3000, 500) == 1750


def test_noise_is_bounded():
    rng = random.Random(1)
    for t in range(0, 300, 7):
        clean = reading_at(t)
        noisy = reading_at(t, noise=1.5, rng=rng)
        assert abs(noisy["moisture_pct"] - clean["moisture_pct"]) <= 1.6
        assert 0 <= noisy["water_pct"] <= 100


def test_tick_feeds_fusion_as_mock_source():
    clock = iter([0.0, 75.0]).__next__
    sensor = MockSensor(noise=0, clock=clock)  # t0 = 0
    reading = sensor.tick()                    # t = 75 -> moisture 80 %
    s = fusion.get_sensor()
    assert s["source"] == "mock"
    assert s["moisture_pct"] == reading["moisture_pct"] == pytest.approx(80.0)
    assert fusion.esp32_connected() is False


def test_values_change_between_cycles():
    """The original gap: with no ESP32, sensor values never moved."""
    t = [0.0]
    sensor = MockSensor(noise=0, clock=lambda: t[0])
    t[0] = 10.0
    sensor.tick()
    first = fusion.compute("Tomato_healthy", 0.2)
    t[0] = 100.0
    sensor.tick()
    second = fusion.compute("Tomato_healthy", 0.2)
    assert first["moisture_pct"] != second["moisture_pct"]
    assert first["water_pct"] != second["water_pct"]


def test_background_thread_updates_and_stops():
    sensor = MockSensor(interval_s=0.02, noise=0)
    sensor.start()
    try:
        assert sensor.is_running()
        deadline = time.time() + 2
        while fusion.get_sensor()["source"] != "mock" and time.time() < deadline:
            time.sleep(0.01)
        assert fusion.get_sensor()["source"] == "mock"
    finally:
        sensor.stop()
    assert not sensor.is_running()


def test_curve_constants_match_firmware_header():
    """mock_sensor.py and firmware/lib/sensor_model must use the same curve."""
    assert (mock_sensor.MOISTURE_MEAN, mock_sensor.MOISTURE_AMP, mock_sensor.MOISTURE_PERIOD_S) == (50.0, 30.0, 300.0)
    assert (mock_sensor.WATER_MEAN, mock_sensor.WATER_AMP, mock_sensor.WATER_PERIOD_S) == (45.0, 25.0, 240.0)
