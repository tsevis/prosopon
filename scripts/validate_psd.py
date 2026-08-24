#!/usr/bin/env python3
"""Independently validate a document written by `prosopon stack` or `prosopon mix`.

The Swift tests prove the file's internal arithmetic is self-consistent. This proves a
third-party reader agrees -- that channel order, PackBits coding, alpha handling and the
merged composite are all what Photoshop will expect, not merely what we assumed.

Usage:
  validate_psd.py <document.psb> <tile.png> [<tile.png> ...]
      A stack. The tiles must be given in the same order they were passed to
      `prosopon stack`.

  validate_psd.py --mix <mix-manifest.json>
      A whole mix run. Every composite the manifest names is checked against the tiles
      it says each quadrant came from: the layer rectangles, the crops, the hidden
      markers, and the flattened composite.
"""
import json
import os
import sys
import numpy as np
from PIL import Image
from psd_tools import PSDImage


def fail(message):
    print(f"  FAIL  {message}")
    return 1


QUADRANT_ORDER = ["topLeft", "topRight", "bottomLeft", "bottomRight"]


def quadrant_origin(name, quadrant_size):
    return {
        "topLeft": (0, 0),
        "topRight": (quadrant_size, 0),
        "bottomLeft": (0, quadrant_size),
        "bottomRight": (quadrant_size, quadrant_size),
    }[name]


def compare(got, expected, label):
    """Pixel-compare two RGB images, tolerating a rounding step."""
    a = np.asarray(got.convert("RGB"), dtype=np.int16)
    b = np.asarray(expected.convert("RGB"), dtype=np.int16)
    if a.shape != b.shape:
        return fail(f"{label}: {a.shape} against {b.shape}")
    delta = np.abs(a - b)
    worst, mean = int(delta.max()), float(delta.mean())
    if worst == 0:
        print(f"    {label:24s} exact match")
    elif worst <= 1:
        print(f"    {label:24s} max delta {worst} (rounding), mean {mean:.4f}")
    else:
        return fail(f"{label}: max delta {worst}, mean {mean:.4f}")
    return 0


def validate_composite(record, manifest, folder):
    """One quartered composite against the four tiles its quadrants came from."""
    errors = 0
    canvas = manifest["canvasSize"]
    quadrant_size = manifest["quadrantSize"]
    document = os.path.join(folder, record["documentPath"])

    psd = PSDImage.open(document)
    print(f"\n{record['documentPath']}  {psd.width}x{psd.height}, {len(psd)} layers")

    if (psd.width, psd.height) != (canvas, canvas):
        errors += fail(f"canvas is {psd.width}x{psd.height}, manifest says {canvas}")

    by_name = {layer.name: layer for layer in psd.descendants()}
    quadrants = {q["quadrant"]: q for q in record["quadrants"]}

    # The three landmark markers are hidden, and must stay out of the composite.
    for marker in ("left eye", "right eye", "mouth"):
        layer = by_name.get(marker)
        if layer is None:
            print(f"    {marker:24s} not present (--no-markers?)")
        elif layer.visible:
            errors += fail(f"the '{marker}' marker is visible; it should be hidden")
        else:
            print(f"    {marker:24s} hidden, {layer.width}x{layer.height} "
                  f"at ({layer.left},{layer.top})")

    # Each quadrant layer: its rectangle, then its pixels against the source tile's
    # matching quarter.
    assembled = Image.new("RGB", (canvas, canvas), (255, 255, 255))
    for name in QUADRANT_ORDER:
        record_for = quadrants.get(name)
        if record_for is None:
            errors += fail(f"the manifest names no {name} quadrant")
            continue
        layer = by_name.get(record_for["name"])
        if layer is None:
            errors += fail(f"no layer named '{record_for['name']}' for {name}")
            continue

        x, y = quadrant_origin(name, quadrant_size)
        if (layer.left, layer.top, layer.width, layer.height) != (x, y, quadrant_size, quadrant_size):
            errors += fail(
                f"{name} is {layer.width}x{layer.height} at ({layer.left},{layer.top}); "
                f"expected {quadrant_size}x{quadrant_size} at ({x},{y})"
            )
            continue
        if not layer.visible:
            errors += fail(f"the {name} quadrant is hidden")

        tile = Image.open(record_for["tilePath"]).convert("RGB")
        expected = tile.crop((x, y, x + quadrant_size, y + quadrant_size))
        got = layer.topil()
        if got is None:
            errors += fail(f"{name} produced no pixel data")
            continue
        errors += compare(got, expected, f"{name}")
        assembled.paste(got.convert("RGB"), (x, y))

    # The stored composite is what Photoshop shows before it parses a single layer.
    merged = psd.topil()
    if merged is None:
        errors += fail("no merged composite stored")
    else:
        errors += compare(merged, assembled, "flattened composite")

    return errors


