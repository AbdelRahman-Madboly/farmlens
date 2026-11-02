"""Case base: back plate with Pi standoffs, walls, a 45 deg flare out to the hooded front frame. The lid sits on the
ledge inside the frame; top and side walls run on past the lid as a rain hood, the bottom stays open to drain.
Air in through slots in the bottom wall, out through the lid vents under the hood. USB-C plug enters from below."""
import importlib.util
from pathlib import Path

HERE = Path(__file__).parent
_spec = importlib.util.spec_from_file_location("geom", HERE.parents[1] / "tools/geom.py")
geom = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(geom)


def build(dims, parts):
    d = dims
    g = geom.Geo(d)
    w, lg, r = g.wall, g.ledge, g.r_in
    body = (g.slab(w, r + w, g.y_back, g.y_flare)
            + g.flare(w, r + w, lg + w, g.pocket_r + w, g.y_flare, g.y_wide)
            + g.slab(lg + w, g.pocket_r + w, g.y_wide, g.y_hood))
    body = body - g.slab(0, r, g.y_floor, g.y_lid_in - 0.01)
    body = body - g.slab(lg, g.pocket_r, g.y_lid_in, g.y_hood - 1)
    # open bottom in front of the lid seat: rain drains, nothing to collect water
    big = g.out_w + 20
    body = body - geom.box(g.cx - big / 2, g.cx + big / 2, g.y_lid_in, g.y_hood - 1, g.z0 - lg - w - 5, g.z0)
    # Pi standoffs with M1.6 x 5 self-tapping pilots (the PB-3 board screw), from the board plane
    for x, z in g.pi_holes():
        body = body + geom.cyl_y(x, z, d["case.standoff_d"] / 2, 0, g.y_floor + 0.5)
        body = body - geom.cyl_y(x, z, d["case.m25_pilot"] / 2, -0.01, d["case.m25_pilot_depth"])
    # lid screws: M3 x 12 countersunk from the lid through a roof into a captured nut. The nut pocket is
    # closed by the roof, so the print pauses under it (nut_pause_z) and the nut is dropped in.
    nut_af = d["nut.af"] + d["nut.clear"]
    y_nut0 = g.y_lid_in + d["case.nut_roof"]
    y_nut1 = y_nut0 + d["nut.pocket_depth"]
    for x, z in g.lid_screws:
        body = body - geom.cyl_y(x, z, d["case.m3_clear"] / 2, g.y_lid_in - 0.01, y_nut1 + d["case.nut_hole_end"])
        body = body - geom.hex_y(x, z, nut_af, y_nut0, y_nut1)
    # Saddle screw heads seat inside the back plate, below the inner floor face.
    for x, z in g.saddle_holes():
        body = body - geom.cyl_y(x, z, d["case.m3_clear"] / 2, g.y_back + 0.01, g.y_floor - 0.5)
        body = body - geom.csk_y(x, z, d["case.m3_clear"] / 2,
                                 d["screw.head_d"] / 2 + d["screw.head_clear"],
                                 g.y_floor + d["screw.head_h"], g.y_floor)
    # USB-C plug opening through the bottom wall
    uy = -g.pcb - d["pi.usbc_h"] / 2
    pw, ph = d["case.plug_w"], d["case.plug_h"]
    ux = d["pi.usbc_x"]
    body = body - geom.box(ux - pw / 2, ux + pw / 2, uy - ph / 2, uy + ph / 2, g.z0 - lg - w - 2, g.z0 + 0.01)
    # intake slots in the bottom wall, clear of the plug opening
    vw, vl = d["case.vent_w"], d["case.vent_l"]
    vy = -d["case.vent_y0"]
    for k in range(int(d["case.vent_n"])):
        x = d["case.vent_x0"] + k * d["case.vent_pitch"]
        body = body - geom.box(x - vw / 2, x + vw / 2, vy, vy - vl, g.z0 - lg - w - 2, g.z0 + 0.01)
    body.label, body.color = "base", "#202124"
    return body
