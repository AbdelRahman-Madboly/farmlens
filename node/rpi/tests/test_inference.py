import os

import numpy as np
import pytest

import inference
from config import DISEASE_CLASSES, HEALTHY_CLASS
from inference import InferenceEngine, is_healthy

FIXTURE_MODEL = os.path.join(os.path.dirname(__file__), "fixtures", "dummy_classifier.tflite")
FRAME = np.zeros((480, 640, 3), dtype=np.uint8)


# ── Mock mode ────────────────────────────────────────────────────────────────

def test_default_mode_is_mock():
    engine = InferenceEngine()
    assert engine.mode() == "mock"
    assert engine.fallback_reason == ""


def test_mock_is_deterministic_with_seed():
    e1, e2 = InferenceEngine(seed=7), InferenceEngine(seed=7)
    assert [e1.run(FRAME) for _ in range(20)] == [e2.run(FRAME) for _ in range(20)]


def test_mock_scores_and_labels_are_consistent():
    engine = InferenceEngine(seed=3)
    for _ in range(500):
        cls, cv, latency = engine.run(FRAME)
        assert 0.10 <= cv <= 0.95
        assert latency == 0.0
        if cv > inference.MOCK_DISEASE_THRESHOLD:
            assert not is_healthy(cls), "mock must not raise a high score on a healthy label"
        else:
            assert cls == HEALTHY_CLASS


# ── Fallbacks when no model is available ─────────────────────────────────────

def test_tflite_without_model_file_falls_back(tmp_path):
    engine = InferenceEngine(mode="tflite", model_path=str(tmp_path / "nope.tflite"))
    assert engine.mode() == "mock"
    assert engine.requested_mode() == "tflite"
    assert "not found" in engine.fallback_reason
    cls, cv, _ = engine.run(FRAME)
    assert isinstance(cls, str) and 0 <= cv <= 1


def test_tflite_without_runtime_falls_back(tmp_path, monkeypatch):
    model = tmp_path / "m.tflite"
    model.write_bytes(b"not a model")
    monkeypatch.setattr(inference, "load_interpreter_class", lambda: None)
    engine = InferenceEngine(mode="tflite", model_path=str(model))
    assert engine.mode() == "mock"
    assert "runtime" in engine.fallback_reason


def test_corrupt_model_falls_back(tmp_path):
    if inference.load_interpreter_class() is None:
        pytest.skip("no TFLite runtime installed")
    model = tmp_path / "m.tflite"
    model.write_bytes(b"\x00" * 64)
    engine = InferenceEngine(mode="tflite", model_path=str(model))
    assert engine.mode() == "mock"
    assert "failed to load" in engine.fallback_reason


def test_unknown_mode_falls_back():
    engine = InferenceEngine(mode="gpu")
    assert engine.mode() == "mock"
    assert "unknown" in engine.fallback_reason


# ── TFLite path logic, with a fake interpreter ───────────────────────────────

class FakeInterpreter:
    """Stands in for a TFLite Interpreter so the post-processing can be tested
    without a runtime. `probs` is what the model 'outputs'."""
    probs = None
    out_shape = None

    def __init__(self, model_path):
        self.model_path = model_path
        n = len(DISEASE_CLASSES)
        self._out_shape = self.out_shape or [1, n]
        self.last_input = None

    def allocate_tensors(self):
        pass

    def get_input_details(self):
        return [{"index": 0, "shape": np.array([1, 32, 32, 3]), "dtype": np.float32,
                 "quantization": (0.0, 0)}]

    def get_output_details(self):
        return [{"index": 1, "shape": np.array(self._out_shape), "dtype": np.float32,
                 "quantization": (0.0, 0)}]

    def set_tensor(self, index, value):
        self.last_input = value

    def invoke(self):
        assert self.last_input.shape == (1, 32, 32, 3)
        assert 0.0 <= self.last_input.min() and self.last_input.max() <= 1.0

    def get_tensor(self, index):
        return np.array([type(self).probs], dtype=np.float32)


def _engine_with(monkeypatch, tmp_path, probs, out_shape=None):
    model = tmp_path / "fake.tflite"
    model.write_bytes(b"fake")
    FakeInterpreter.probs = probs
    FakeInterpreter.out_shape = out_shape
    monkeypatch.setattr(inference, "load_interpreter_class", lambda: FakeInterpreter)
    return InferenceEngine(mode="tflite", model_path=str(model))


def _one_hot(idx, p):
    n = len(DISEASE_CLASSES)
    probs = np.full(n, (1 - p) / (n - 1), dtype=np.float32)
    probs[idx] = p
    return probs


def test_disease_class_score_is_its_probability(monkeypatch, tmp_path):
    idx = DISEASE_CLASSES.index("Tomato_Late_blight")
    engine = _engine_with(monkeypatch, tmp_path, _one_hot(idx, 0.8))
    assert engine.mode() == "tflite"
    cls, cv, latency = engine.run(FRAME)
    assert cls == "Tomato_Late_blight"
    assert cv == pytest.approx(0.8, abs=1e-3)
    assert latency >= 0


def test_confident_healthy_gives_low_score(monkeypatch, tmp_path):
    idx = DISEASE_CLASSES.index("Tomato_healthy")
    engine = _engine_with(monkeypatch, tmp_path, _one_hot(idx, 0.9))
    cls, cv, _ = engine.run(FRAME)
    assert cls == "Tomato_healthy"
    assert cv == pytest.approx(0.1, abs=1e-3)


def test_low_confidence_is_no_detection(monkeypatch, tmp_path):
    n = len(DISEASE_CLASSES)
    engine = _engine_with(monkeypatch, tmp_path, np.full(n, 1.0 / n, dtype=np.float32))
    assert engine.run(FRAME)[:2] == ("none", 0.0)


def test_logits_are_softmaxed(monkeypatch, tmp_path):
    logits = np.zeros(len(DISEASE_CLASSES), dtype=np.float32)
    logits[0] = 10.0
    engine = _engine_with(monkeypatch, tmp_path, logits)
    cls, cv, _ = engine.run(FRAME)
    assert cls == DISEASE_CLASSES[0]
    assert 0.99 < cv <= 1.0


def test_wrong_output_shape_falls_back(monkeypatch, tmp_path):
    engine = _engine_with(monkeypatch, tmp_path, np.zeros(4), out_shape=[1, 10, 4])
    assert engine.mode() == "mock"
    assert "expected output" in engine.fallback_reason


# ── Real runtime with a dummy model ──────────────────────────────────────────

@pytest.mark.skipif(not os.path.isfile(FIXTURE_MODEL), reason="dummy model fixture missing")
def test_dummy_tflite_model_runs():
    """tests/fixtures/dummy_classifier.tflite is a tiny untrained network made
    only to exercise the runtime path. Its predictions mean nothing."""
    if inference.load_interpreter_class() is None:
        pytest.skip("no TFLite runtime installed")
    engine = InferenceEngine(mode="tflite", model_path=FIXTURE_MODEL)
    assert engine.mode() == "tflite", engine.fallback_reason
    frame = np.random.default_rng(0).integers(0, 255, (480, 640, 3), dtype=np.uint8)
    cls, cv, latency = engine.run(frame)
    assert cls == "none" or cls in DISEASE_CLASSES
    assert 0.0 <= cv <= 1.0
    assert latency > 0
