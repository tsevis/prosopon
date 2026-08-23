# Kanon — batch portrait alignment to a canonical face grid

Draft 1 · 2026-08-23

---

## 1. Name

**Prosopon** (πρόσωπον) — face, and in the theatre, *mask*. The app takes hundreds of
different faces and renders each one onto the same mask.

---

## 0. What this is for

Prosopon is not an end in itself. The aligned tiles are raw material for **mosaics
assembled from quadrants and fragments of many different portraits** — a strip of one
face's eye butted against another's cheek, another's mouth.

That single fact drives every design decision below, because a fragment of photo A only
butts cleanly against a fragment of photo B when both put the eyes and mouth on
*identical pixels*. Hence:

- the three coordinates are **fixed and non-negotiable**;
- **partial coverage is a hard reject** — a tile with an empty corner cannot be cut up;
- absolute anatomical accuracy matters less than **consistency of definition** across
  the corpus. A landmark convention that is slightly "wrong" but applied identically to
  every face costs nothing; one that wobbles from photo to photo shows up as a visible
  step at every seam.

---

## 2. The specification, made exact

Output canvas: **2048 × 2048**, gridlines every **128 px** (16 × 16 cells).

| Target | Coordinate | Grid cell |
|---|---|---|
| Left eye centre (viewer's left) | (512, 512) | intersection (4, 4) |
| Right eye centre | (1536, 512) | intersection (12, 4) |
| Mouth centre | (1024, 1664) | intersection (8, 13) |

Derived constants:

- Interocular distance **IOD = 1024 px**
- Eye midpoint **C = (1024, 512)**
- Eye-line → mouth drop **D = 1152 px**
- **D / IOD = 1.125** ← the single most consequential number in the whole project. See §4.

Allowed distortion: uniform scale + rotation + translation, plus a **≤ 5 % stretch**.

---

## 3. The core geometry

Three point-correspondences impose 6 constraints. A similarity transform
(rotate + uniform scale + translate) has only 4 degrees of freedom, so it can
satisfy the two eyes exactly and nothing more — the mouth lands wherever the
face's own proportions put it. A full affine has 6 DOF and hits all three points
exactly, but with unbounded distortion. The 5 % cap is what sits between those two,
and it makes the problem a *constrained* fit rather than a solve.

### Recommended decomposition — eyes pinned by construction

**Step 1 — similarity from the eyes only** (closed form, no optimiser):

```
θ = atan2(eR − eL)                    rotation
s = 1024 / ‖eR − eL‖                  uniform scale
t                                     translation putting eL on (512,512)
```

Both eyes are now exactly on target, and the face is upright in canvas space.

**Step 2 — measure the mouth** in that canvas space, at `m' = (mx, my)`:

```
s_y = 1152 / (my − 512)               vertical stretch needed
h   = (1024 − mx) / (my − 512)        shear needed (mouth off centre-line)
```

**Step 3 — clamp, then apply about the eye line `y = 512`:**

```
s_y ← clamp(s_y, 1/1.05, 1.05)
h   ← clamp(h, −h_max, +h_max)        h_max default 0.03 (≈1.7°)

Y = [[1, h], [0, s_y]]  pivoted at y = 512
```

Why this decomposition is the right one:

- **The eyes stay exact for free.** Both lie on `y = 512`, the pivot line, so the
  vertical scale doesn't move them, and the shear displacement `h·(y − 512)` is zero
  there. No least-squares, no drift.
- **The clamps are directly interpretable.** Because the stretch is vertical-only,
  the aspect-ratio change *is* `s_y`, so "≤ 5 % stretch" means literally
  `|s_y − 1| ≤ 0.05`. Every rejected image gets a human-readable reason:
  *"needed 7.3 % stretch, capped at 5 %, mouth lands 31 px high."*
- **Splitting the stretch across both axes is tempting but wrong here.** Applying
  `√s_y` vertically and `1/√s_y` horizontally would halve the visible per-axis
  distortion at constant area — but any horizontal scale about `x = 1024` moves the
  eyes off 512 / 1536. Vertical-only is what keeps the eye constraint free.

A secondary **"balanced residual"** mode should also exist: instead of dumping all
the leftover error on the mouth, run a weighted least-squares fit over all three
points (`w_eye`, `w_mouth`) under the same clamp, letting the eyes drift a few px
so the mouth lands closer. Default off; valuable for the faces that hit the cap hard.

---

## 4. The one thing to decide before writing code

**D / IOD = 1.125 is a taller face than most real faces are.**

Typical adult proportion runs somewhere around 1.05–1.10, with real spread across
individuals. If that holds for your corpus, then the *average* photo needs roughly
5 % vertical stretch just to reach your mouth line — meaning something close to half
your images would sit at or beyond the 5 % cap, and their mouths would land high.
The tool would be permanently fighting its own constraint.

I'm quoting that population figure from memory, so **don't act on it — measure it.**

Build a **Calibrate** command as the very first deliverable: run landmark detection
across the corpus, and report the histogram of native `D / IOD` plus the
distribution of required `s_y`. Then you choose, with real numbers in hand:

1. **Keep 1.125** and accept that N % of images have a high mouth (fine if the mouth
   is less critical than the eyes for your compositing).
2. **Raise the cap** to whatever covers the bulk of the distribution.
3. **Move the mouth target** to your corpus median, so per-image stretch only has to
   absorb the *spread* rather than the spread *plus a constant bias*. This is the
   mathematically cleanest option and costs nothing but a different constant.

This is one afternoon of work and it determines the value of every downstream number.

---

## 5. Landmarks — and two definitions that matter more than model choice

### 5.1 What counts as "the eye centre"

Your reference images show dots centred on the **iris**. But the iris **moves with
gaze** — a subject glancing sideways has an iris centre displaced several px at
2048 scale, and that displacement propagates into scale *and* rotation for the whole
face. The **midpoint of the inner and outer eye corners (canthi)** is gaze-invariant
and anatomically fixed.

Recommendation: **canthus midpoint as the default**, iris centre as a switch. For
alignment across hundreds of faces, *consistency of definition* beats absolute
anatomical correctness — a systematic bias is invisible, per-image jitter is not.

### 5.2 What counts as "the mouth centre"

Your image 2 has an open mouth; images 1 and 3 are closed. The **midpoint of the two
mouth corners (commissures)** is stable under opening and closing; a lip-seam
centroid is not. Default to commissures, offer the seam centroid as an option.

### 5.3 Detector tiers — all three already on this machine

| Tier | Source | Notes |
|---|---|---|
| **Default** | Apple **Vision** `DetectFaceLandmarksRequest` | 76 points incl. pupils and outer/inner lips, plus roll/yaw/pitch. Zero model files, runs on the ANE, no dependency at all. |
| **Accuracy** | InsightFace **`2d106det`** + **`det_10g`** (SCRFD) — `~/.insightface/models/buffalo_l/` | 106 dense points, materially better and steadier than Vision. |
| **Pose / QA** | InsightFace **`1k3d68`** — same folder | 3D 68-point, yields reliable yaw/pitch/roll for gating. |
| *Lightweight option* | **YuNet** `face_detection_yunet_2023mar.onnx` (227 KB, MIT) — `mozaix/plugins/cv/models/` | Emits exactly the 5 points needed: both eyes, nose, both mouth corners. Ideal cheap first pass or sanity cross-check. |

**Integration note:** `coremltools` 8.3 is installed, but its ONNX converter was
removed back in v6 — you can't convert these ONNX files to Core ML directly. The
clean native route is **ONNX Runtime's Objective-C/C package via SPM with the
CoreML execution provider** (`onnxruntime` 1.20.1 here already reports
`CoreMLExecutionProvider`). No Python in the shipping app.

### 5.4 Sub-pixel refinement

Whatever the detector gives, add a refinement pass on a crop around each landmark:
gradient-based radial symmetry (Timm–Barth means-of-gradients) for the iris, and
corner refinement for the canthi. Cheap, and it is the difference between a stack
that averages to a sharp mean face and one that averages to a soft one.

---

## 6. Architecture

Native Mac, no Python at runtime.

```
Kanon.app  (SwiftUI, macOS 15+, Swift 6 strict concurrency)
├── KanonCore        pure-Swift value types, no UI, no I/O
│   ├── Geometry     landmark → transform solve, clamps, residuals
│   ├── Landmarks    protocol + Vision / ONNX backends
│   └── Quality      pose gating, coverage, upsample ratio, score
├── KanonRender      Metal compute kernel: inverse affine + Lanczos-3
├── KanonIO          ImageIO — HEIC/RAW/JPEG/TIFF in, 16-bit out, EXIF, ICC
├── KanonUI          review grid, overlay, manual nudge, mean-face QA
└── kanon (CLI)      same core, headless, scriptable
```

Building the **CLI first on the shared core** is deliberate: it makes the whole
pipeline testable and batch-scriptable, and the GUI becomes a view onto it rather
than the only way in.

### Rendering quality

Resampling is where a technically-correct aligner still produces disappointing
pixels. Requirements:

- **Warp in linear light** — degamma → warp → regamma. Warping in gamma space darkens
  every edge, and across hundreds of stacked faces that reads as mush.
- **Lanczos-3**, not bilinear. Core Image's Lanczos only does pure scale, and vImage's
  affine warp tops out at bilinear — so this wants a small custom **Metal compute
  kernel** applying the inverse affine with a Lanczos-3 tap. ~60 lines, full control,
  and trivially fast on an M1 Ultra.
- **Half-float or 16-bit throughout**, with a fixed working colour space (Display P3
  or sRGB, chosen once) and correct EXIF-orientation handling on input.
- **Out-of-canvas regions**: default to **transparent alpha** plus a coverage mask —
  never silently edge-clamp, which fabricates content that looks real.

---

## 7. Quality metrics (per image, in a sidecar)

The stack is only as good as your ability to throw out the bad members, so every
output ships with:

- full 3×3 transform matrix (lets you re-render at 4096 later without re-detecting)
- source landmarks and their canvas-space residuals
- `s_y` requested vs. applied, and the resulting **mouth error in px**
- **coverage %** — how much of the 2048² canvas has real pixels
- **effective scale** — source px per output px; anything under 1.0 is being
  upsampled and will look soft in the stack
- yaw / pitch / roll, and detector confidence
- a single composite **quality score** for sorting

**Yaw is the dominant failure mode.** A turned head foreshortens the interocular
distance, so the similarity step over-scales the whole face — and no 2D affine can
undo it. Phase 3 should gate on yaw (reject beyond ~±15°) or project landmarks to a
frontal plane using the 3D landmark set first.

---

## 8. UI

- **Review grid** — thumbnails with your exact reference overlay: the 128 px grid,
  the cyan target crosshairs, the landmark dots. You made three of these by hand
  already; the app should generate them for the whole corpus.
- **Sort by quality score**, filter by any metric, so the worst 20 surface immediately.
- **Manual nudge** — drag any of the three landmarks and re-solve live. This is the
  feature that separates a tool from a demo; detectors will fail on a handful out of
  hundreds and you need a 5-second fix, not a re-run.
- **Mean-face QA view** — average the whole aligned stack. If eyes and mouth are
  sharp and everything else is a blur, the alignment is correct. This one view
  validates the entire batch at a glance.
- **Flicker preview** — cycle aligned images at ~8 fps; misalignment reads instantly
  as jitter in a way that static inspection never catches.

---

## 9. Phases

| # | Deliverable | Purpose |
|---|---|---|
| **0** | **Python spike + Calibrate report** on ~30 of your photos | Prove the geometry, compare Vision vs. InsightFace landmarks, and answer §4 *before* committing to Swift. Ends with a mean-face image. |
| **1** | `kanon` CLI on KanonCore + Metal renderer | Full batch pipeline, headless, with sidecars. Already useful on its own. |
| **2** | Kanon.app — review grid, overlay, manual nudge, mean-face | Makes hundreds of images actually manageable. |
| **3** | Accuracy tier: ONNX Runtime backend, iris refinement, pose gating | Tightens the stack; targets the tail of hard images. |
| **4** | Extras: outpaint fill for low-coverage frames (Flux/Qwen are on disk), re-render from stored transforms, presets | Only once 0–3 are solid. |

Phase 0 is throwaway code by design and de-risks everything else.

---

## 10. Decisions

| # | Question | Decision |
|---|---|---|
| 1 | Eye centre | **Canthus midpoint.** Pupils available behind `--use-pupils`. |
| 2 | Mouth centre | **Commissure midpoint** — stable whether the mouth is open or closed. |
| 3 | Is 1.125 negotiable | **No.** All three coordinates are fixed. Calibration becomes a diagnostic, not a decision. |
| 4 | Head upright or eyes level | **Moot — see below.** |
| 5 | Uncovered canvas | **Hard reject.** Anything that cannot fill 2048² is not used. |
| 6 | Multiple faces | **Export all of them**, each as its own tile. |
| 7 | Output format | **Layered Photoshop** — with a size caveat, see below. |

### On question 4: the choice does not exist

Pinning both eyes to (512, 512) and (1536, 512) *forces* the eye line horizontal. There
is no remaining freedom to choose "head upright" instead — eyes level is a consequence
of the fixed coordinates, not a preference.

What survives of that question is the **shear** knob. When a head is tilted or the face
is asymmetric, the mouth drifts off the x = 1024 centre line even with the eyes level.
Shear is the only linear operation that can slide it back without disturbing the eyes,
so shear is where the "how upright should the head look" tradeoff actually lives:

- `--max-shear 0.05` (default) — mouth on centre for almost every face, ~2.9° of lean
  in the lower face at full deflection.
- `--no-shear` — the lower face is left exactly as photographed, mouth allowed to sit
  off-centre.

For mosaic work the default is right: a mouth fragment that is 40 px off-centre will not
line up with its neighbours.

### On question 7: layered Photoshop hits a hard wall

A 2048² RGB layer costs about **12.6 MB at 8-bit** and **25.2 MB at 16-bit**, and RLE
barely compresses photographic data. So:

| Layers | 8-bit | 16-bit |
|---:|---:|---:|
| 100 | 1.3 GB | 2.5 GB |
| 300 | 3.8 GB | 7.6 GB |
| 500 | 6.3 GB | 12.6 GB |

**`.psd` is capped at 2 GB.** A few hundred aligned portraits blows straight past it. The
plan is therefore:

- write **`.psb`** (Large Document Format) for stacks — Photoshop opens it natively, same
  layer model, no practical size ceiling;
- default the stack to **8-bit**, since the sources are 8-bit JPEGs and the extra depth
  buys nothing but file size, with `--bit-depth 16` available;
- `--batch-size` to split a large corpus into several documents;
- keep per-tile 16-bit TIFF as a separate output for anything to be graded individually.

There is no system API for writing PSD/PSB, so this is a hand-written encoder. It is a
well-documented format and a self-contained job, but it is real work — hence its own
milestone rather than a flag on the existing writer.

---

## 11. Status

Built and tested (**39 tests green**, `swift test`):

- `ProsoponCore` — geometry, the two-stage solver, coverage, quality gates. No UI, no I/O,
  no Core Graphics; the maths is testable in isolation and is exercised by a randomised
  sweep asserting the eyes never move.
- `ProsoponIO` — ImageIO loading with EXIF orientation baked in, 16-bit output, the
  verification overlay.
- `ProsoponRender` — Metal Lanczos-3 in linear light, a CPU reference implementation, and
  the Core Graphics renderer they are measured against.
- `ProsoponVision` — Apple Vision landmarks, canthi and commissures recovered as the
  farthest-apart pair in each contour.
- `ProsoponPSD` — a hand-written layered `.psd`/`.psb` encoder, streamed so a
  multi-gigabyte document never has to fit in memory.
- `ProsoponQA` — streaming mean and deviation over a stack, plus per-tile registration
  against the stack's own consensus.
- `prosopon align`, `prosopon calibrate`, `prosopon stack` and `prosopon qa`, with a JSON
  manifest and sortable CSVs.

Verified on a real portrait: coverage 100 %, mouth error **0.00 px**, stretch −3.39 %,
and the overlay's discs sit on the eyes and mouth exactly as in the reference images.

The renderer is additionally checked at the pixel level against a synthetic source with
known landmark colours, which is what catches a missing y-flip or a mirrored axis —
failures that a purely mathematical test cannot see.

The stack writer is validated against `psd-tools`: every layer and the merged composite
decode pixel-identical to their source tiles, in both bit depths and both containers.
Measured at 120 layers in 18 s producing 1.3 GB, with resident memory settling near 1 GB
and staying flat rather than growing with the layer count.

### Next, in order

1. **SwiftUI review app** — the overlay grid over every tile, sorted by score, with
   draggable landmarks and a live re-solve for the handful the detector gets wrong.
2. **InsightFace accuracy tier** — `det_10g` + `2d106det` over ONNX Runtime's CoreML
   provider, plus yaw gating.

### A caveat on the "real portrait" check

The only portrait available on this machine to smoke-test against turned out to be
**reference image 2 itself** — 1024 x 1024, already aligned and already carrying the
target discs and crosshairs. So the visual match against the reference is partly
circular and is *not* evidence that Vision's landmarks land correctly on an unseen
photograph. What it does still establish is unaffected: the solver's arithmetic, the
coverage and magnification measurements, the resampler comparisons (which are about pixel
fidelity, not landmarks), and the QA machinery, which is validated against synthetic
stacks with known injected jitter and against known pixel shifts of real imagery.

Detection accuracy remains unverified on real input. A folder of ordinary portraits
would settle it.

### One empirical note

The first real face measured a native mouth-drop ratio of **1.164** — *above* 1.125,
needing a 3.4 % squash rather than a stretch. That runs against the expectation in §4
that faces would cluster below the target, and the likely reason is definitional: a
canthus midpoint sits differently from a pupil, so the ratio is not comparable to
textbook figures. It is one face. Run `prosopon calibrate` over the real corpus before
drawing any conclusion about how often the 5 % cap will bite.
