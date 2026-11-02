"""
FarmLens FastAPI Server
========================
Endpoints:
  GET  /               Web dashboard (HTML)
  GET  /api/status     Node health and active modes
  POST /api/sensor     ESP32 posts sensor data here        (API key if set)
  GET  /api/live       Latest cycle, the app polls this every 5 s
  GET  /api/logs       Cycle history, newest first
  GET  /api/image/{id} JPEG for a specific cycle
  GET  /api/snapshot   Fresh camera frame
  GET  /api/stream     Live MJPEG stream (multipart/x-mixed-replace)
  GET  /api/settings   Fusion weights
  POST /api/settings   Update fusion weights live          (API key if set)

Authentication: if API_KEY is set, the two POST endpoints require the header
"X-API-Key". Read endpoints stay open. See SECURITY.md.
"""
import asyncio
import hmac
import threading
import time
import logging

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, HTMLResponse, StreamingResponse

import fusion
import logger
from config import (
    NODE_ID, NODE_NAME, START_TIME, API_KEY, SENSOR_MODE, STREAM_FPS, STREAM_QUALITY,
)
from schema import SensorReading, SettingsUpdate

log = logging.getLogger("farmlens.api")

app = FastAPI(title="FarmLens Node", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "X-API-Key"],
)

# ── Shared state (injected by main.py) ────────────────────────────────────────
_camera      = None
_ai_mode     = "mock"
_sensor_mode = SENSOR_MODE
_api_key     = API_KEY


def set_camera(cam):
    global _camera
    _camera = cam


def set_ai_mode(mode: str):
    global _ai_mode
    _ai_mode = mode


def set_sensor_mode(mode: str):
    global _sensor_mode
    _sensor_mode = mode


def set_api_key(key: str):
    global _api_key
    _api_key = key or ""


_latest: dict = {}
_latest_lock  = threading.Lock()


def update_latest(data: dict):
    with _latest_lock:
        _latest.update(data)


def get_latest() -> dict:
    with _latest_lock:
        return dict(_latest)


def clear_latest():
    with _latest_lock:
        _latest.clear()


def require_api_key(x_api_key: str | None = Header(default=None)):
    """No-op when no key is configured; otherwise a constant-time compare."""
    if not _api_key:
        return
    if not x_api_key or not hmac.compare_digest(x_api_key, _api_key):
        raise HTTPException(401, "Missing or invalid X-API-Key")


# ═══════════════════════════════════════════════════════════════════════════════
# REST ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@app.get("/api/status")
def status():
    return {
        "service":         "farmlens",
        "node_id":         NODE_ID,
        "node_name":       NODE_NAME,
        "version":         app.version,
        "stream":          True,
        "mode":            _ai_mode.upper(),
        "ai_mode":         _ai_mode,
        "sensor_mode":     _sensor_mode,
        "simulated":       _ai_mode == "mock" or _sensor_mode == "mock",
        "uptime_s":        int(time.time() - START_TIME),
        "cycle_count":     fusion.get_cycle_count(),
        "esp32_connected": fusion.esp32_connected(),
        "camera_ready":    _camera.is_ready() if _camera else False,
        "camera_backend":  _camera.backend()  if _camera else "none",
        "camera_note":     _camera.note()     if _camera else "",
        "auth_required":   bool(_api_key),
    }


@app.post("/api/sensor", dependencies=[Depends(require_api_key)])
def receive_sensor(body: SensorReading):
    """The ESP32 firmware calls this every 5 seconds."""
    fusion.update_sensor(body.model_dump(exclude_none=True), source=fusion.SOURCE_ESP32)
    return {"ok": True}


@app.get("/api/live")
def live():
    data = get_latest()
    if data:
        return data
    # No cycle has run yet: return the current sensor values with no detection.
    s = fusion.get_sensor()
    m_stress, w_stress = fusion.stress_flags(s["moisture_pct"], s["water_pct"])
    return {
        "ts": int(time.time()), "node_id": NODE_ID,
        "moisture_raw": s["moisture_raw"], "moisture_pct": round(s["moisture_pct"], 1),
        "water_raw": s["water_raw"], "water_pct": round(s["water_pct"], 1),
        "moisture_stress": m_stress, "water_stress": w_stress,
        "cs": fusion.soil_stress(m_stress, w_stress), "cv": 0.0, "ccombined": 0.0,
        "alert": False,
        "detection_class": "none",
        "detection_conf": 0.0,
        "cycle_id": "", "has_image": False,
        "fault": s["fault"], "sensor_source": s["source"],
    }


