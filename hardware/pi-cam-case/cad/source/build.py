#!/usr/bin/env python3
"""Rebuild the FarmLens Pi camera case from its parametric source.

Every number lives in dimensions.yaml; each part is a build(dims, parts)
function in parts/<name>/part.py, and parts("<other>") returns another
built part. Edit a value, run this script, and STEP and STL files appear in
build/.

    pip install -r requirements.txt
    python build.py                  # base, lid, saddle
    python build.py assembly plate   # any part names
    python build.py --all
"""
import argparse
import importlib.util
import sys
from pathlib import Path

import yaml
from build123d import export_step, export_stl

HERE = Path(__file__).resolve().parent
PRINTED = ["base", "lid", "saddle"]
ALL = PRINTED + ["camera", "pi", "tree", "assembly", "plate"]

dims = {k: v["value"] for k, v in yaml.safe_load((HERE / "dimensions.yaml").read_text()).items()}
_built = {}


def part(name: str):
    """Build a part once and reuse it; parts call this for the parts they need."""
    if name not in _built:
        path = HERE / "parts" / name / "part.py"
        if not path.is_file():
            sys.exit(f"No part named {name!r} (expected {path})")
        spec = importlib.util.spec_from_file_location(f"part_{name}", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _built[name] = module.build(dims, part)
    return _built[name]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("parts", nargs="*", help=f"part names (default: {' '.join(PRINTED)})")
    ap.add_argument("--all", action="store_true", help="build every part")
    ap.add_argument("--out", default=str(HERE / "build"), help="output folder (default: build/)")
    args = ap.parse_args()

    names = ALL if args.all else (args.parts or PRINTED)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for name in names:
        shape = part(name)
        export_step(shape, str(out / f"{name}.step"))
        export_stl(shape, str(out / f"{name}.stl"))
        bb = shape.bounding_box()
        print(f"{name:9s} {bb.size.X:6.1f} x {bb.size.Y:6.1f} x {bb.size.Z:6.1f} mm  "
              f"volume {shape.volume / 1000:7.1f} cm3  -> {out / name}.step/.stl")


if __name__ == "__main__":
    main()
