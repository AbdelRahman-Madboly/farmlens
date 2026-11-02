"""
FarmLens Camera Module
=======================
Three backends, switchable via CAMERA_BACKEND in .env:
  - "mock"      : synthetic frames, no camera needed (default)
  - "picamera2" : Pi camera on the CSI ribbon
  - "opencv"    : USB webcam

To switch camera: edit CAMERA_BACKEND in .env, restart service.
"""
import threading
import time
import logging
import numpy as np
import cv2

from config import (
    CAMERA_BACKEND, CAMERA_INDEX,
    CAMERA_WIDTH, CAMERA_HEIGHT,
)

log = logging.getLogger("farmlens.camera")

# ── Try to import picamera2 ───────────────────────────────────────────────────
_HAVE_PICAMERA2 = False
if CAMERA_BACKEND == "picamera2":
    try:
        from picamera2 import Picamera2
        _HAVE_PICAMERA2 = True
    except ImportError:
        log.warning("picamera2 not installed - falling back to opencv backend")


class CameraCapture:
    """
    Unified camera interface.
    Call capture() to get an H×W×3 RGB numpy array.
    Never raises - returns a placeholder frame on any error.
    """

    def __init__(self, backend: str | None = None):
        self._cam_pi  = None   # Picamera2 instance
        self._cam_cv  = None   # OpenCV VideoCapture instance
        self._backend = (backend or CAMERA_BACKEND).lower()
        self._frame_n = 0
        # The cycle loop, the snapshot endpoint and every open stream share one
        # camera, so captures are serialised.
        self._lock    = threading.Lock()

        if self._backend == "mock":
            log.info("Camera: MOCK backend, synthetic frames")
        elif self._backend == "picamera2" and _HAVE_PICAMERA2:
            self._init_picamera2()
        else:
            self._init_opencv()

    # ── Init ─────────────────────────────────────────────────────────────────

    def _init_picamera2(self):
        try:
            self._cam_pi = Picamera2()
            # A video configuration keeps the sensor streaming, so each
            # capture_array() returns in one frame time and the MJPEG stream
            # stays smooth. picamera2 names formats by their little-endian
            # word order: "BGR888" gives arrays in [R, G, B] order, which is
            # what the rest of this module expects ("RGB888" would swap red
            # and blue).
            cfg = self._cam_pi.create_video_configuration(
                main={"size": (CAMERA_WIDTH, CAMERA_HEIGHT), "format": "BGR888"}
            )
            self._cam_pi.configure(cfg)
            self._cam_pi.start()
            time.sleep(1)   # allow sensor to settle
            self._backend = "picamera2"
            log.info("RPi Camera ready via picamera2 (%dx%d)", CAMERA_WIDTH, CAMERA_HEIGHT)
        except Exception as e:
            log.warning("picamera2 init failed: %s - trying opencv", e)
            self._cam_pi = None
            self._init_opencv()

    def _init_opencv(self):
        cap = cv2.VideoCapture(CAMERA_INDEX)
        if cap.isOpened():
            cap.set(cv2.CAP_PROP_FRAME_WIDTH,  CAMERA_WIDTH)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
            self._cam_cv = cap
            self._backend = "opencv"
            log.info("Camera ready via OpenCV index=%d (%dx%d)",
                     CAMERA_INDEX, CAMERA_WIDTH, CAMERA_HEIGHT)
        else:
            cap.release()
            self._backend = "none"
            log.warning("No camera found, placeholder frames will be used")

    # ── Capture ──────────────────────────────────────────────────────────────

    def capture(self) -> np.ndarray:
        """Return H×W×3 RGB array. Never raises. Safe to call from any thread."""
        with self._lock:
            return self._capture_locked()

    def _capture_locked(self) -> np.ndarray:
        if self._backend == "mock":
            return self._mock_frame()

        if self._cam_pi:
            try:
                return self._cam_pi.capture_array()
            except Exception as e:
                log.warning("picamera2 capture error: %s", e)

        if self._cam_cv and self._cam_cv.isOpened():
            try:
                ret, bgr = self._cam_cv.read()
                if ret:
                    return cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            except Exception as e:
                log.warning("opencv capture error: %s", e)

        return self._placeholder()

    def snapshot(self) -> np.ndarray:
        """Alias for capture - used by /api/snapshot."""
        return self.capture()

    def backend(self) -> str:
        return self._backend

    def is_ready(self) -> bool:
        if self._backend == "mock":
            return True
        return self._cam_pi is not None or (
            self._cam_cv is not None and self._cam_cv.isOpened()
        )

    # ── Synthetic frames ─────────────────────────────────────────────────────

    def _mock_frame(self) -> np.ndarray:
        """A plain synthetic 'leaf' image, labelled so it cannot be mistaken
        for a photo. The blotches move between frames."""
        self._frame_n += 1
        h, w = CAMERA_HEIGHT, CAMERA_WIDTH
        rng = np.random.default_rng(self._frame_n)
        frame = np.zeros((h, w, 3), dtype=np.uint8)
        frame[:] = (34, 52, 30)                      # dark soil background (RGB)
        cv2.ellipse(frame, (w // 2, h // 2), (int(w * 0.33), int(h * 0.30)),
                    25, 0, 360, (70, 140, 60), -1)   # leaf
        cv2.line(frame, (int(w * 0.25), int(h * 0.68)), (int(w * 0.75), int(h * 0.32)),
                 (110, 170, 90), 2)                  # midrib
        for _ in range(int(rng.integers(0, 6))):
            cx = int(w * rng.uniform(0.35, 0.65))
            cy = int(h * rng.uniform(0.35, 0.65))
            cv2.circle(frame, (cx, cy), int(rng.integers(6, 16)), (120, 95, 40), -1)
        cv2.putText(frame, "SIMULATED FRAME", (int(w * 0.30), h - 40),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (230, 230, 230), 1)
        # A running clock, so a live stream visibly moves.
        cv2.putText(frame, time.strftime("%H:%M:%S"), (int(w * 0.40), h - 16),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200, 200, 200), 1)
        return frame

    # ── Placeholder ──────────────────────────────────────────────────────────

    def _placeholder(self) -> np.ndarray:
        frame = np.zeros((CAMERA_HEIGHT, CAMERA_WIDTH, 3), dtype=np.uint8)
        frame[:] = (25, 25, 25)
        cv2.putText(frame, "NO CAMERA", (int(CAMERA_WIDTH * 0.22), int(CAMERA_HEIGHT * 0.5)),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.4, (70, 70, 70), 2)
        cv2.putText(frame, "Check cable / CAMERA_BACKEND in .env",
                    (20, int(CAMERA_HEIGHT * 0.62)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (55, 55, 55), 1)
        return frame

    # ── Cleanup ───────────────────────────────────────────────────────────────

    def release(self):
        if self._cam_pi:
            try: self._cam_pi.stop()
            except Exception: pass
        if self._cam_cv:
            try: self._cam_cv.release()
            except Exception: pass
        log.info("Camera released")


# ── Image utilities ───────────────────────────────────────────────────────────

def draw_overlay(frame_rgb: np.ndarray, detection_class: str,
                 confidence: float, ccombined: float,
                 cycle_id: str, ai_mode: str = "mock") -> np.ndarray:
    """
    Draw detection overlay on RGB frame.
    Same layout for mock and TFLite output; mock mode adds a placeholder box.
    Returns annotated BGR copy ready for JPEG encoding.
    """
    bgr = cv2.cvtColor(frame_rgb, cv2.COLOR_RGB2BGR)
    h, w = bgr.shape[:2]

    is_disease = "healthy" not in detection_class.lower() and detection_class != "none"
    col = (0, 60, 220) if is_disease else (50, 200, 50)  # BGR

    # Fixed placeholder box, drawn only in mock mode. It is not a detection:
    # the mock has no coordinates and the TFLite path is a whole-image
    # classifier, so neither produces a real bounding box.
    x1, y1 = int(w * 0.15), int(h * 0.12)
    x2, y2 = int(w * 0.85), int(h * 0.88)
    if ai_mode == "mock":
        cv2.rectangle(bgr, (x1, y1), (x2, y2), col, 2)

    # Label bar above box
    # The score is the disease score Cv (shown bottom-left), not the
    # probability of the label, so it is not repeated here.
    label = detection_class.replace("_", " ") + ("  (mock)" if ai_mode == "mock" else "")
    (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1)
    cv2.rectangle(bgr, (x1, y1 - th - 10), (x1 + tw + 8, y1), col, -1)
    cv2.putText(bgr, label, (x1 + 4, y1 - 4),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1)

    # Bottom-left: Cv and Cc scores
    cv2.putText(bgr, f"Cv:{confidence:.2f}  Cc:{ccombined:.2f}",
                (10, h - 28), cv2.FONT_HERSHEY_SIMPLEX, 0.48, col, 1)

    # Bottom-left: cycle ID
    cv2.putText(bgr, cycle_id, (10, h - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.38, (120, 120, 120), 1)

    # Top-left: mode watermark
    mode_label = "MOCK MODE" if ai_mode == "mock" else "TFLITE CLASSIFIER"
    mode_col   = (40, 140, 200) if ai_mode == "mock" else (40, 200, 40)
    cv2.putText(bgr, mode_label, (10, 22),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, mode_col, 1)

    # Bottom-right: timestamp
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    (tsw, _), _ = cv2.getTextSize(ts, cv2.FONT_HERSHEY_SIMPLEX, 0.40, 1)
    cv2.putText(bgr, ts, (w - tsw - 6, h - 8),
                cv2.FONT_HERSHEY_SIMPLEX, 0.40, (150, 150, 150), 1)

    return bgr   # BGR - ready for cv2.imencode


def encode_jpeg(frame_bgr: np.ndarray, quality: int = 85) -> bytes | None:
    """Encode BGR frame to JPEG bytes."""
    ok, buf = cv2.imencode(".jpg", frame_bgr, [cv2.IMWRITE_JPEG_QUALITY, quality])
    return bytes(buf) if ok else None


def save_jpeg(frame_bgr: np.ndarray, path: str, quality: int = 85) -> bool:
    """Save BGR frame as JPEG file. Returns True on success."""
    data = encode_jpeg(frame_bgr, quality)
    if not data:
        return False
    try:
        with open(path, "wb") as f:
            f.write(data)
        return True
    except Exception as e:
        log.warning("save_jpeg: %s", e)
        return False