@app.get("/api/logs")
def logs(limit: int = 50):
    limit = max(1, min(limit, 200))
    rows  = logger.get_logs(limit)
    return {"count": len(rows), "logs": rows}


@app.get("/api/image/{cycle_id}")
def get_image(cycle_id: str):
    if not logger.valid_cycle_id(cycle_id):
        raise HTTPException(400, "Invalid cycle id")
    if not logger.image_exists(cycle_id):
        raise HTTPException(404, "Image not found")
    with open(logger.image_path(cycle_id), "rb") as f:
        data = f.read()
    return Response(content=data, media_type="image/jpeg")


@app.get("/api/snapshot")
def snapshot():
    """Fresh camera frame. The app Camera tab refreshes this every 5 s."""
    import cv2
    from camera import encode_jpeg
    if _camera is None:
        raise HTTPException(503, "Camera not initialised")
    frame_bgr = cv2.cvtColor(_camera.snapshot(), cv2.COLOR_RGB2BGR)
    jpeg = encode_jpeg(frame_bgr)
    if jpeg is None:
        raise HTTPException(503, "JPEG encode failed")
    return Response(content=jpeg, media_type="image/jpeg")


STREAM_BOUNDARY = "frame"


def _stream_jpeg() -> bytes | None:
    import cv2
    from camera import encode_jpeg
    frame_bgr = cv2.cvtColor(_camera.snapshot(), cv2.COLOR_RGB2BGR)
    return encode_jpeg(frame_bgr, quality=STREAM_QUALITY)


@app.get("/api/stream")
async def stream(fps: float = STREAM_FPS, frames: int = 0):
    """Live MJPEG stream. Browsers show it in an <img>; the app parses it.

    fps is capped at 30. frames > 0 stops after that many frames (tests).
    Starlette cancels the generator when the client disconnects.
    """
    if _camera is None:
        raise HTTPException(503, "Camera not initialised")
    period = 1.0 / max(0.5, min(fps, 30.0))

    async def gen():
        sent = 0
        while frames <= 0 or sent < frames:
            started = time.monotonic()
            jpeg = await run_in_threadpool(_stream_jpeg)
            if jpeg:
                yield (
                    f"--{STREAM_BOUNDARY}\r\n"
                    f"Content-Type: image/jpeg\r\n"
                    f"Content-Length: {len(jpeg)}\r\n\r\n"
                ).encode() + jpeg + b"\r\n"
                sent += 1
            await asyncio.sleep(max(0.0, period - (time.monotonic() - started)))

    return StreamingResponse(
        gen(),
        media_type=f"multipart/x-mixed-replace; boundary={STREAM_BOUNDARY}",
        headers={"Cache-Control": "no-store"},
    )


@app.get("/api/settings")
def get_settings():
    return fusion.get_settings()


@app.post("/api/settings", dependencies=[Depends(require_api_key)])
def post_settings(body: SettingsUpdate):
    fusion.update_settings(body.model_dump(exclude_none=True))
    return {"ok": True, "settings": fusion.get_settings()}


# ═══════════════════════════════════════════════════════════════════════════════
# WEB DASHBOARD  (served at /)
# ═══════════════════════════════════════════════════════════════════════════════

_DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>FarmLens Dashboard</title>
<style>
  :root {
    --green:  #1D9E75;
    --red:    #E24B4A;
    --amber:  #BA7517;
    --bg:     #F5F5F0;
    --card:   #FFFFFF;
    --border: #E8E8E4;
    --text:   #1A1A1A;
    --muted:  #6B7280;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, sans-serif; background: var(--bg);
         color: var(--text); padding: 16px; }
  h1 { color: var(--green); font-size: 1.4rem; margin-bottom: 4px; }
  .subtitle { color: var(--muted); font-size: .85rem; margin-bottom: 16px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
          gap: 12px; margin-bottom: 16px; }
  .card { background: var(--card); border: 1px solid var(--border);
          border-radius: 12px; padding: 14px; }
  .card-label { font-size: .7rem; color: var(--muted); text-transform: uppercase;
                letter-spacing: .05em; margin-bottom: 6px; }
  .card-value { font-size: 1.6rem; font-weight: 700; }
  .card-unit  { font-size: .8rem; color: var(--muted); margin-left: 3px; }
  .green { color: var(--green); }
  .red   { color: var(--red);   }
  .amber { color: var(--amber); }
  .alert-banner { background: #fef2f2; border: 1px solid #fca5a5;
                  border-radius: 10px; padding: 10px 14px; margin-bottom: 14px;
                  color: var(--red); font-weight: 600; display: none; }
  .sim-banner { background: #fff7ed; border: 1px solid #fdba74;
                border-radius: 10px; padding: 8px 14px; margin-bottom: 14px;
                color: #9a3412; font-size: .8rem; display: none; }
  .camera-wrap { background: #111; border-radius: 14px; overflow: hidden;
                 margin-bottom: 14px; aspect-ratio: 4/3; position: relative;
                 max-width: 640px; }
  .camera-wrap img { width: 100%; height: 100%; object-fit: cover; }
  .cam-overlay { position: absolute; top: 8px; left: 8px;
                 background: rgba(0,0,0,.5); color: #fff;
                 font-size: .7rem; padding: 3px 8px; border-radius: 20px; }
  .status-row { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 14px; }
  .badge { font-size: .7rem; padding: 3px 10px; border-radius: 20px;
           font-weight: 600; }
  .badge-green { background: #d1fae5; color: #065f46; }
  .badge-red   { background: #fee2e2; color: #991b1b; }
  .badge-grey  { background: #e5e7eb; color: #374151; }
  .log-table { width: 100%; border-collapse: collapse; font-size: .78rem; }
  .log-table th { background: var(--bg); padding: 6px 10px;
                  text-align: left; color: var(--muted); font-weight: 600;
                  border-bottom: 1px solid var(--border); }
  .log-table td { padding: 6px 10px; border-bottom: 1px solid var(--border); }
  .log-table tr:last-child td { border: none; }
  footer { margin-top: 20px; font-size: .7rem; color: var(--muted); text-align: center; }
</style>
</head>
<body>
<h1>FarmLens Node Dashboard</h1>
<p class="subtitle" id="subtitle">Loading…</p>

<div id="sim-banner" class="sim-banner"></div>
<div id="alert-banner" class="alert-banner">Alert: <span id="alert-class"></span></div>

<div class="status-row">
  <span class="badge badge-grey" id="badge-mode">AI: -</span>
  <span class="badge badge-grey" id="badge-sensor">SENSORS: -</span>
  <span class="badge badge-grey" id="badge-esp32">ESP32: -</span>
  <span class="badge badge-grey" id="badge-cam">CAM: -</span>
  <span class="badge badge-grey" id="badge-uptime">UPTIME: -</span>
</div>

<div class="camera-wrap">
  <img id="cam-img" src="/api/stream" alt="camera">
  <div class="cam-overlay" id="cam-label">Live</div>
</div>

<div class="grid">
  <div class="card">
    <div class="card-label">Soil Moisture</div>
    <div class="card-value" id="moisture">-<span class="card-unit">%</span></div>
  </div>
  <div class="card">
    <div class="card-label">Water Level</div>
    <div class="card-value" id="water">-<span class="card-unit">%</span></div>
  </div>
  <div class="card">
    <div class="card-label">AI Confidence (Cv)</div>
    <div class="card-value" id="cv">-</div>
  </div>
  <div class="card">
    <div class="card-label">Stress Score (Cs)</div>
    <div class="card-value" id="cs">-</div>
  </div>
  <div class="card">
    <div class="card-label">Ccombined</div>
    <div class="card-value" id="cc">-</div>
  </div>
  <div class="card">
    <div class="card-label">Detection</div>
    <div class="card-value" style="font-size:1rem;" id="detection">-</div>
  </div>
</div>

<div class="card">
  <div class="card-label" style="margin-bottom:10px">Recent Cycles</div>
  <table class="log-table">
    <thead><tr>
      <th>Cycle ID</th><th>Moisture</th><th>Water</th>
      <th>Cv</th><th>Cc</th><th>Alert</th><th>Class</th>
    </tr></thead>
    <tbody id="log-body"></tbody>
  </table>
</div>

<footer>FarmLens node · prototype on simulated data · readings refresh every 5 s</footer>

<script>
function esc(v) {
  return String(v).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

async function fetchLive() {
  try {
    const r = await fetch('/api/live');
    const d = await r.json();
    document.getElementById('moisture').innerHTML =
      d.moisture_pct.toFixed(1) + '<span class="card-unit">%</span>';
    document.getElementById('water').innerHTML =
      d.water_pct.toFixed(1) + '<span class="card-unit">%</span>';
    document.getElementById('cv').textContent = d.cv.toFixed(3);
    document.getElementById('cs').textContent = d.cs.toFixed(3);
    const ccEl = document.getElementById('cc');
    ccEl.textContent = d.ccombined.toFixed(3);
    ccEl.className = 'card-value ' + (d.ccombined > 0.65 ? 'red' : d.ccombined > 0.4 ? 'amber' : 'green');
    const det = d.detection_class.replace(/_/g,' ');
    const detEl = document.getElementById('detection');
    detEl.textContent = det;
    detEl.className = 'card-value ' + (det === 'none' ? '' : det.includes('healthy') ? 'green' : 'red');
    const banner = document.getElementById('alert-banner');
    banner.style.display = d.alert ? 'block' : 'none';
    document.getElementById('alert-class').textContent = det;
    document.getElementById('subtitle').textContent =
      'Node: ' + d.node_id + '  ·  Cycle: ' + (d.cycle_id || 'waiting for first cycle');
  } catch(e) { console.warn('live fetch failed', e); }
}

async function fetchStatus() {
  try {
    const r = await fetch('/api/status');
    const d = await r.json();
    const fmt = s => { const h=Math.floor(s/3600),m=Math.floor((s%3600)/60);
      return h>0 ? h+'h '+m+'m' : m+'m'; };
    document.getElementById('badge-mode').textContent  = 'AI: ' + d.ai_mode.toUpperCase();
    document.getElementById('badge-sensor').textContent = 'SENSORS: ' + d.sensor_mode.toUpperCase();
    const sim = document.getElementById('sim-banner');
    sim.style.display = d.simulated ? 'block' : 'none';
    sim.textContent = 'Simulated data. AI: ' + d.ai_mode + ', sensors: ' + d.sensor_mode +
      ', camera: ' + d.camera_backend + '. These values are not measurements.';
    document.getElementById('badge-esp32').textContent = 'ESP32: ' + (d.esp32_connected ? 'connected' : 'not connected');
    document.getElementById('badge-esp32').className   = 'badge ' + (d.esp32_connected ? 'badge-green' : 'badge-red');
    document.getElementById('badge-cam').textContent   = 'CAM: ' + (d.camera_ready ? d.camera_backend : 'off');
    document.getElementById('badge-cam').className     = 'badge ' + (d.camera_ready ? 'badge-green' : 'badge-red');
    document.getElementById('badge-uptime').textContent = 'UP: ' + fmt(d.uptime_s);
  } catch(e) {}
}

async function fetchLogs() {
  try {
    const r  = await fetch('/api/logs?limit=8');
    const d  = await r.json();
    const tb = document.getElementById('log-body');
    tb.innerHTML = d.logs.map(row =>
      '<tr>' +
      '<td>' + esc(row.cycle_id.split('-').slice(-2).join('-')) + '</td>' +
      '<td>' + row.moisture_pct.toFixed(1) + '%</td>' +
      '<td>' + row.water_pct.toFixed(1) + '%</td>' +
      '<td>' + row.cv.toFixed(2) + '</td>' +
      '<td>' + row.ccombined.toFixed(2) + '</td>' +
      '<td>' + (row.alert ? '<span style="color:red">YES</span>' : 'no') + '</td>' +
      '<td>' + esc(row.detection_class.replace(/_/g,' ')) + '</td>' +
      '</tr>'
    ).join('');
  } catch(e) {}
}

// The camera is a live MJPEG stream. If it drops (node restart, Wi-Fi
// blip), reconnect it a few seconds later.
const camImg = document.getElementById('cam-img');
camImg.onerror = () => {
  document.getElementById('cam-label').textContent = 'Reconnecting…';
  setTimeout(() => { camImg.src = '/api/stream?t=' + Date.now(); }, 3000);
};
camImg.onload = () => { document.getElementById('cam-label').textContent = 'Live stream'; };

async function tick() {
  await Promise.all([fetchLive(), fetchStatus(), fetchLogs()]);
}

tick();
setInterval(tick, 5000);
</script>
</body>
</html>"""


@app.get("/", response_class=HTMLResponse)
def dashboard():
    """Web dashboard: open http://<node-address>:8000 in a browser."""
    return HTMLResponse(content=_DASHBOARD_HTML)
