"""Raspberry Pi camera v1.3, light model from reference/rpi-cam-v13.stl: board, lens block, ribbon connector behind.
Mounted on the lid, lens looking -Y, ribbon connector edge at the bottom (toward the Pi's camera connector)."""
import importlib.util
from pathlib import Path

from build123d import Compound

HERE = Path(__file__).parent
_spec = importlib.util.spec_from_file_location("geom", HERE.parents[1] / "tools/geom.py")
geom = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(geom)


def build(dims, parts):
    d = dims
    g = geom.Geo(d)
    x0, x1, z0, z1 = g.cam_board_box()
    yf = g.cam_front
    yb = yf + d["cam.pcb"]
    board = geom.box(x0, x1, yf, yb, z0, z1)
    for x, z in g.cam_holes():
        board = board - geom.cyl_y(x, z, d["cam.hole_d"] / 2, yf - 1, yb + 1)
    board.label, board.color = "board", "#1f7a3a"
    s = d["cam.lens_block"] / 2
    lens = geom.box(g.lens_x - s, g.lens_x + s, yf - d["cam.lens_h"], yf, g.lens_z - s, g.lens_z + s)
    lens.label, lens.color = "lens", "#151515"
    ci = d["cam.conn_x_in"]
    conn = geom.box(x0 + ci, x1 - ci, yb, yb + d["cam.back"], z1 - d["cam.conn_y1"], z1 - d["cam.conn_y0"])
    conn.label, conn.color = "connector", "#e8e0c8"
    return Compound(label="camera", children=[board, lens, conn])
