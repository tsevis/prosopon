# Prosopon

Aligns hundreds of portrait photographs onto one fixed 2048 × 2048 face grid, so that
fragments of different faces can be cut up and recombined into mosaics.

```
left eye   (512, 512)      right eye  (1536, 512)      mouth  (1024, 1664)
```

Both eyes land on their targets **exactly**. The mouth is brought onto target by a
vertical stretch and a shear pivoted on the eye line — capped, by default, at 5 %.

## Build

```bash
swift build -c release
```

## Use

Measure a corpus against the canvas without writing anything:

```bash
.build/release/prosopon calibrate ~/Pictures/portraits
```

Align and write tiles, with verification overlays:

```bash
.build/release/prosopon align ~/Pictures/portraits -o ~/aligned --overlay
```

Collect the tiles into one layered Photoshop document, first file on top:

```bash
.build/release/prosopon stack ~/aligned -o ~/faces.psb
```

Each align run writes `manifest.json` (landmarks, transforms, metrics — enough to re-render at
any size without re-detecting) and `report.csv` (the same data, sortable by score).

### Options that matter

| Flag | Default | |
|---|---|---|
| `--max-stretch` | `0.05` | the 5 % rule |
| `--max-shear` | `0.05` | horizontal drift per unit of vertical drop |
| `--no-shear` | off | leave the mouth's horizontal offset uncorrected |
| `--faces` | `all` | `all`, `largest` or `central` |
| `--use-pupils` | off | eye centre from the pupil instead of the canthus midpoint |
| `--allow-partial-coverage` | off | keep tiles that do not fill the canvas |
| `--max-magnification` | `2.0` | reject tiles enlarged beyond this |
| `--dry-run` | off | analyse and report, write no images |

### `stack` options

| Flag | Default | |
|---|---|---|
| `--format` | `psb` | `psb` has no practical size limit; `psd` is capped at 2 GB |
| `--bit-depth` | `8` | 8 or 16 |
| `--compression` | `rle` | `rle` (what Photoshop writes) or `raw` |
| `--batch-size` | none | split into several documents of at most N layers |
| `--dpi` | `72` | resolution recorded in the document |

A 2048 x 2048 RGBA layer costs about 16 MB at 8-bit, and photographic data barely
compresses, so **a few hundred layers passes the 2 GB ceiling a `.psd` can address** —
hence the `.psb` default. Measured on an M1 Ultra: 120 layers in 18 s producing a
1.3 GB document, with resident memory settling at about 1 GB and staying there rather
than growing with the layer count. Set `PROSOPON_MEMORY=1` to see that figure live.

## How the solve works

Three point-correspondences impose six constraints. A similarity transform has four
degrees of freedom, so it can pin both eyes and nothing more; a full affine has six and
hits all three points but with unbounded distortion. The 5 % cap sits between them.

1. **Similarity from the eyes alone** — closed form. Both eyes are now exact and the face
   is upright in canvas space.
2. **Stretch and shear about the eye line** — both pivot on `y = 512`, where the eyes
   already sit, so neither can move them. The eyes stay exact for free, and the clamps
   report in plain language: *wanted 7.3 % stretch, allowed 5 %, mouth 31 px high*.

Because the stretch is vertical-only, the aspect change *is* the stretch factor, so the
5 % rule reads directly off the transform. Splitting the distortion across both axes
would halve the per-axis error, but any horizontal scale about `x = 1024` moves the eyes
off 512 and 1536.

## Layout

| Target | |
|---|---|
| `ProsoponCore` | geometry, solver, coverage, quality gates — no I/O, no UI |
| `ProsoponIO` | ImageIO loading with EXIF baked in, linear-light rendering, overlays |
| `ProsoponVision` | Apple Vision landmarks |
| `ProsoponPSD` | layered `.psd` / `.psb` writer |
| `ProsoponCLI` | `align`, `calibrate`, `stack` |

See [docs/PLAN.md](docs/PLAN.md) for the reasoning, the decisions and what is next.

## Tests

```bash
swift test
```

Covers the transform algebra, the solver invariants (including a randomised sweep
asserting the eyes never move), polygon clipping for coverage, a pixel-level check that
landmarks land on their targets in the rendered output without mirroring or flipping,
PackBits round-trips, and a structural reader that walks every declared section length
in a written document and checks it lands where the content actually ends.

The Swift tests prove the document is internally consistent. To prove a *third-party*
reader agrees — that channel order, PackBits coding, alpha handling and the merged
composite are what Photoshop expects rather than merely what we assumed:

```bash
python3 scripts/validate_psd.py ~/faces.psb ~/aligned/*.png
```

It decodes every layer with `psd-tools` and compares it against the source tile.