def validate_mix(manifest_path):
    folder = os.path.dirname(os.path.abspath(manifest_path))
    with open(manifest_path) as handle:
        manifest = json.load(handle)

    print(f"\n{manifest_path}")
    print(f"  canvas       {manifest['canvasSize']} x {manifest['canvasSize']}, "
          f"quadrants {manifest['quadrantSize']}")
    print(f"  seed         {manifest['seed']}")
    print(f"  tiles        {manifest['tileCount']}")
    print(f"  composites   {len(manifest['composites'])}")
    print(f"  unused       {len(manifest['unused'])}")

    errors = 0
    written = [c for c in manifest["composites"] if c.get("documentPath")]
    if not written:
        return fail("the manifest names no written documents (a dry run?)")

    # No photograph may appear twice anywhere in the batch.
    names = [q["name"] for c in manifest["composites"] for q in c["quadrants"]]
    if len(names) != len(set(names)):
        repeated = sorted({n for n in names if names.count(n) > 1})
        errors += fail(f"{len(repeated)} tile(s) used more than once: {repeated[:3]}")
    else:
        print(f"  reuse        none — {len(names)} distinct tiles across the batch")

    for record in written:
        errors += validate_composite(record, manifest, folder)

    print(f"\n  {'PASSED' if errors == 0 else str(errors) + ' FAILURE(S)'}\n")
    return errors


def main(argv):
    if len(argv) == 3 and argv[1] == "--mix":
        return validate_mix(argv[2])
    if len(argv) < 3:
        print(__doc__)
        return 2

    document, tiles = argv[1], argv[2:]
    psd = PSDImage.open(document)
    errors = 0

    print(f"\n{document}")
    print(f"  version      {'psb' if psd._record.header.version == 2 else 'psd'}")
    print(f"  size         {psd.width} x {psd.height}")
    print(f"  depth        {psd._record.header.depth}-bit, {psd._record.header.channels} channels")
    print(f"  colour mode  {psd._record.header.color_mode}")
    print(f"  layers       {len(psd)}")

    if len(psd) != len(tiles):
        errors += fail(f"expected {len(tiles)} layers, found {len(psd)}")
        return errors

    # psd_tools yields layers bottom-to-top; the writer puts tiles[0] on top.
    layers = list(psd)[::-1]

    for layer, tile in zip(layers, tiles):
        expected = Image.open(tile).convert("RGB")
        name = layer.name
        print(f"\n  layer '{name}'  {layer.width}x{layer.height} @ ({layer.left},{layer.top})"
              f"  opacity={layer.opacity} blend={layer.blend_mode.name}")

        if (layer.width, layer.height) != expected.size:
            errors += fail(f"'{name}' is {layer.width}x{layer.height}, tile is {expected.size}")
            continue
        if (layer.left, layer.top) != (0, 0):
            errors += fail(f"'{name}' is offset to ({layer.left},{layer.top})")

        got = layer.topil()
        if got is None:
            errors += fail(f"'{name}' produced no pixel data")
            continue
        got = got.convert("RGB")

        a = np.asarray(got, dtype=np.int16)
        b = np.asarray(expected, dtype=np.int16)
        delta = np.abs(a - b)
        worst, mean = int(delta.max()), float(delta.mean())
        if worst == 0:
            print(f"    pixels     exact match against {tile.split('/')[-1]}")
        elif worst <= 1:
            print(f"    pixels     max delta {worst} (rounding), mean {mean:.4f}")
        else:
            errors += fail(f"'{name}' differs from {tile}: max delta {worst}, mean {mean:.4f}")

    # The stored composite should equal the topmost layer, since the tiles are opaque.
    merged = psd.topil()
    if merged is None:
        errors += fail("no merged composite stored")
    else:
        top = Image.open(tiles[0]).convert("RGB")
        delta = np.abs(np.asarray(merged.convert("RGB"), dtype=np.int16) - np.asarray(top, dtype=np.int16))
        if delta.max() == 0:
            print(f"\n  composite    exact match against the top layer")
        elif delta.max() <= 1:
            print(f"\n  composite    max delta {int(delta.max())} (rounding)")
        else:
            errors += fail(f"composite differs from the top layer: max delta {int(delta.max())}")

    print(f"\n  {'PASSED' if errors == 0 else str(errors) + ' FAILURE(S)'}\n")
    return errors


if __name__ == "__main__":
    sys.exit(min(main(sys.argv), 1))
