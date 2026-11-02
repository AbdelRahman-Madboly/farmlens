"""Tree saddle: a 120 deg V on the back of the case. Any trunk or rod from mount.tree_min to mount.tree_max touches
both faces (a 150 mm trunk at 43 mm from the root, 50 mm at 14 mm). One strap tunnel runs straight across behind the V
root and comes out at the sides, so the strap pulls the saddle onto the trunk. Four M3 screws, two above and two below
the tunnel, from inside the case through its back plate into nuts held in pockets in the saddle. As tall as the case back: no ledge on top.
Prints lying flat on the case face (build direction +Y): the tunnel roof bridges 19 mm with sloped corners; the four
hexagonal nut chambers sit at one height, one pause, and bear on a solid 3 mm web on the case side."""
import importlib.util
import math
from pathlib import Path

from build123d import Plane, Polygon, Pos, extrude

HERE = Path(__file__).parent
_spec = importlib.util.spec_from_file_location("geom", HERE.parents[1] / "tools/geom.py")
geom = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(geom)


def build(dims, parts):
    d = dims
    g = geom.Geo(d)
    half = math.radians(d["mount.v_angle"] / 2)
    face = d["mount.face"]
    tip_x = face * math.sin(half)
    rise = face * math.cos(half)
    y0 = g.y_back
    yr = y0 + d["mount.web"]
    hw = tip_x + d["mount.arm"]
    pts = [(-hw, y0), (hw, y0), (hw, yr + rise), (tip_x, yr + rise), (0, yr), (-tip_x, yr + rise), (-hw, yr + rise)]
    h = g.back_h
    zb = g.cz - h / 2
    prof = Polygon(*[(g.cx + x, y) for x, y in pts], align=None)
    body = Pos(0, 0, zb) * extrude(Plane.XY * prof, amount=h)
    # strap tunnel along X, centred in height. Printed lying flat it is a slot whose roof bridges the strap width, so the
    # top corners slope in at 45 deg (the 25 mm strap, 1.5 mm thick, still lies flat in the bottom of the slot).
    sw, st = d["mount.strap_w"], d["mount.strap_t"]
    ty0 = y0 + d["mount.tunnel_floor"]
    flat = d["mount.strap_flat"]
    slope = min(st - flat, sw / 2 - 4.0)
    prof_t = Polygon((ty0, g.cz - sw / 2), (ty0, g.cz + sw / 2), (ty0 + flat, g.cz + sw / 2),
                     (ty0 + flat + slope, g.cz + sw / 2 - slope), (ty0 + st, g.cz + sw / 2 - slope),
                     (ty0 + st, g.cz - sw / 2 + slope), (ty0 + flat + slope, g.cz - sw / 2 + slope),
                     (ty0 + flat, g.cz - sw / 2), align=None)
    body = body - Pos(g.cx + hw + 1, 0, 0) * extrude(Plane.YZ * prof_t, amount=2 * hw + 2)   # Plane.YZ extrudes toward -X
    # Prints with the case face down: the 3 mm web is laid first, then the four hexagonal nut chambers (all at the same
    # height, so ONE pause drops all four nuts in), then a 2 mm roof the screw passes through. Screw tension pulls each
    # nut onto the web, which is saddle material between the nut and the case, never an open face.
    nut_af = d["nut.af"] + d["nut.clear"]
    y_nut0 = y0 + d["mount.nut_web"]
    y_nut1 = y_nut0 + d["nut.pocket_depth"]
    tip_end = y0 + d["mount.screw_len"] - d["case.back"] + d["mount.tip_clear"]
    for x, z in g.saddle_holes():
        body = body - geom.hex_y(x, z, nut_af, y_nut0, y_nut1)
        body = body - geom.cyl_y(x, z, d["case.m3_clear"] / 2, y0 - 0.01, tip_end)
    body.label, body.color = "saddle", "#202124"
    return body
