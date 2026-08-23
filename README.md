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
| `--resampler` | `lanczos` | `lanczos` (GPU), `lanczos-cpu`, or `coregraphics` |

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

## Resampling

Tiles are resampled with **Lanczos-3 on the GPU**, in linear light. Two things make that
worth the trouble over Core Graphics' `.high`:

- **Fidelity.** Under a half-pixel shift — the worst case for any interpolator — Lanczos-3
  keeps 100.7 % of an eight-pixel-period signal. Core Graphics keeps 0.9239, which is
  `cos(π/8)` to five decimals: the exact response of bilinear interpolation. Magnifying
  fourfold, Lanczos is off by 0.03 % against 1.02 %. Every tile in the stack pays that
  difference once.
- **Reduction.** A filter whose footprint stays three source pixels wide aliases as soon
  as the source is being shrunk. The kernel here widens by the inverse of the per-axis
  scale, measured separately along each source axis so rotation does not confuse it, and
  capped at sixteen source pixels. A one-pixel checkerboard reduced fourfold comes out
  flat to within 1e-15 rather than as moire.

It costs about 10 % more wall-clock than Core Graphics end to end (96 ms against 87 ms
per image on an M1 Ultra, both dominated by JPEG decode and face detection). The CPU
implementation is ten times slower again and exists as the reference the GPU kernel is
checked against, tap for tap.

A Laplacian-variance "sharpness" reading actually prefers Core Graphics on real photos.
That proxy rewards ringing and blockiness; the frequency measurements above show what it
is really registering is error.

## Layout

| Target | |
|---|---|
| `ProsoponCore` | geometry, solver, coverage, quality gates — no I/O, no UI |
| `ProsoponIO` | ImageIO loading with EXIF baked in, linear-light rendering, overlays |
| `ProsoponRender` | Metal Lanczos-3, a CPU reference, and the Core Graphics fallback |
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

The geometry suite runs against all three renderers, so a coordinate bug in one shows up
as a disagreement with the other two. Resampling is pinned by an identity transform
reproducing its source bit-for-bit — Lanczos is 1 at the centre tap and 0 at every other
integer, so anything that misaligns the taps blurs and is caught — and by comparing the
GPU kernel against the CPU reference, which agree to 2 parts in 65535.

The Swift tests prove the document is internally consistent. To prove a *third-party*
reader agrees — that channel order, PackBits coding, alpha handling and the merged
composite are what Photoshop expects rather than merely what we assumed:

```bash
python3 scripts/validate_psd.py ~/faces.psb ~/aligned/*.png
```

It decodes every layer with `psd-tools` and compares it against the source tile.
