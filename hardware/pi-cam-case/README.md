# FarmLens Pi camera case

Outdoor case for the FarmLens node: a Raspberry Pi 4 Model B and a Pi camera (v1.3) in a PETG
shell with a rain hood, mounted on a tree trunk or pole with a strap. Part of the FarmLens
monorepo; see the [root README](../../README.md).

| Front | Side | Back |
|---|---|---|
| ![Case front](images/cad-front.jpg) | ![Case side](images/cad-side.jpg) | ![Case back with saddle and strap](images/cad-back.jpg) |

Renders of the CAD assembly (v004) on a 100 mm example trunk. The trunk and strap are for scale only.

![FarmLens case on a 100 mm trunk](images/pi-cam-case-on-trunk.png)

| In the field | Close up |
|---|---|
| ![FarmLens node in a tomato field](images/concept-field.jpg) | ![FarmLens case on a trunk](images/concept-on-trunk.jpg) |

Concept images of the planned field setup, not photos of a built unit. The solar panel, sensor
box and probes are not part of this case design.

## Status

Design prototype (assembly v004: base v010, lid v009, saddle v008). Print-ready and sliced for a
Bambu Lab A1 in PETG; not yet field-tested.

## Files

| Path | What it is | Use it to |
|---|---|---|
| [`stl/`](stl) | `base.stl`, `lid.stl`, `saddle.stl`, already oriented for printing | Slice and print in any slicer |
| [`print/farmlens-case-bambu-a1-petg-0.28mm.gcode.3mf`](print) | All three parts on one plate, sliced for a Bambu Lab A1 (0.4 mm nozzle), PETG, 0.28 mm layers, with the nut pauses | Print on an A1 directly: open in Bambu Studio and send |
| [`cad/step/`](cad/step) | `base.step`, `lid.step`, `saddle.step` and `assembly.step` (case, Pi, camera and example trunk) | Open or modify in FreeCAD, Fusion, Onshape, SolidWorks |
| [`cad/source/`](cad/source) | Parametric source (Python, [build123d](https://github.com/gumyr/build123d)). Every dimension is in `dimensions.yaml` with its source | Change a dimension and rebuild |

## Printed parts

| File | Part | Material |
|---|---|---|
| `stl/base.stl` | Case base with rain hood, Pi on standoffs | PETG |
| `stl/lid.stl` | Front lid holding the camera | PETG |
| `stl/saddle.stl` | V saddle for trunks or rods 50 to 150 mm across, with tunnels for one 25 mm strap | PETG |

Print in PETG (PLA softens in the sun). No supports. 0.28 mm layers were used.

**Nut pauses.** The M3 nuts are captured inside the print, so the print pauses twice to drop them
in. The sliced A1 file already has both pauses. In another slicer, add a pause (M601 or your
printer's pause) at the start of the layer at:

| Height | Part | Nuts |
|---|---|---|
| Z 5.52 mm | Saddle | 4 x M3, into the hexagonal chambers |
| Z 29.6 mm | Base | 4 x M3, into the lid-corner pockets |

The heights match 0.28 mm layers on a 0.2 mm first layer; with another layer height, pause at the
first layer that covers the nut pockets.

## Hardware

| Item | Qty | Use |
|---|---|---|
| M1.6 x 5 self-tapping screws | 8 | Pi (4) and camera (4) to their posts, 1.3 mm pilots. The Pi (2.7 mm) and camera (2.1 mm) holes cannot take M3 |
| M3 x 12 countersunk screws + M3 nuts | 4 + 4 | Lid to base; nuts dropped into the base pockets at the Z 29.6 mm pause |
| M3 x 16 countersunk screws + M3 nuts | 4 + 4 | Saddle to base, screwed from inside the case; nuts dropped into the saddle chambers at the Z 5.52 mm pause. 16 mm = 6 mm case back + 3 mm saddle web + 2.12 mm nut + at least 4.88 mm past the nut |
| 25 mm strap (hook-and-loop or ratchet), about 1.5 mm thick | 1 | Saddle to trunk |

The nut pockets fit a standard M3 nut, 5.31 mm across flats and 2.12 mm thick.
In total: 8 x M1.6 x 5, 4 x M3 x 12, 4 x M3 x 16 and 8 x M3 nuts.

## Assembly

1. Print the three parts, dropping in the nuts at the two pauses.
2. Screw the camera to the lid posts (M1.6 x 5), lens through the square window.
3. Screw the Pi to the base standoffs (M1.6 x 5), ports down.
4. Plug the camera ribbon into the Pi (contacts facing the HDMI ports) and fold it into the case.
5. Screw the saddle to the back of the base from inside (M3 x 16 countersunk).
6. Close the lid (M3 x 12 countersunk into the captured nuts).
7. Run the strap through the saddle tunnel and round the trunk; the USB-C power cable enters
   from below.

## Rebuild from source

```bash
cd cad/source
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python build.py            # base, lid, saddle -> build/*.step and build/*.stl
python build.py --all      # also camera, pi, tree, assembly, plate
```

`build.py` reads `dimensions.yaml`, builds each `parts/<name>/part.py`, and exports STEP and STL to
`build/`. The parts are in assembly position; rotate them for printing (base back-plate down, lid
front-face down, saddle lying flat on its case face), or build `plate` for the A1 layout.

## Design notes

- Anything fixed to the back stays inside the back face's outline, so no upward face holds rain.
- Each nut bears on the part it clamps, with a 3 mm web between the nut and the case.
- Air enters through slots in the bottom wall and leaves through the lid vents under the hood; the
  bottom in front of the lid is open so water drains.
- The Pi stands upright with its ports at the bottom, so the USB-C cable enters from below.
