import pytest
from fastapi.testclient import TestClient

import api
import fusion
import main
from camera import CameraCapture
from inference import InferenceEngine
from mock_sensor import MockSensor
from schema import CycleResult


@pytest.fixture
def client():
    return TestClient(api.app)


@pytest.fixture
def camera():
    cam = CameraCapture(backend="mock")
    api.set_camera(cam)
    return cam


def test_status_reports_simulated_modes(client, camera):
    r = client.get("/api/status")
    assert r.status_code == 200
    body = r.json()
    assert body["ai_mode"] == "mock" and body["sensor_mode"] == "mock"
    assert body["simulated"] is True
    assert body["camera_backend"] == "mock" and body["camera_ready"] is True
    assert body["esp32_connected"] is False
    assert body["auth_required"] is False


def test_live_before_first_cycle_has_no_detection(client):
    body = client.get("/api/live").json()
    assert body["detection_class"] == "none"
    assert body["alert"] is False
    assert body["fault"] == 1


def test_sensor_post_is_validated(client):
    ok = client.post("/api/sensor", json={"moisture_pct": 42.0, "water_pct": 55.5,
                                          "moisture_raw": 2100, "water_raw": 1600})
    assert ok.status_code == 200 and ok.json() == {"ok": True}
    assert fusion.get_sensor()["source"] == "esp32"
    assert client.get("/api/status").json()["esp32_connected"] is True

    assert client.post("/api/sensor", json={"water_pct": 10}).status_code == 422
    assert client.post("/api/sensor", json={"moisture_pct": 150, "water_pct": 10}).status_code == 422
    assert client.post("/api/sensor", json={"moisture_pct": "wet", "water_pct": 10}).status_code == 422


def test_settings_round_trip_and_validation(client):
    assert client.get("/api/settings").json()["theta"] == 0.5
    r = client.post("/api/settings", json={"theta": 0.3, "crop_type": "pepper"})
    assert r.status_code == 200
    assert r.json()["settings"]["theta"] == 0.3
    assert client.get("/api/settings").json()["crop_type"] == "pepper"
    assert client.post("/api/settings", json={"w1": 2}).status_code == 422
    assert client.post("/api/settings", json={"theta": -0.1}).status_code == 422


def test_api_key_protects_write_endpoints(client):
    api.set_api_key("test-key-123")
    body = {"moisture_pct": 40, "water_pct": 40}
    assert client.post("/api/sensor", json=body).status_code == 401
    assert client.post("/api/sensor", json=body, headers={"X-API-Key": "wrong"}).status_code == 401
    assert client.post("/api/sensor", json=body, headers={"X-API-Key": "test-key-123"}).status_code == 200
    assert client.post("/api/settings", json={"theta": 0.4}).status_code == 401
    assert client.post("/api/settings", json={"theta": 0.4},
                       headers={"X-API-Key": "test-key-123"}).status_code == 200
    # Reads stay open
    assert client.get("/api/live").status_code == 200
    assert client.get("/api/status").json()["auth_required"] is True


def test_image_endpoint_rejects_bad_ids(client):
    assert client.get("/api/image/FL-001-missing").status_code == 404
    assert client.get("/api/image/bad.id").status_code == 400


def test_snapshot_without_camera_is_503(client):
    assert client.get("/api/snapshot").status_code == 503


def test_snapshot_returns_jpeg(client, camera):
    r = client.get("/api/snapshot")
    assert r.status_code == 200
    assert r.headers["content-type"] == "image/jpeg"
    assert r.content[:2] == b"\xff\xd8"


def test_dashboard_is_served(client):
    r = client.get("/")
    assert r.status_code == 200
    assert "FarmLens Node Dashboard" in r.text


def test_end_to_end_cycle_in_mock_mode(client, camera):
    """Mock sensor + mock inference + mock camera through one full cycle,
    then read it back through the API the app uses."""
    sensor = MockSensor(noise=0, seed=1)
    sensor.tick()
    engine = InferenceEngine(seed=1)

    data = main.run_cycle(camera, engine, 1)
    CycleResult(**data)
    assert data["sensor_source"] == "mock"
    assert data["has_image"] is True

    live = client.get("/api/live").json()
    assert live["cycle_id"] == data["cycle_id"]
    assert live["moisture_pct"] == data["moisture_pct"]

    logs = client.get("/api/logs?limit=5").json()
    assert logs["count"] == 1
    assert logs["logs"][0]["cycle_id"] == data["cycle_id"]

    img = client.get(f"/api/image/{data['cycle_id']}")
    assert img.status_code == 200 and img.content[:2] == b"\xff\xd8"


def test_logs_limit_is_clamped(client):
    assert client.get("/api/logs?limit=0").status_code == 200
    assert client.get("/api/logs?limit=100000").json()["count"] == 0


def test_status_identifies_the_node_for_discovery(client, camera):
    body = client.get("/api/status").json()
    assert body["service"] == "farmlens"
    assert body["stream"] is True
    assert body["version"] == api.app.version


def test_stream_sends_mjpeg_frames(client, camera):
    r = client.get("/api/stream?frames=3&fps=30")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("multipart/x-mixed-replace")
    assert "boundary=frame" in r.headers["content-type"]
    parts = r.content.split(b"--frame\r\n")[1:]
    assert len(parts) == 3
    for part in parts:
        head, _, body = part.partition(b"\r\n\r\n")
        assert b"Content-Type: image/jpeg" in head
        length = int(head.split(b"Content-Length: ")[1].split(b"\r\n")[0])
        assert body[:2] == b"\xff\xd8"            # JPEG start of image
        assert body[length - 2:length] == b"\xff\xd9"  # JPEG end of image


def test_stream_without_camera_is_503(client):
    assert client.get("/api/stream?frames=1").status_code == 503


def test_camera_capture_is_thread_safe(camera):
    import threading
    shapes, errors = [], []

    def grab():
        try:
            for _ in range(5):
                shapes.append(camera.capture().shape)
        except Exception as e:  # pragma: no cover
            errors.append(e)

    threads = [threading.Thread(target=grab) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert not errors and len(shapes) == 20
