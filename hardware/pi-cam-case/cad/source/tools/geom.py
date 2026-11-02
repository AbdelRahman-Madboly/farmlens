"""Shared FarmLens case geometry, every number from dims.

World frame: Z up (the trunk is vertical), the camera looks toward -Y, the tree is behind the case at +Y.
The Pi 4 board stands upright with its port edge (USB-C, HDMI, audio) at the bottom: drawing x -> world x,
drawing y (from the port edge) -> world z, component side faces -Y. Board back face at y = 0.
"""
from __future__ import annotations

import math

from build123d import (Axis, Box, Circle, Cylinder, Plane, Polygon, Pos, RectangleRounded, RegularPolygon, Rot, Solid, extrude, loft)


class Geo:
    def __init__(self, d):
        self.d = d
        self.L, self.W, self.pcb = d["pi.length"], d["pi.width"], d["pi.pcb"]
        gap, wall = d["case.gap"], d["case.wall"]
        self.wall = wall
        # cavity (inside the walls, behind the lid)
        self.x0 = -d["case.sd_room"] - gap
        self.x1 = self.L + d["pi.port_overhang"] + gap
        self.z0 = -d["pi.edge_overhang"] - gap
        self.z1 = self.W + gap
        self.y_floor = d["case.standoff_h"]                       # floor inner face (board back at 0)
        self.y_back = self.y_floor + d["case.back"]                # back outer face, saddle seat
        self.y_front_parts = -self.pcb - d["pi.usb_h"]             # tallest Pi part
        self.y_lid_in = self.y_front_parts - d["case.top_room"]
        self.y_lid_out = self.y_lid_in - d["case.lid"]
        self.y_hood = self.y_lid_out - d["case.hood"]              # front edge of the hood
        self.ledge, self.r_in = d["case.ledge"], d["case.r_in"]
        self.y_wide = self.y_lid_in + d["case.ledge_depth"]        # solid ledge depth behind the lid (screw room)
        self.y_flare = self.y_wide + d["case.flare_ratio"] * d["case.ledge"]   # flare 37 deg from the print axis
        self.pocket_r = d["case.ledge"] / 2                        # hood pocket corner: lid screws on its arc centres
        self.cx = (self.x0 + self.x1) / 2
        self.cz = (self.z0 + self.z1) / 2
        self.cw = self.x1 - self.x0
        self.ch = self.z1 - self.z0
        # lid screws sit in the ledge corners
        o = self.ledge / 2
        self.lid_screws = [(x, z) for x in (self.x0 - o, self.x1 + o) for z in (self.z0 - o, self.z1 + o)]
        # outer size of the hooded front frame
        self.out_w = self.cw + 2 * (self.ledge + wall)
        self.out_h = self.ch + 2 * (self.ledge + wall)
        self.back_h = self.ch + 2 * wall                          # back face height, the saddle matches it
        # camera: lens centre in world, board front face y
        self.lens_x = d["case.cam_x"]
        self.lens_z = self.z1 - d["case.cam_from_top"]
        self.cam_front = self.y_lid_out + d["case.lens_recess"] + d["cam.lens_h"]   # lens top just inside the lid front
        self.cam_post_h = self.cam_front - self.y_lid_in

    # a rounded rectangle in the XZ plane, centred on the cavity, extruded along y from ya to yb (ya > yb ok)
    def slab(self, grow, r, ya, yb):
        lo, hi = min(ya, yb), max(ya, yb)
        sk = Pos(self.cx, self.cz) * RectangleRounded(self.cw + 2 * grow, self.ch + 2 * grow, r)
        s = extrude(Plane.XZ * sk, amount=hi - lo)          # Plane.XZ extrudes toward -Y
        return Pos(0, hi, 0) * s

    def flare(self, g0, r0, g1, r1, ya, yb):
        lo, hi = min(ya, yb), max(ya, yb)
        a = Plane.XZ.offset(-ya) * (Pos(self.cx, self.cz) * RectangleRounded(self.cw + 2 * g0, self.ch + 2 * g0, r0))
        b = Plane.XZ.offset(-yb) * (Pos(self.cx, self.cz) * RectangleRounded(self.cw + 2 * g1, self.ch + 2 * g1, r1))
        return loft([a.face(), b.face()])

    # Pi drawing point (x from SD end, y from port edge) -> world (x, z)
    def pi_xz(self, px, py):
        return px, py

    def pi_holes(self):
        d = self.d
        i, dx, dy = d["pi.hole_inset"], d["pi.hole_dx"], d["pi.hole_dy"]
        return [(i + a, i + b) for a in (0, dx) for b in (0, dy)]

    def saddle_holes(self):
        d = self.d
        return [(self.cx + sx * d["mount.screw_dx"], self.cz + sz * d["mount.screw_dz"])
                for sx in (-1, 1) for sz in (-1, 1)]

    def saddle_pocket_z(self, z):
        """Flat-down nut chamber, with floor and closing roof on print layers."""
        d = self.d
        bottom = self.cz - self.back_h / 2
        layer = d["print.layer"]
        floor = bottom + round((z - bottom - d["nut.af"] / 2) / layer) * layer
        return floor, floor + d["mount.nut_pocket_h"]

    # camera holes in world (x, z); board y runs downward (connector edge at the bottom)
    def cam_holes(self):
        d = self.d
        bx0 = self.lens_x - d["cam.lens_x"]
        bz_top = self.lens_z + d["cam.lens_y"]
        xs = (bx0 + d["cam.hole_x0"], bx0 + d["cam.hole_x0"] + d["cam.hole_dx"])
        zs = (bz_top - d["cam.hole_y0"], bz_top - d["cam.hole_y0"] - d["cam.hole_dy"])
        return [(x, z) for x in xs for z in zs]

    def cam_board_box(self):
        d = self.d
        bx0 = self.lens_x - d["cam.lens_x"]
        bz_top = self.lens_z + d["cam.lens_y"]
        return bx0, bx0 + d["cam.board_x"], bz_top - d["cam.board_y"], bz_top


