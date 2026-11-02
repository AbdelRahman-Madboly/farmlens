"""Raspberry Pi 4 Model B, light model: board, the parts that set the case (heights from the drawing), standing upright.
Footprint sizes of the blocks are read off the mechanical drawing for the picture only; heights and overhangs are dims."""
import importlib.util
from pathlib import Path

from build123d import Compound, Plane, Pos, RectangleRounded, extrude

HERE = Path(__file__).parent
_spec = importlib.util.spec_from_file_location("geom", HERE.parents[1] / "tools/geom.py")
geom = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(geom)


def build(dims, parts):
    d = dims
    g = geom.Geo(d)
    L, W, t = g.L, g.W, g.pcb
    top = -t                                           # component face (y), parts grow toward -Y
    out = []

    def part(x0, x1, z0, z1, h, label, color):
        b = geom.box(x0, x1, top, top - h, z0, z1)
        b.label, b.color = label, color
        out.append(b)

    sk = Pos(L / 2, W / 2) * RectangleRounded(L, W, d["pi.corner_r"])
    pcb = Pos(0, 0, 0) * extrude(Plane.XZ * sk, amount=t)
    for x, z in g.pi_holes():
        pcb = pcb - geom.cyl_y(x, z, d["pi.hole_d"] / 2, 1, -t - 1)
    pcb.label, pcb.color = "pcb", "#1f7a3a"
    out.append(pcb)
    over, edge = d["pi.port_overhang"], d["pi.edge_overhang"]
    part(L + over - 17.5, L + over, 9 - 7.3, 9 + 7.3, d["pi.usb_h"], "usb2", "#c9c9c9")
    part(L + over - 17.5, L + over, 27 - 7.3, 27 + 7.3, d["pi.usb_h"], "usb3", "#c9c9c9")
    part(L + over - 21.5, L + over, 45.75 - 8, 45.75 + 8, d["pi.eth_h"], "ethernet", "#c9c9c9")
    ux = d["pi.usbc_x"]
    part(ux - 4.5, ux + 4.5, -edge + 1.2, 6.3, d["pi.usbc_h"], "usb-c", "#b0b0b0")
    for k, hx in enumerate((d["pi.hdmi0_x"], d["pi.hdmi1_x"])):
        part(hx - 3.75, hx + 3.75, -edge + 1.0, 6.0, d["pi.hdmi_h"], f"hdmi-{k}", "#b0b0b0")
    ax = d["pi.audio_x"]
    part(ax - 3.0, ax + 3.0, -edge, 12.0, d["pi.audio_h"], "audio", "#222222")
    part(32.5 - 25.5, 32.5 + 25.5, 52.5 - 2.6, 52.5 + 2.6, d["pi.gpio_h"], "gpio", "#202020")
    part(25.75 - 7.5, 25.75 + 7.5, 32.5 - 7.5, 32.5 + 7.5, 2.4, "cpu", "#8a8a8a")
    cx = d["pi.csi_x"]
    part(cx - 1.5, cx + 1.5, d["pi.csi_z0"], d["pi.csi_z1"], d["pi.csi_h"], "csi", "#eeeeee")
    sd = geom.box(-0.5, 12.0, 0, d["pi.bottom"], 22.0, 34.0)
    sd.label, sd.color = "sd-socket", "#999999"
    out.append(sd)
    return Compound(label="pi", children=out)
