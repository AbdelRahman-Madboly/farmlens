"""Print plate for the A1: case base (back plate down), lid (front face down) and tree saddle (lying flat, case face down) on the
256 mm bed, as they are sliced. The base pauses once, under the roof of the four lid-corner nut pockets, to drop in the M3 nuts."""
import copy

from build123d import Box, Compound, Pos, Rot

def _on_bed(part, rx, cx, cy):
    """Same bounding-box-centred placement as tools/place_on_bed.py."""
    p = Rot(rx, 0, 0) * copy.copy(part)
    bb = p.bounding_box()
    return Pos(cx - (bb.min.X + bb.max.X) / 2,
               cy - (bb.min.Y + bb.max.Y) / 2, -bb.min.Z) * p


def build(dims, parts):
    base = _on_bed(parts("base"), -90, dims["print.base_x"], dims["print.base_y"])
    lid = _on_bed(parts("lid"), 90, dims["print.lid_x"], dims["print.lid_y"])
    saddle = _on_bed(parts("saddle"), 90, dims["print.saddle_x"], dims["print.saddle_y"])
    base.label, lid.label, saddle.label = "base", "lid", "saddle"
    bed_size, slab = dims["print.bed"], dims["print.bed_slab"]
    bed = Pos(bed_size / 2, bed_size / 2, -slab / 2) * Box(bed_size, bed_size, slab)
    bed.label, bed.color = "bed", "#3a3d42"
    return Compound(label="plate", children=[bed, base, lid, saddle])
