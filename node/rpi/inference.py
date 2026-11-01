"""
FarmLens Inference Engine
==========================
AI_MODE = "mock"   -> random-walk disease score, no model file needed (default)
AI_MODE = "tflite" -> generic TFLite image classifier at MODEL_PATH

No trained model ships with this repository. The TFLite path is exercised in
the tests with a small dummy model generated for that purpose only; its
outputs mean nothing. If AI_MODE=tflite is requested but the runtime or the
model file is missing, or the model's output is not a [1, N] class vector,
the engine logs the reason and falls back to mock mode.

run() returns (detection_class, cv, latency_ms) where `cv` is the visual
disease score in [0, 1] that fusion.compute() expects:
  - top class is a disease  -> cv = probability of that class
  - top class is healthy    -> cv = 1 - probability of that class
  - top probability below CONFIDENCE_THRESHOLD -> ("none", 0.0)
"""
import os
import random
import time
import logging

import numpy as np

from config import (
    AI_MODE, MODEL_PATH, CONFIDENCE_THRESHOLD,
    DISEASE_CLASSES, HEALTHY_CLASS, NO_DETECTION,
)

log = logging.getLogger("farmlens.inference")

MODE_MOCK = "mock"
MODE_TFLITE = "tflite"


def is_healthy(cls: str) -> bool:
    return "healthy" in cls.lower()


# Labels the mock may report when its score crosses the disease threshold
MOCK_DISEASE_CLASSES = [c for c in DISEASE_CLASSES if not is_healthy(c)]
MOCK_DISEASE_THRESHOLD = 0.60


def load_interpreter_class():
    """Return a TFLite Interpreter class, or None if no runtime is installed."""
    try:
        from ai_edge_litert.interpreter import Interpreter
        return Interpreter
    except ImportError:
        pass
    try:
        from tflite_runtime.interpreter import Interpreter
        return Interpreter
    except ImportError:
        pass
    try:
        import tensorflow as tf
        return tf.lite.Interpreter
    except ImportError:
        return None


def _softmax(x: np.ndarray) -> np.ndarray:
    e = np.exp(x - np.max(x))
    return e / e.sum()


class InferenceEngine:
    """
    Unified inference interface.
    run(frame_rgb) -> (detection_class: str, cv: float, latency_ms: float)
    """

    def __init__(self, mode: str | None = None, model_path: str | None = None,
                 labels: list[str] | None = None, seed: int | None = None):
        self._requested = (mode or AI_MODE).lower()
        self._model_path = model_path or MODEL_PATH
        self._labels = labels or DISEASE_CLASSES
        self._rng = random.Random(seed)
        self._interpreter = None
        self._cv_state = 0.35
        self._cycle = 0
        self._mode = MODE_MOCK
        self.fallback_reason = ""

        if self._requested == MODE_TFLITE:
            self._load_tflite()
        elif self._requested != MODE_MOCK:
            self._fallback(f"unknown AI_MODE {self._requested!r}")
        log.info("Inference engine: %s MODE", self._mode.upper())

    # ── Setup ────────────────────────────────────────────────────────────────

    def _fallback(self, reason: str):
        self.fallback_reason = reason
        self._mode = MODE_MOCK
        self._interpreter = None
        log.warning("%s; using mock inference", reason)

    def _load_tflite(self):
        if not os.path.isfile(self._model_path):
            return self._fallback(f"model file not found: {self._model_path}")
        interpreter_cls = load_interpreter_class()
        if interpreter_cls is None:
            return self._fallback("no TFLite runtime installed")
        try:
            interp = interpreter_cls(model_path=self._model_path)
            interp.allocate_tensors()
        except Exception as e:
            return self._fallback(f"failed to load model: {e}")

        inp = interp.get_input_details()[0]
        out = interp.get_output_details()[0]
        if len(inp["shape"]) != 4 or inp["shape"][3] != 3:
            return self._fallback(f"expected input [1,H,W,3], got {list(inp['shape'])}")
        if len(out["shape"]) != 2 or out["shape"][0] != 1:
            return self._fallback(f"expected output [1,N], got {list(out['shape'])}")
        if out["shape"][1] != len(self._labels):
            log.warning("model has %d outputs but %d labels are configured",
                        out["shape"][1], len(self._labels))

        self._interpreter = interp
        self._input = inp
        self._output = out
        self._mode = MODE_TFLITE
        log.info("TFLite model loaded: %s", self._model_path)

    # ── Public ───────────────────────────────────────────────────────────────

    def mode(self) -> str:
        return self._mode

    def requested_mode(self) -> str:
        return self._requested

    def run(self, frame_rgb: np.ndarray) -> tuple[str, float, float]:
        if self._mode == MODE_TFLITE and self._interpreter is not None:
            return self._run_tflite(frame_rgb)
        return self._run_mock()

    # ── Mock ─────────────────────────────────────────────────────────────────

    def _run_mock(self) -> tuple[str, float, float]:
        self._cycle += 1
        self._cv_state = max(0.10, min(0.95,
            self._cv_state + self._rng.uniform(-0.07, 0.07)))
        cv = round(self._cv_state, 3)
        if cv > MOCK_DISEASE_THRESHOLD:
            cls = MOCK_DISEASE_CLASSES[(self._cycle - 1) % len(MOCK_DISEASE_CLASSES)]
        else:
            cls = HEALTHY_CLASS
        return cls, cv, 0.0

    # ── TFLite ───────────────────────────────────────────────────────────────

    def _prepare_input(self, frame_rgb: np.ndarray) -> np.ndarray:
        import cv2
        h, w = int(self._input["shape"][1]), int(self._input["shape"][2])
        img = cv2.resize(frame_rgb, (w, h)).astype(np.float32) / 255.0
        dtype = self._input["dtype"]
        if dtype == np.float32:
            data = img
        else:
            scale, zero = self._input.get("quantization", (0.0, 0))
            if scale:
                data = np.round(img / scale + zero)
            else:
                data = img * 255.0
            info = np.iinfo(dtype)
            data = np.clip(data, info.min, info.max).astype(dtype)
        return data[np.newaxis]

    def _read_probabilities(self) -> np.ndarray:
        raw = self._interpreter.get_tensor(self._output["index"])[0]
        out = raw.astype(np.float32)
        if self._output["dtype"] != np.float32:
            scale, zero = self._output.get("quantization", (0.0, 0))
            if scale:
                out = (out - zero) * scale
        if out.min() < 0 or abs(float(out.sum()) - 1.0) > 0.05:
            out = _softmax(out)
        return out

    def _run_tflite(self, frame_rgb: np.ndarray) -> tuple[str, float, float]:
        t0 = time.perf_counter()
        try:
            self._interpreter.set_tensor(self._input["index"], self._prepare_input(frame_rgb))
            self._interpreter.invoke()
            probs = self._read_probabilities()
        except Exception as e:
            log.error("TFLite inference error: %s", e)
            return NO_DETECTION, 0.0, 0.0

        best = int(np.argmax(probs))
        p = float(probs[best])
        latency_ms = round((time.perf_counter() - t0) * 1000, 1)

        if p < CONFIDENCE_THRESHOLD or best >= len(self._labels):
            return NO_DETECTION, 0.0, latency_ms
        cls = self._labels[best]
        cv = (1.0 - p) if is_healthy(cls) else p
        return cls, round(cv, 3), latency_ms
