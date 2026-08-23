#!/usr/bin/env python3
"""Independently validate a document written by `prosopon stack`.

The Swift tests prove the file's internal arithmetic is self-consistent. This proves a
third-party reader agrees -- that channel order, PackBits coding, alpha handling and the
merged composite are all what Photoshop will expect, not merely what we assumed.

Usage:  validate_psd.py <document.psb> <tile.png> [<tile.png> ...]

The tiles must be given in the same order they were passed to `prosopon stack`.
"""
import sys
import numpy as np
from PIL import Image
from psd_tools import PSDImage


def fail(message):
    print(f"  FAIL  {message}")
    return 1


def main(argv):
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
