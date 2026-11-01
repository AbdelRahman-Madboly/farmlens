import time

import pytest

import fusion
from schema import CycleResult


def test_stress_flags_use_strict_thresholds():
    # Defaults: moisture < 30 %, water < 20 %
    assert fusion.stress_flags(29.9, 50) == (1, 0)
    assert fusion.stress_flags(30.0, 50) == (0, 0)
    assert fusion.stress_flags(50, 19.9) == (0, 1)
    assert fusion.stress_flags(50, 20.0) == (0, 0)
    assert fusion.stress_flags(10, 10) == (1, 1)


@pytest.mark.parametrize("m,w,expected", [(0, 0, 0.0), (1, 0, 0.6), (0, 1, 0.4), (1, 1, 1.0)])
def test_soil_stress_weights(m, w, expected):
    assert fusion.soil_stress(m, w) == pytest.approx(expected)


def test_combined_score_formula_and_clamp():
    assert fusion.combined_score(0.5, 0.0, 0.6, 0.4) == pytest.approx(0.3)
    assert fusion.combined_score(0.5, 1.0, 0.6, 0.4) == pytest.approx(0.7)
    assert fusion.combined_score(1.0, 1.0, 1.0, 1.0) == 1.0
    assert fusion.combined_score(-1.0, 0.0, 1.0, 0.0) == 0.0


def test_compute_with_dry_soil_raises_alert():
    fusion.update_sensor({"moisture_pct": 20.0, "water_pct": 60.0}, source="mock")
    data = fusion.compute("Tomato_Late_blight", 0.7)
    assert data["moisture_stress"] == 1 and data["water_stress"] == 0
    assert data["cs"] == pytest.approx(0.6)
    assert data["ccombined"] == pytest.approx(0.6 * 0.7 + 0.4 * 0.6)
    assert data["alert"] is True
    assert data["sensor_source"] == "mock"
    assert data["fault"] == 0
    CycleResult(**data)  # shape matches the documented schema


def test_compute_healthy_and_wet_has_no_alert():
    fusion.update_sensor({"moisture_pct": 60.0, "water_pct": 60.0}, source="mock")
    data = fusion.compute("Tomato_healthy", 0.2)
    assert data["cs"] == 0.0
    assert data["alert"] is False


def test_alert_is_strictly_greater_than_theta():
    fusion.update_settings({"w1": 1.0, "w2": 0.0, "theta": 0.5})
    fusion.update_sensor({"moisture_pct": 60.0, "water_pct": 60.0}, source="mock")
    assert fusion.compute("x", 0.5)["alert"] is False
    assert fusion.compute("x", 0.51)["alert"] is True


def test_initial_state_reports_fault_until_first_reading():
    data = fusion.compute("none", 0.0)
    assert data["fault"] == 1
    assert data["sensor_source"] == "none"


def test_update_settings_is_partial():
    fusion.update_settings({"theta": 0.7})
    s = fusion.get_settings()
    assert s["theta"] == 0.7
    assert s["w1"] == 0.6 and s["w2"] == 0.4 and s["crop_type"] == "tomato"
    fusion.update_settings({"crop_type": "pepper", "w1": None})
    assert fusion.get_settings()["crop_type"] == "pepper"
    assert fusion.get_settings()["w1"] == 0.6


def test_esp32_connected_only_for_esp32_source(monkeypatch):
    fusion.update_sensor({"moisture_pct": 50, "water_pct": 50}, source="mock")
    assert fusion.esp32_connected() is False
    fusion.update_sensor({"moisture_pct": 50, "water_pct": 50}, source="esp32")
    assert fusion.esp32_connected() is True
    later = time.time() + fusion.ESP32_TIMEOUT_S + 1
    monkeypatch.setattr(fusion.time, "time", lambda: later)
    assert fusion.esp32_connected() is False


def test_cycle_counter():
    assert fusion.get_cycle_count() == 0
    assert fusion.increment_cycle() == 1
    assert fusion.increment_cycle() == 2
    assert fusion.get_cycle_count() == 2


def test_cycle_id_uses_node_id_and_time():
    data = fusion.compute("none", 0.0, now=0)
    assert data["cycle_id"].startswith("FL-001-")
    assert data["ts"] == 0
