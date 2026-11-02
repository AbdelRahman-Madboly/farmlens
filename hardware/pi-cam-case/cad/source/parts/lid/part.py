"""Front lid: a plate in the hood pocket, four M3 x 12 countersunk screws into captured nuts in the ledge corners. The camera hangs on four posts behind
it with its lens block in a square window, lens front 0.5 mm inside the lid face. Outlet vents high up, under the hood."""
import importlib.util
from pathlib import Path

from build123d import Plane, Pos, Rectangle, loft

HERE = Path(__file__).parent
_spec = importlib.util.spec_from_file_location("geom", HERE.parents[1] / "tools/geom.py")
geom = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(geom)

def build(dims, parts):
    d = dims
    g = geom.Geo(d)
    fit = d["case.fit"]
    lid = g.slab(g.ledge - fit, g.pocket_r - fit, g.y_lid_in, g.y_lid_out)
    for x, z in g.lid_screws:
        lid = lid - geom.cyl_y(x, z, d["case.m3_clear"] / 2, g.y_lid_in + 1, g.y_lid_out - 1)
        lid = lid - geom.csk_y(x, z, d["case.m3_clear"] / 2,
                               d["screw.head_d"] / 2 + d["screw.head_clear"],
                               g.y_lid_out + d["screw.head_h"], g.y_lid_out)
    ch = d["case.window_chamfer"]   # 45 deg mouth on the window
    s = d["cam.lens_block"] + 2 * d["case.lens_clear"]
    lid = lid - geom.box(g.lens_x - s / 2, g.lens_x + s / 2, g.y_lid_in + 1, g.y_lid_out - 1, g.lens_z - s / 2, g.lens_z + s / 2)
    a = Plane.XZ.offset(-(g.y_lid_out + ch)) * (Pos(g.lens_x, g.lens_z) * Rectangle(s, s))
    b = Plane.XZ.offset(-(g.y_lid_out - 0.01)) * (Pos(g.lens_x, g.lens_z) * Rectangle(s + 2 * ch + 0.02, s + 2 * ch + 0.02))
    lid = lid - loft([a.face(), b.face()])
    # camera posts with M1.6 x 5 pilots (2.0 mm into the plate, 1.0 left in front)
    for x, z in g.cam_holes():
        lid = lid + geom.cyl_y(x, z, d["case.cam_post_d"] / 2, g.y_lid_in - 0.01, g.cam_front)
        lid = lid - geom.cyl_y(x, z, d["case.m2_pilot"] / 2, g.cam_front + 0.01, g.y_lid_in - d["case.m2_pilot_depth"])
    # outlet vents: two groups of upright slots either side of the camera, high under the hood
    vw, m = d["case.vent_w"], d["case.vent_margin"]
    bx0, bx1, _, _ = g.cam_board_box()
    zt = g.z1 - m / 2
    for x0, x1 in ((g.x0 + m, bx0 - m), (bx1 + m, g.x1 - m)):
        n = int((x1 - x0) // (2 * vw)) + 1
        for k in range(n):
            x = x0 + k * 2 * vw
            lid = lid - geom.box(x, x + vw, g.y_lid_in + 1, g.y_lid_out - 1, zt - d["case.vent_l"], zt)
    lid.label, lid.color = "lid", "#202124"
    return lid
