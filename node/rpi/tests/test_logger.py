import os

import pytest

import logger


def _cycle(cycle_id, ts, **extra):
    d = {"cycle_id": cycle_id, "ts": ts, "cv": 0.3, "has_image": False}
    d.update(extra)
    return d


def test_save_and_read_back_newest_first():
    assert logger.save_cycle(_cycle("FL-001-a", 100))
    assert logger.save_cycle(_cycle("FL-001-b", 300))
    assert logger.save_cycle(_cycle("FL-001-c", 200))
    ids = [r["cycle_id"] for r in logger.get_logs(10)]
    assert ids == ["FL-001-b", "FL-001-c", "FL-001-a"]


def test_limit_is_applied():
    for i in range(5):
        logger.save_cycle(_cycle(f"FL-001-{i}", i))
    assert len(logger.get_logs(2)) == 2


def test_same_cycle_id_is_replaced_not_duplicated():
    logger.save_cycle(_cycle("FL-001-x", 1, cv=0.1))
    logger.save_cycle(_cycle("FL-001-x", 1, cv=0.9))
    rows = logger.get_logs(10)
    assert len(rows) == 1 and rows[0]["cv"] == 0.9


def test_database_lives_in_the_temp_dir(tmp_path):
    assert logger.DB_PATH.startswith(str(tmp_path))
    assert os.path.isfile(logger.DB_PATH)


def test_save_failure_returns_false():
    assert logger.save_cycle({"ts": 1}) is False  # no cycle_id


def test_get_logs_on_broken_db_returns_empty(monkeypatch, tmp_path):
    monkeypatch.setattr(logger, "DB_PATH", str(tmp_path / "missing-dir" / "x.db"))
    assert logger.get_logs() == []


def test_image_path_rejects_traversal():
    with pytest.raises(ValueError):
        logger.image_path("../../etc/passwd")
    assert logger.image_exists("../secret") is False
    assert logger.image_path("FL-001-20260101-120000").endswith("FL-001-20260101-120000.jpg")


def test_image_exists(tmp_path):
    path = logger.image_path("FL-001-img")
    assert logger.image_exists("FL-001-img") is False
    with open(path, "wb") as f:
        f.write(b"\xff\xd8")
    assert logger.image_exists("FL-001-img") is True
