import copy

from build123d import Compound

# The whole node on a trunk; each piece is named by its part id, so the window can show, hide and move it apart on its own.
PIECES = ["pi", "camera", "base", "lid", "saddle", "tree"]


def build(dims, parts):
    children = []
    for part_id in PIECES:
        piece = copy.copy(parts(part_id))
        piece.label = part_id
        children.append(piece)
    return Compound(label="assembly", children=children)
