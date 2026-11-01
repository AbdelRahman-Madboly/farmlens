"""
FarmLens Node: Main Orchestrator
=================================
Start:  python3 main.py
Stop:   Ctrl+C  or  sudo systemctl stop farmlens

With the defaults (SENSOR_MODE=mock, AI_MODE=mock, CAMERA_BACKEND=mock) this
runs on any machine with no hardware and serves simulated data.

Every CYCLE_INTERVAL_S seconds (default 30):
  1. Capture a camera frame
  2. Run inference (mock or TFLite)
  3. Compute sensor fusion from the latest sensor reading
  4. Draw the overlay and save a JPEG
  5. Save the cycle to SQLite
  6. Update the /api/live cache
"""
import logging
import socket
import sys
import threading
import time

import uvicorn

from config import (
    NODE_ID, API_HOST, API_PORT,
    CYCLE_INTERVAL_S, LOG_FILE, SENSOR_MODE, CAMERA_BACKEND,
)
from camera import CameraCapture, draw_overlay, save_jpeg
from inference import InferenceEngine
from fusion import compute, increment_cycle
from logger import init_db, save_cycle, image_path
from mock_sensor import MockSensor
import api

log = logging.getLogger("farmlens.main")


def run_cycle(camera, engine, n: int) -> dict:
    """Run one capture-infer-fuse-log cycle and return the cycle dict."""
    frame_rgb = camera.capture()
    det_class, cv, latency_ms = engine.run(frame_rgb)
    data = compute(det_class, cv)

    frame_bgr = draw_overlay(
        frame_rgb, det_class, cv, data["ccombined"], data["cycle_id"],
        ai_mode=engine.mode(),
    )
    data["has_image"] = save_jpeg(frame_bgr, image_path(data["cycle_id"]))
    save_cycle(data)
    api.update_latest(data)

    log.info(
        "#%-4d %-24s m=%5.1f%% w=%5.1f%% cv=%.2f cc=%.2f alert=%-3s src=%s%s",
        n, data["cycle_id"], data["moisture_pct"], data["water_pct"],
        data["cv"], data["ccombined"], "YES" if data["alert"] else "no",
        data["sensor_source"],
        f" [{latency_ms:.0f}ms]" if latency_ms > 0 else "",
    )
    return data


def cycle_loop(camera, engine, stop: threading.Event, interval_s: float = CYCLE_INTERVAL_S):
    log.info("Cycle loop started, every %ss", interval_s)
    n = 0
    while not stop.is_set():
        started = time.time()
        n = increment_cycle()
        try:
            run_cycle(camera, engine, n)
        except Exception as e:
            log.error("Cycle #%d error: %s", n, e, exc_info=True)
        stop.wait(max(0.0, interval_s - (time.time() - started)))
    log.info("Cycle loop stopped after %d cycles", n)


def _setup_logging():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
        datefmt="%H:%M:%S",
        handlers=[logging.StreamHandler(sys.stdout), logging.FileHandler(LOG_FILE)],
    )


def main():
    _setup_logging()
    engine = InferenceEngine()
    log.info("FarmLens node %s | AI: %s | sensors: %s | camera: %s",
             NODE_ID, engine.mode(), SENSOR_MODE, CAMERA_BACKEND)

    init_db()
    camera = CameraCapture()
    api.set_camera(camera)
    api.set_ai_mode(engine.mode())
    api.set_sensor_mode(SENSOR_MODE)

    mock_sensor = None
    if SENSOR_MODE == "mock":
        mock_sensor = MockSensor()
        mock_sensor.start()
    else:
        log.info("SENSOR_MODE=%s: waiting for POST /api/sensor", SENSOR_MODE)

    stop = threading.Event()
    loop = threading.Thread(target=cycle_loop, args=(camera, engine, stop), daemon=True)
    loop.start()

    try:
        ip = socket.gethostbyname(socket.gethostname())
    except OSError:
        ip = "localhost"
    log.info("Dashboard: http://%s:%d/   API: http://%s:%d/api/status", ip, API_PORT, ip, API_PORT)

    try:
        uvicorn.run(api.app, host=API_HOST, port=API_PORT, log_level="warning")
    finally:
        stop.set()
        if mock_sensor:
            mock_sensor.stop()
        loop.join(timeout=5)
        camera.release()
        log.info("FarmLens stopped.")


if __name__ == "__main__":
    main()
