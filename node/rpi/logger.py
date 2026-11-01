"""
FarmLens Logger
================
SQLite cycle history + JPEG path helpers.
WAL mode is enabled so the API can read while the cycle loop writes.
"""
import json
import logging
import os
import re
import sqlite3
from contextlib import closing

from config import DB_PATH, LOG_IMAGE_DIR

log = logging.getLogger("farmlens.logger")

# Cycle IDs look like "FL-001-20260101-120000". Anything else is rejected
# before it reaches the filesystem.
CYCLE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


def _connect() -> sqlite3.Connection:
    con = sqlite3.connect(DB_PATH)
    con.execute("PRAGMA journal_mode=WAL")
    return con


def init_db():
    os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
    with closing(_connect()) as con:
        con.execute("""
            CREATE TABLE IF NOT EXISTS cycles (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                cycle_id  TEXT UNIQUE,
                ts        INTEGER,
                data_json TEXT,
                has_image INTEGER DEFAULT 0
            )
        """)
        con.commit()
    log.info("SQLite ready: %s", DB_PATH)


def save_cycle(data: dict) -> bool:
    """Insert or replace one cycle. Returns False (and logs) on failure."""
    try:
        with closing(_connect()) as con:
            con.execute(
                "INSERT OR REPLACE INTO cycles (cycle_id, ts, data_json, has_image) "
                "VALUES (?,?,?,?)",
                (data["cycle_id"], data["ts"],
                 json.dumps(data), int(data.get("has_image", False))),
            )
            con.commit()
        return True
    except Exception as e:
        log.error("save_cycle: %s", e)
        return False


def get_logs(limit: int = 50) -> list:
    """Newest cycles first."""
    try:
        with closing(_connect()) as con:
            rows = con.execute(
                "SELECT data_json FROM cycles ORDER BY ts DESC, id DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [json.loads(r[0]) for r in rows]
    except Exception as e:
        log.error("get_logs: %s", e)
        return []


def valid_cycle_id(cycle_id: str) -> bool:
    return bool(CYCLE_ID_RE.match(cycle_id or ""))


def image_path(cycle_id: str) -> str:
    if not valid_cycle_id(cycle_id):
        raise ValueError(f"invalid cycle_id: {cycle_id!r}")
    return os.path.join(LOG_IMAGE_DIR, f"{cycle_id}.jpg")


def image_exists(cycle_id: str) -> bool:
    return valid_cycle_id(cycle_id) and os.path.isfile(image_path(cycle_id))
