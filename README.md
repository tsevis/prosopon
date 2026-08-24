# Prosopon

Aligns hundreds of portrait photographs onto one fixed 2048 × 2048 face grid, so that
fragments of different faces can be cut up and recombined into mosaics — and then
composes them into quartered portraits, four faces to a canvas.

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

Or do the whole thing in the app — import, analyse, and fix the handful the detector got
wrong:

```bash
./review.sh
```

`review.sh` builds the binary if it is stale, wraps it in a `.app` bundle and opens that.
The bundle is not optional: a bare SwiftPM executable has no `Info.plist`, and without one
the app runs its event loop happily while never putting a window on screen. Given a run
directory it opens straight into Fine Tune on it; with no argument it finds the most recent
run, and with none to find it starts at Import.

Check that the batch registered, before committing to it:

```bash
.build/release/prosopon qa ~/aligned -o ~/qa
```

Collect the tiles into one layered Photoshop document, first file on top:

```bash
.build/release/prosopon stack ~/aligned -o ~/faces.psb
```

Compose them into quartered portraits — four faces to a canvas, each image used once:

```bash
.build/release/prosopon mix ~/aligned -o ~/mixed
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
| `--use-pupils` | off | eye centre from the pupil instead of the canthus midpoint (Vision only) |
| `--detector` | `vision` | `vision` or `insightface` |
| `--model-path` | searched | directory holding `det_10g.onnx` and `2d106det.onnx` |
| `--allow-partial-coverage` | off | keep tiles that do not fill the canvas |
| `--max-magnification` | `2.0` | reject tiles enlarged beyond this |
| `--max-yaw` | off | reject faces turned further than this, in degrees |
| `--dry-run` | off | analyse and report, write no images |
| `--resampler` | `lanczos` | `lanczos` (GPU), `lanczos-cpu`, or `coregraphics` |
| `--bit-depth` | `16` | bits per channel written; 8 is right when the sources are 8-bit |

### `qa` options

| Flag | Default | |
|---|---|---|
| `--suspect-threshold` | `2` | call out tiles further than this many pixels from consensus |
| `--contact-sheet-count` | `24` | how many tiles to put on the contact sheet |
| `--deviation-gain` | `3` | brightness multiplier for the deviation image |

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

## Mixing — the quartered portrait

`mix` is what the alignment was for. Each output is one 2048 × 2048 canvas cut into four
1024 × 1024 quadrants, every quadrant from a different photograph. N tiles in, N ÷ 4
documents out, and **no image appears twice anywhere in the batch**.

The seams fall at x = 1024 and y = 1024. On the fixed grid that puts the left eye
(512, 512) dead centre of the top-left quadrant, the right eye (1536, 512) dead centre of
the top-right — and the mouth (1024, 1664) **exactly on the vertical seam**. So the two
bottom quadrants carry half a mouth each, from two different people. It is the hardest
join in the picture and it only works because both mouths are on the same pixels by
construction.

### How the four are chosen

Not by shuffling and hoping. Every tile is measured along the eight strips it could
present to a neighbour: the mean colour of a 16 px strip, taken in **linear light** and
compared in **CIE Lab**, plus the standard deviation of L\* as a texture term. Then, per
composite:

1. **The most frontal half of the corpus is reserved for the top quadrants**, where the
   eyes are. Splitting the pool by frontality before any matching satisfies that exactly,
   rather than leaving it as a preference a strong tone match could outvote.
2. **The mouth seam is matched first**, with the mouth band (± 192 px of the mouth line)
   weighted four times the rest of the strip. The strip runs the whole bottom half — chin,
   neck, shoulder — so left unweighted, a matching backdrop would outvote a matching mouth.
3. **Then the cheeks**, each top quadrant chosen to meet the bottom one below it; the
   second also has to meet the first across the nose bridge, so it is scored on both.

Greedy and deliberately so — an optimal assignment over hundreds of tiles is not worth its
cost, and a good first choice on the hardest seam is worth more than a balanced compromise
across all four. The costs rise through a batch as the easy matches are spent.

**Frontality comes from head yaw when the detector reports a usable one.** Vision does not
— it quantises to 45° steps — so a Vision run falls back to the quality score and the
manifest says so in words rather than claiming to be pose-sorted.

**The shuffle is seeded** (`--seed`, default 1), so a run reproduces and another seed gives
another batch from the same corpus. When N is not a multiple of four the remainder is left
out, named in the manifest and counted in the summary; a composite with a white quadrant is
not the artwork, and dropping four photographs in silence is not acceptable either.

Two faces found in **one photograph** are two tiles with the same source, and a candidate
whose source is already in the composite is refused: quartering a portrait with itself is
not the piece.

`mix-manifest.json` and `mix-report.csv` record which image went where, what each quadrant
was matched on, what it scored, and what all four seams came out at — so a bad join is
traced rather than guessed at.

### One thing tone matching cannot see

Nothing matches a face's tone as well as **the same face**. On a corpus holding several
frames of one sitter, the best mouth partner for a frame is usually another frame of the
same person — measured on a twenty-portrait set of five sitters at four frames each, every
composite repeated a sitter and two took three quadrants from one person. The frames are
separate files, so the same-source guard never fires.

This is the objective working as specified rather than a bug: at the seam, "the same
person again" and "a very good match" are the same measurement. Telling them apart needs
either a face embedding (`w600k_r50.onnx` is in the same `buffalo_l` folder as the
detectors) or a rule about matching on *all eight* strips at once. Neither is built. On a
corpus of distinct identities the situation does not arise.

### Positioned layers, no masks

Each quadrant is a **1024 × 1024 layer at its own offset**, cropped from the aligned tile
as it is written. A PSD layer record already carries its own bounding rectangle, so this
needs no layer-mask code at all, and a composite comes out around **25 MB** instead of the
80 MB four full-canvas layers would cost.

What it gives up is real and was chosen knowingly: a seam **cannot be slid in Photoshop
afterwards** to reveal more of a face. Regenerate with another `--seed` instead.

The three landmark markers are reproduced as hidden olive discs at the two eyes and the
mouth, which is what lets a join be checked by eye, and a white locked Background sits
under everything.

### `mix` options

| Flag | Default | |
|---|---|---|
| `--seed` | `1` | seeds the shuffle and every fallback pick |
| `--seam-width` | `16` | width of the strip tones are matched on, in canvas pixels |
| `--mouth-band` | `384` | height of the mouth band, centred on the mouth target |
| `--measure-size` | `1024` | resolution tiles are decoded at for measurement |
| `--format` | `psd` | a composite is far inside the 2 GB ceiling; `psb` also available |
| `--bit-depth` | `8` | 8 or 16 |
| `--compression` | `rle` | `rle` or `raw` |
| `--no-markers` | off | leave out the three hidden landmark markers |
| `--no-background` | off | leave out the white background layer |
| `--preview-size` | `512` | flattened preview beside each document; `0` for none |
| `--flat` | none | also write a full-size flattened `png` or `tiff` |
| `--limit` | none | write only the first N composites; the plan still covers everything |
| `--dry-run` | off | plan and write the manifest, write no documents |

A composite is about 25 MB, so 640 of them is roughly 16 GB. `--dry-run` reads the whole
plan first, and `--limit` writes a few to look at.

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

## Detectors

**Vision** is the default: no model files, nothing to install, runs on the Neural Engine.

**InsightFace** (`--detector insightface`) runs `det_10g` + `2d106det` from `buffalo_l`
through ONNX Runtime with the CoreML execution provider — no Python at runtime. It is
searched for in `~/.insightface/models/buffalo_l` and a couple of other usual places, or
pointed at with `--model-path`. Its 106-point contour gives the canthi and the mouth
commissures directly, rather than leaving them to be inferred from a coarser
constellation.

The six indices it reads — 35/39 and 93/89 for the canthi, 52/61 for the commissures —
were established by running the reference implementation over a set of faces and keeping
the ones that did not move, not taken from memory. `scripts/insightface_truth.py`
regenerates the fixture that pins them.

The Swift port is checked against that reference: same faces found, box corners agreeing
to **0.16 px** on a 1280 px image, and all 106 landmarks to **0.004** of an interocular
distance.

One measured surprise: using *better* resampling for the model's input crop makes it
worse. Core Graphics `.high` moves the median canonical landmark from 3.9 to 6.3 canvas
pixels away from the reference. The model was trained behind OpenCV's bilinear, and
matching that is the accurate choice, not the higher-quality filter.

### Head pose

`--detector insightface` also loads `1k3d68` and reports head pose, which `--max-yaw`
then gates on. Yaw agrees with the reference implementation to **0.47 degrees** across
faces turned from -55 to +7.

Yaw is the one distortion the aligner cannot answer. A turned head foreshortens the
interocular distance, so pinning the eyes to their fixed targets scales the whole face up
to compensate - the cheek and jaw come out larger than on a frontal tile, and a fragment
cut from one will not meet its neighbours. Because the eye coordinates are not
negotiable, the scale is fully determined and there is no freedom left to correct with.
Declining the tile is the only useful response, which is why this is a gate and not a
correction.

Yaw also feeds the score, so sorting brings the most frontal tiles forward even when
nothing was rejected.

**The gate needs the InsightFace detector.** Vision reports yaw only in 45 degree steps:
on the six-face photograph it gave 0 for faces actually turned 13, 20 and 37 degrees.
Setting `--max-yaw` with `--detector vision` prints a warning rather than quietly doing
nothing.

### Which one is better?

Not established. The port is faithful to its reference, and on a six-face group photo
both detectors find all six. But they place the landmarks differently — InsightFace's
mouth-drop ratios run consistently lower, which is a definitional difference rather than
an error — and deciding which is *closer to the truth* needs a corpus of real portraits
that this machine does not have. InsightFace also found nothing at all in a photograph
that had markers painted over the eyes, where Vision coped.

There is one thing it is measurably better at: **pose**. Vision's 45 degree quantisation
makes its yaw unusable for gating, while InsightFace's tracks the reference to half a
degree. If yaw matters to you, that settles the choice on its own.

### A note on output size

A 2048² tile is about **22 MB** as a 16-bit PNG and **5.5 MB** as an 8-bit one — four
times smaller, because PNG compresses 8-bit data far better. Rendered from 8-bit sources
the two differ by at most 1/255, so the extra depth stores nothing. At a few thousand
tiles that is the difference between 51 GB and 13 GB; set `--bit-depth 8` unless the
sources genuinely carried more than 8 bits.

## Checking a batch

Superimposing hundreds of aligned faces should leave the eyes and mouth crisp while
everything that varies between people averages into a blur. One image says whether a
whole batch is usable.

Because the alignment is solved analytically and puts the eyes on target to within a
billionth of a pixel, a soft average never means the arithmetic slipped — it means the
landmark detector was wrong on some tiles. So `qa` also measures, per tile, how far each
landmark sits from where the rest of the stack agrees it should be, by correlating a
96 px window against the stack's own average. That turns "the average looks soft" into a
ranked list of files to open.

It writes `mean.png`, `mean-overlay.png`, `deviation.png`, a `contact-sheet.png` of the
worst offenders with the targets drawn over each, and `qa.csv` / `qa.json`.

Two figures matter in the summary:

- **Sharpness retained** — how crisp the average is at each landmark against how crisp the
  individual tiles are there. The *contrast* between the landmarks and the whole canvas is
  the real signal: above 1 means the eyes and mouth survived averaging better than the
  hair and jaw did, which is what registration looks like.
- **Distance from consensus** — per tile, in pixels. Sub-pixel accurate via a parabolic fit
  on the correlation peak, since rounding to whole pixels would put a half-pixel floor
  under every measurement.

The consensus measurement assumes the tiles resemble one another. Over a corpus of many
*distinct* identities the average is a soft generic face that no individual correlates
with, and almost everything reports as unmatched — on 2,288 assorted studio headshots,
2,243 of them did. There the **sharpness contrast** figure is the one to read; the
per-tile displacement needs a stack of one subject, or of faces alike enough to average
into something recognisable.

Tiles that cannot be matched at all — a mirrored face, an unusual pose, a detection that
landed on the wrong feature — are reported **separately** rather than as a large
displacement, because the number would be meaningless and the fix is different.

## The app

`prosopon-review` reads left to right as the work: **Import**, **Analyze**, **Fine Tune**,
**Mix**. It can start from an empty window or from a run `align` already wrote.

**Import.** One panel takes folders and individual photographs together, with multiple
selection, and a drag onto the window accepts the same mixture. Each folder carries its
own *Look Inside Folders* switch, because a corpus is usually one deep tree beside a
handful of strays and a single setting would be wrong for one of the two. Sources are
remembered between launches as security-scoped bookmarks; one that will not resolve stays
in the list saying **missing — moved, renamed, or on a volume that is not mounted**,
because silently forgetting a folder is how somebody loses a corpus they added months
ago. Space previews the selected photograph. Before anything runs, the banner says how
many were found, how many this run has already aligned, and how many are still to do.

**Analyze** runs the same pipeline the CLI does, in process, and hands the result
straight to Fine Tune. Two settings and no more — which detector, and where the tiles go.

**Fine Tune** is the review queue: it reads `manifest.json` from the run, and a `qa.json`
when it can find one, so the queue can be ordered by distance from the stack consensus.
It looks beside the manifest, in a `qa/` folder under the run, and in a `qa/` folder
beside it; `prosopon qa <run> -o <run>/qa` puts it somewhere it will certainly be found.
Worst first, because finding the few bad tiles is the whole point; nobody should page
through three hundred good ones. A tile that failed a gate was never written, and the row
says which gate rather than showing an empty square.

Dragging a marker means **"the feature you are aiming at is actually here."** The point
travels back through the transform to become the corrected source landmark, and on
release the image moves so that feature lands on the crosshair. The marker returns to its
target, because in canvas space that is where the landmarks always are.

Corrections have to be made in source space for this reason: in canvas space the eyes sit
on their targets by construction whatever the detector did, so there would be nothing to
drag. The image deliberately does not follow the marker mid-drag either — re-solving live
would slide the feature out from under the cursor as it was being aimed at. The metrics
*do* update live, from a provisional solve, so the mouth error can be watched falling
before letting go.

Saving re-renders only the edited tiles and updates the manifest in place, so a later
`stack` or `qa` picks the corrections up with no further step. A correction that pushes a
tile past a gate removes its file and clears its path, rather than leaving a stale tile
for the next stack run to swallow.

**Mix** composes the run's tiles into quartered portraits and shows what came out: a grid
of flattened previews with each composite's four sources and its seam distances underneath,
because whether a mouth joins is a question only looking can answer. The seed is a control
here rather than a flag, since trying another one is the normal way to get a different batch
from the same corpus.

| Key | |
|---|---|
| ↑ / ↓ | previous / next tile |
| ⌘Z | revert the selected tile |
| ⌘S | save corrections |
| ⌘I | add portraits |
| space | look at the selected photograph, in Import |

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
| `ProsoponInsight` | InsightFace `buffalo_l` through ONNX Runtime and CoreML |
| `ProsoponPSD` | layered `.psd` / `.psb` writer |
| `ProsoponQA` | streaming mean and deviation, per-tile registration against consensus |
| `ProsoponMix` | seam measurement, the quadrant assignment, and what a mix run writes |
| `ProsoponPipeline` | load → detect → solve → gate → render, the batch fan-out, and what a run writes. Shared by the CLI and the app, so a run folder is the same folder whichever made it |
| `ProsoponReview` | the app: stages, import sources, the review session, the correction writer |
| `ProsoponCLI` | `align`, `calibrate`, `qa`, `stack`, `mix` |

See [docs/PLAN.md](docs/PLAN.md) for the reasoning, the decisions and what is next.

## Tests

```bash
swift test
```

309 tests, about five minutes. Covers the transform algebra, the solver invariants (including a randomised sweep
asserting the eyes never move), polygon clipping for coverage, a pixel-level check that
landmarks land on their targets in the rendered output without mirroring or flipping,
PackBits round-trips, and a structural reader that walks every declared section length
in a written document and checks it lands where the content actually ends.

The mix is covered at both ends. The assignment is a pure function over measurements, so
the invariants are checked over a whole batch rather than one composite: every tile placed
exactly once, the remainder named, the same seed reproducing and a different one not, the
most frontal half landing on top, and the mouth band outvoting the rest of the seam when
they disagree. The composing is checked against documents on disk — that a quadrant layer
declares the right rectangle, that a cropped layer takes the quarter it sits on rather than
a flipped or mirrored one, and that a hidden marker stays out of the flattened composite.

The app is covered without opening a window. Every string in the toolbar and every dimmed
control is a function of one flat value, so the wording, the enablement and the ordering
are checked by building that value and reading the answer — including that exactly one
control is filled on every stage in every state, and that a source which cannot be read
interrupts whatever else the stage was saying. Source scanning and the bookmarks that
remember it are checked against real folders and real bookmarks in a throwaway defaults
suite, since a folder is what the code reads and only the system can make a bookmark.

The geometry suite runs against all three renderers, so a coordinate bug in one shows up
as a disagreement with the other two. Resampling is pinned by an identity transform
reproducing its source bit-for-bit — Lanczos is 1 at the centre tap and 0 at every other
integer, so anything that misaligns the taps blurs and is caught — and by comparing the
GPU kernel against the CPU reference, which agree to 2 parts in 65535.

The Swift tests prove the document is internally consistent. To prove a *third-party*
reader agrees — that channel order, PackBits coding, alpha handling and the merged
composite are what Photoshop expects rather than merely what we assumed:

```bash
python3 scripts/validate_psd.py ~/faces.psb ~/aligned/*.png     # a stack
python3 scripts/validate_psd.py --mix ~/mixed/mix-manifest.json  # a whole mix run
```

It decodes every layer with `psd-tools` and compares it against the source tile. In `--mix`
mode it walks every composite the manifest names: each quadrant layer's rectangle, its
pixels against the matching quarter of the tile it came from, that the three markers are
hidden, that the flattened composite is the four quadrants assembled, and that no
photograph appears twice across the batch.
