"""Test setup: point every path at a temp dir and force simulated modes
before any node module imports config."""
import os
import tempfile

_TMP = tempfile.mkdtemp(prefix="farmlens-test-")
os.environ.update({
    "DB_FILE": os.path.join(_TMP, "farmlens.db"),
    "LOG_IMAGE_DIR": os.path.join(_TMP, "images"),
    "MODEL_DIR": os.path.join(_TMP, "models"),
    "LOG_FILE": os.path.join(_TMP, "farmlens.log"),
    "AI_MODE": "mock",
    "SENSOR_MODE": "mock",
    "CAMERA_BACKEND": "mock",
    "API_KEY": "",
})

import pytest  # noqa: E402

import api  # noqa: E402
import fusion  # noqa: E402
import logger  # noqa: E402


@pytest.fixture(autouse=True)
def clean_state(tmp_path, monkeypatch):
    """Fresh fusion state, empty API cache, no API key, and a new SQLite
    database plus image dir per test."""
    images = tmp_path / "images"
    images.mkdir()
    monkeypatch.setattr(logger, "DB_PATH", str(tmp_path / "test.db"))
    monkeypatch.setattr(logger, "LOG_IMAGE_DIR", str(images))
    logger.init_db()
    fusion.reset()
    api.clear_latest()
    api.set_api_key("")
    api.set_camera(None)
    yield
    fusion.reset()
    api.clear_latest()