def box(x0, x1, y0, y1, z0, z1):
    return Pos((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2) * Box(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))


def cyl_y(x, z, r, ya, yb):
    """Cylinder along Y between ya and yb at (x, z)."""
    lo, hi = min(ya, yb), max(ya, yb)
    return Pos(x, (lo + hi) / 2, z) * Rot(90, 0, 0) * Cylinder(r, hi - lo)


def hex_y(x, z, af, ya, yb, rotation=0):
    """Hexagonal prism along Y (a nut pocket), `af` across flats, between ya and yb at (x, z).
    rotation 30 puts a corner on +Z, so a horizontal pocket roofs with a point."""
    lo, hi = min(ya, yb), max(ya, yb)
    sk = Pos(x, z) * RegularPolygon(af / math.sqrt(3), 6, rotation=rotation)
    return Pos(0, hi, 0) * extrude(Plane.XZ * sk, amount=hi - lo)


def csk_y(x, z, r_small, r_big, y_small, y_big):
    """Countersink cone along Y: radius r_small at y_small, r_big at y_big."""
    a = Plane.XZ.offset(-y_small) * (Pos(x, z) * Circle(r_small))
    b = Plane.XZ.offset(-y_big) * (Pos(x, z) * Circle(r_big))
    return loft([a.face(), b.face()])


def teardrop_y(x, z, r, ya, yb):
    """Horizontal hole along Y that prints with Z up: a circle with a 45 deg point toward +Z."""
    lo, hi = min(ya, yb), max(ya, yb)
    c = cyl_y(x, z, r, lo, hi)
    s = r / math.sqrt(2)
    tri = Polygon((-s, s), (s, s), (0, r * math.sqrt(2)), align=None)
    t = extrude(Plane.XZ * tri, amount=hi - lo)
    return c + Pos(x, hi, z) * t
