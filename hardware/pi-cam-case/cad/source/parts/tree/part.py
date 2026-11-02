"""Example trunk (show.tree_d) seated in the saddle's V, and the 25 mm strap: through the tunnel, out at the sides and
round the back of the trunk. For the assembly picture only."""
import importlib.util
import math
from pathlib import Path

import numpy as np
from build123d import Compound, Cylinder, Plane, Polygon, Pos, extrude
from scipy.spatial import ConvexHull

HERE = Path(__file__).parent
_spec = importlib.util.spec_from_file_location("geom", HERE.parents[1] / "tools/geom.py")
geom = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(geom)


def _hull(circle_c, r, rect):
    a = np.linspace(0, 2 * math.pi, 120, endpoint=False)
    pts = np.c_[circle_c[0] + r * np.cos(a), circle_c[1] + r * np.sin(a)]
    pts = np.vstack([pts, rect])
    h = ConvexHull(pts)
    return Polygon(*[tuple(p) for p in pts[h.vertices]], align=None)


def build(dims, parts):
    d = dims
    g = geom.Geo(d)
    half = math.radians(d["mount.v_angle"] / 2)
    r = d["show.tree_d"] / 2
    yr = g.y_back + d["mount.web"]
    tc = (g.cx, yr + r / math.sin(half))                 # trunk centre: touches both V faces
    h = g.back_h + 160
    trunk = Pos(tc[0], tc[1], g.cz) * Cylinder(r, h)
    trunk.label, trunk.color = "trunk", "#7a5a3a"
    # strap: thin band along the hull of the trunk and the tunnel
    face = d["mount.face"]
    hw = face * math.sin(half) + d["mount.arm"]
    t, st = d["show.strap_t"], d["mount.strap_t"]
    ty0 = g.y_back + d["mount.tunnel_floor"]
    yo, yi = ty0 + (st - t) / 2, ty0 + (st + t) / 2      # strap centred in the tunnel
    outer = _hull(tc, r + t, [(g.cx - hw - 1, yo), (g.cx + hw + 1, yo)])
    inner = _hull(tc, r + 0.01, [(g.cx - hw - 2, yi), (g.cx + hw + 2, yi)])
    sw = d["show.strap_w"]
    band = extrude(Plane.XY.offset(g.cz - sw / 2) * outer, amount=sw) - extrude(Plane.XY.offset(g.cz - sw / 2 - 1) * inner, amount=sw + 2)
    band.label, band.color = "strap", "#2b4f8a"
    return Compound(label="tree", children=[trunk, band])
