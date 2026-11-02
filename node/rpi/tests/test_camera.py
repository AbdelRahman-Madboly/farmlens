"""Camera backend selection, with picamera2 and OpenCV replaced by fakes."""
import sys
import types

import numpy as np
import pytest

import camera
from camera import CameraCapture


class FakeCap:
    """cv2.VideoCapture stand-in: opened/readable as configured."""
    def __init__(self, opened, readable):
        self.opened, self.readable = opened, readable

    def isOpened(self):
        return self.opened

    def read(self):
        if self.readable:
            return True, np.zeros((480, 640, 3), np.uint8)
        return False, None

    def set(self, *a):
        pass

    def release(self):
        self.opened = False


def fake_picamera2(cameras):
    """A picamera2 module whose camera list is `cameras`."""
    class Picamera2:
        @staticmethod
        def global_camera_info():
            return cameras

        def create_video_configuration(self, main):
            return main

        def configure(self, cfg):
            pass

        def start(self):
            pass

        def capture_array(self):
            return np.full((480, 640, 3), 7, np.uint8)

        def stop(self):
            pass

        def close(self):
            pass

    mod = types.ModuleType("picamera2")
    mod.Picamera2 = Picamera2
    return mod


@pytest.fixture(autouse=True)
def no_sleep(monkeypatch):
    monkeypatch.setattr(camera.time, "sleep", lambda s: None)


def use_cv(monkeypatch, opened, readable):
    monkeypatch.setattr(camera.cv2, "VideoCapture", lambda i: FakeCap(opened, readable))


def test_auto_without_picamera2_or_webcam_falls_back_to_mock(monkeypatch):
    monkeypatch.setitem(sys.modules, "picamera2", None)   # import fails
    use_cv(monkeypatch, opened=False, readable=False)
    cam = CameraCapture(backend="auto")
    assert cam.backend() == "mock"
    assert "picamera2 is not installed" in cam.note()
    assert cam.is_ready()
    assert cam.capture().shape == (480, 640, 3)


def test_auto_with_no_pi_camera_says_check_the_cable(monkeypatch):
    monkeypatch.setitem(sys.modules, "picamera2", fake_picamera2([]))
    use_cv(monkeypatch, opened=False, readable=False)
    cam = CameraCapture(backend="auto")
    assert cam.backend() == "mock"
    assert "ribbon cable" in cam.note()


def test_auto_picks_the_pi_camera(monkeypatch):
    monkeypatch.setitem(sys.modules, "picamera2", fake_picamera2([{"Model": "ov5647"}]))
    use_cv(monkeypatch, opened=False, readable=False)
    cam = CameraCapture(backend="auto")
    assert cam.backend() == "picamera2"
    assert cam.note() == ""
    assert int(cam.capture()[0, 0, 0]) == 7


def test_auto_skips_a_video_device_that_gives_no_frames(monkeypatch):
    # A Pi codec node opens but never returns a frame: not a camera.
    monkeypatch.setitem(sys.modules, "picamera2", fake_picamera2([]))
    use_cv(monkeypatch, opened=True, readable=False)
    assert CameraCapture(backend="auto").backend() == "mock"


def test_auto_uses_a_working_usb_webcam(monkeypatch):
    monkeypatch.setitem(sys.modules, "picamera2", fake_picamera2([]))
    use_cv(monkeypatch, opened=True, readable=True)
    cam = CameraCapture(backend="auto")
    assert cam.backend() == "opencv"


def test_status_reports_the_camera_note(monkeypatch):
    from fastapi.testclient import TestClient
    import api
    monkeypatch.setitem(sys.modules, "picamera2", None)
    use_cv(monkeypatch, opened=False, readable=False)
    api.set_camera(CameraCapture(backend="auto"))
    body = TestClient(api.app).get("/api/status").json()
    assert body["camera_backend"] == "mock"
    assert "picamera2" in body["camera_note"]
