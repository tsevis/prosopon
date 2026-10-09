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
| *Lightweight option* | **YuNet** `face_detection_yunet_2023mar.onnx` (227 KB, MIT) — from the OpenCV Zoo | Emits exactly the 5 points needed: both eyes, nose, both mouth corners. Ideal cheap first pass or sanity cross-check. |

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

Built and tested (**309 tests green**, `swift test`, about five minutes):

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
- `ProsoponInsight` — InsightFace `det_10g` + `2d106det` through ONNX Runtime with the
  CoreML provider, checked against the reference Python implementation.
- `ProsoponPipeline` — load, detect, solve, gate, render for one photograph; the bounded
  fan-out over many; source scanning; and what a run writes. Shared by the command line
  and the app.
- `ProsoponReview` — the three stages, the import sources, the review session, live
  preview rendering, and the correction writer, with the SwiftUI views on top of them.
- `ProsoponMix` — seam measurement in Lab, the quadrant assignment, and what a mix run
  writes. See §14.
- `prosopon align`, `prosopon calibrate`, `prosopon stack`, `prosopon qa` and
  `prosopon mix`, with a JSON manifest and sortable CSVs, plus the `prosopon-review` app.

Verified on a real portrait: coverage 100 %, mouth error **0.00 px**, stretch −3.39 %,
and the overlay's discs sit on the eyes and mouth exactly as in the reference images.

The renderer is additionally checked at the pixel level against a synthetic source with
known landmark colours, which is what catches a missing y-flip or a mirrored axis —
failures that a purely mathematical test cannot see.

The stack writer is validated against `psd-tools`: every layer and the merged composite
decode pixel-identical to their source tiles, in both bit depths and both containers.
Measured at 120 layers in 18 s producing 1.3 GB, with resident memory settling near 1 GB
and staying flat rather than growing with the layer count.

---

## 12. The app

Reads left to right as the work — **Import**, **Analyze**, **Fine Tune**, **Mix** — with a
count on each stage, a chip naming what is loaded and how far along it is, actions right-aligned
with exactly one filled control, and one line of plain language under the toolbar. The
interaction model is borrowed from CrewListr Pro on this machine
(`crewlisterpromac/Sources/CrewListrProMac/UI/AppChrome.swift`), not the code.

### Every string is a value

`ChromeState` is a flat struct, and `Stage.badge`, `SubjectChip`, `CommandSet` and
`StatusBanner` are functions of it. What the toolbar says, which control is filled, which
are dimmed and what the banner reads are therefore checked by building a value and
reading the answer — no window, no session, no folder on disk. The SwiftUI files are left
holding arrangement.

That is what pays for the standing rule about not launching the app: the parts that can be
silently wrong are not in the view layer.

Two orderings that took a decision:

- **Fine Tune's badge counts tiles that need attention, not the queue.** Three hundred
  good tiles is not a number anybody tracks.
- **Unsaved corrections outrank a queue that needs attention.** Both are true at once and
  there is one line; work that closing the window would lose comes first.

### The palette is measured

`#E80F9E` is the grid ink in `documents/assets/Splash.jpg`, sampled off the lines. Every
value in `Theme` is that hue at a different lightness.

White on it is **4.21:1**, under the 4.5 floor, and a filled button's label is 12pt
semibold rather than large text — so the fill is four steps darker at 4.55:1 and the
undiluted pink is kept for the icon and the active rule, where nothing is carrying type.
Accent text clears 6.46:1 on white and 5.72:1 on the dark panel; both banner inks clear
7:1 on their own ground.

The banner's two states are one hue apart by saturation rather than by colour, and the
cost is real: green-means-fine is a convention read without thinking and pink-means-fine
is not, so the glyph and the wording carry what colour used to.

The canvas behind a photograph deliberately does not follow the appearance. A tile is
judged against its neighbours and a white surround changes what the eye makes of its
shadows.

### Import

Folders and files in one panel with multiple selection, the same mixture by drag, and a
`Look Inside Folders` switch per folder — a corpus is usually one deep tree beside a
handful of strays, and a single global setting would be wrong for one of the two.

Sources persist as security-scoped bookmarks. The app is not sandboxed today and a plain
path would work; this is written for the day it is, because without one a sandboxed build
would open showing the same four folders and find every one of them empty — a failure with
no error attached to it, which is the kind this project keeps meeting.

A bookmark that will not resolve is **kept and named**, never dropped. So is a decode
failure of the whole list: a `try?` there would empty the source list with no error
anywhere, which is the exact shape of the `qa.json` bug that hid a dead feature for weeks.

### Failures that look like nothing

None of these produces an error, and four of them produce the identical symptom: a live
process, a menu bar, and no window.

- **A resource loaded by asset name comes back empty.** Nino recorded it: the splash
  rendered as a bare gradient and every layout assertion still passed, because a missing
  image is a valid `Image`. Artwork is loaded by URL and `BrandTests` fails when it is nil.
- **The `.app` bundle can be assembled without it.** `Bundle.module` looks in
  `Contents/Resources`, and `review.sh` used to copy only the executable. It now copies the
  resource bundle and the icon, and checks all three files landed rather than letting the
  running app discover it.
- **Reading the run during scene construction races with the window being created.**
  Measured here: the same build and the same arguments produced a window on one launch and
  not the next, with the process alive and idle in its event loop either way. `AppState`
  now reads nothing in `init`; the window goes up first and a `.task` loads into it. Nino
  recorded the same race and both it and CrewListr answer it the same way. `AppStateTests`
  pins the rule by asserting that construction leaves `session` nil.
- **Copying a new binary into the bundle without re-registering it.** Already written down
  in `review.sh` and still easy to do by hand while debugging: the app launches, owns a
  menu bar, and never shows a window. Two hours of this session went into a measurement
  that turned out to be this, not the code under test. Use `review.sh`; it does the
  `touch` and the `lsregister`.

- **`WindowGroup` sometimes does not make its window at all.** The fourth cause, and the
  one that outlived the other three being fixed. Reproduced by killing the running
  instance and starting another straight after: **2 failures in 10 launches**. A `sample`
  of a stuck process shows the main thread idle in `mach_msg` — not a hang, simply an
  event loop with nothing to show. `WindowWatchdog` runs from `App.init` (the only place
  it can: the check has to happen when there is no window, and a `.task` on a view that
  was never created never fires) and sends the reopen event a Dock-icon click sends, which
  SwiftUI's own delegate answers by building the missing window. **30 launches afterwards:
  30 windows, no duplicates.**

  Two faults wear this one face, which is why the first attempt only cut the rate to 1 in
  20. Usually no window is built and reopen builds one; sometimes a window exists and was
  never ordered on screen, and reopen does nothing for that because SwiftUI can see it
  already holds one. So the watchdog distinguishes them — present the window that exists,
  ask for one only when there is none. Asking in the other case is how a slow launch ends
  up with two.

  It is deliberately **not** an `NSApplicationDelegateAdaptor`. Installing one to force
  `setActivationPolicy(.regular)` is what turned this from intermittent into permanent.

The middle two are worth stating together, because they are indistinguishable from outside
and from each other. Anything that measures whether a window appeared has to build the
bundle the way `review.sh` builds it, or it is measuring its own shortcut.

The remedy for the fourth repairs a bad launch within about a second; it does not prevent
one. The underlying race is Apple's, and a verified repair was preferred to a speculative
fix to the cause.

---

## 13. Next

**Deciding which detector to trust, and how much of a corpus survives the gates.** Both
need real portraits, and one run answers them:

```bash
prosopon calibrate ~/portraits --detector insightface
```

Everything else that remains is speculative until that number exists.

Two smaller things the GUI work turned up:

- **`RunManifest` does not record the thresholds a run was aligned with.** A run made with
  `--max-yaw 15 --max-magnification 1.2` re-solves in the app against the defaults and will
  not reproduce its own rejections. The field belongs in the manifest.
- **The Analyze stage writes 8-bit PNG and does not offer the choice.** Right for
  8-bit sources, which is everything measured so far, and wrong the first time somebody
  imports raw.

### Yaw

Gated, not corrected - the fixed eye coordinates determine the scale outright, so there
is no freedom left to compensate for foreshortening. Pose comes from `1k3d68` and agrees
with the reference to 0.47 degrees over a range of -55 to +7.

Only the InsightFace detector can drive it. Vision quantises yaw to 45 degree steps and
reported 0 for faces turned 13, 20 and 37, so `--max-yaw` warns when paired with it. This
is the one respect in which the InsightFace tier is *demonstrably* better rather than
merely faithful to its reference.

The review app now carries the detector's yaw through from the manifest rather than
re-solving without it — and, because Vision's zero is a quantisation rather than a
measurement, a Vision run says so beside the figure instead of asserting a frontal face.

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


---

## 14. Mixing — the quartered portrait

The first thing in this project that makes the artwork rather than the raw material for
it. Modelled on a Photoshop document built by hand: four portraits, one per quadrant, plus
three hidden fill layers marking the two eyes and the mouth, over a white background.

### The geometry, and the join it forces

Seams at `x = 1024` and `y = 1024`. On the fixed grid that puts:

| | |
|---|---|
| left eye (512, 512) | dead centre of the top-left quadrant |
| right eye (1536, 512) | dead centre of the top-right |
| mouth (1024, 1664) | **exactly on the vertical seam**, 640 px below the horizontal one |

So the two bottom quadrants carry **half a mouth each, from two different people**. That is
the hardest join in the picture, and it is only possible because both mouths are on the
same pixels by construction — which is the whole reason §2's coordinates are not
negotiable. Moving the seam off the mouth to make the join easier would be discarding the
only thing that makes it work. `QuadrantGeometryTests` asserts it rather than a comment
claiming it.

### Assignment: measured, not shuffled

Each tile is measured along the eight strips it could present to a neighbour — there are
eight rather than four because which pixels a tile shows depends on where it is placed.
A strip's signature is a **profile of sixteen samples along its length**, each the mean
colour of its segment averaged in **linear light** (a physical mixture, not an average of
gamma-encoded numbers) and converted once to **CIE Lab** (equal distances are roughly
equal differences to the eye), plus σ(L\*) over the whole strip as a small texture term at
weight 0.5.

It was a single mean per strip until it was measured. A seam is 1024 px long and a face
changes a great deal over that distance, so two strips running in opposite directions —
one lightening down the join, the other darkening — have identical means and a visible
break where they meet. The distance now has two parts, because the two failures look
different: a constant offset is a step at the seam, while disagreeing *slopes* are the two
halves drifting apart towards one end, which reads as two pictures rather than one face
and is weighted half again as heavily.

Measured at half resolution by default. A strip mean survives a careful downsample — it is
a mean — and at 2,560 tiles that is the difference between seconds and minutes.

Then, per composite:

1. **The most frontal half of the corpus is reserved for the top quadrants.** Splitting the
   pool by frontality *before* matching satisfies "prefer frontal faces where the eyes are"
   exactly. Expressed instead as a term in the cost function, a strong tone match would
   sometimes outvote it.
2. **The mouth seam first.** Its band (± 192 px) is weighted **4×** the rest of the strip,
   because the strip runs the whole 1024 px bottom half and the mouth is a few hundred of
   them; unweighted, a matching backdrop outvotes a matching mouth.
3. **Then the cheeks**, and the second top pick is scored on the nose bridge as well.

Greedy, O(N²) in cheap vector distances — about 6.5 M of them at N = 2,560, nothing beside
the decodes. An optimal assignment is not worth its cost here, and the costs visibly rise
through a batch as the easy matches are spent: on the twenty-portrait set the mouth-seam
distance went 5.3, 3.5, 4.8, 10.2, 11.9.

**Frontality is yaw when the detector reports a usable one.** Vision quantises to 45°
steps, so a Vision run falls back to the quality score and the manifest records
`frontalityBasis` plus a sentence saying which — a manifest that claimed to be pose-sorted
when it was not would look exactly like one that was.

**Seeded** with SplitMix64, since Swift's own generator cannot be. The seed drives the
shuffle of both pools and every fallback pick; ties inside the cost function break on
filename, so a run is reproducible down to the byte.

**Fallback rather than dropping.** A tile with no measurable strips, or a pool that empties
early, produces a pick taken from the seeded order and recorded as `randomFallback`. Every
image is used exactly once whatever happens.

**The remainder is left out and named.** `N mod 4` tiles cannot make a composite; they are
listed in the manifest with the reason and counted in the summary. A final composite with a
white quadrant is not the artwork, and dropping four photographs silently is how somebody
finds out months later.

### Positioned layers, not masks

The reference document is four full-canvas layers each masked down to one quadrant, which
is what lets a mask be slid afterwards to reveal more of a face. Reproducing it faithfully
would mean implementing the layer-mask section — bounds, default colour, flags, and the
mask's own channel data.

**Decided against, knowingly.** A PSD layer record already carries its own bounding
rectangle, so a quadrant is a 1024 × 1024 layer at its own offset and no mask code has to
exist. Layer pixels drop from ~64 MB to ~16 MB; a composite lands at **25 MB** measured.
The cost is the mask's whole point: a seam can no longer be slid in Photoshop, and the
document has to be regenerated with another seed instead. `StackWriter+Layers.swift` still
writes `no layer mask` into every record, as it always has.

Two consequences worth writing down:

- **`.croppedImage` content.** The tile on disk is the whole 2048 face and the layer wants
  a quarter of it, so the crop happens as the layer is written rather than through
  intermediate files. A crop taken from the wrong quarter, or upside down, produces a
  document that opens perfectly happily and is meaningless — hence a test that reads the
  flattened composite back and checks each quarter is the colour it started as.
- **Hidden layers must not reach the merged composite.** Photoshop computes it from what is
  visible; a stored composite that disagreed would be wrong in whatever opened the file.

The three markers become hidden olive discs 24 px across, drawn with alpha. Same appearance
as a fill revealed through a one-dot mask, a few kilobytes, no mask section.

### One document per composite

Many composites in one document would stack hundreds of quadrant layers on the same canvas:
only the top four visible, the merged composite meaningless, and no way to open one piece
without the other 639. There is no arrangement in which a multi-composite document is the
artwork. `.psd` rather than `stack`'s `.psb`, since 25 MB is nowhere near the 2 GB ceiling
and `.psd` is what everything else opens.

A flattened 512 px preview is written beside each document — the artwork is a picture and
whether a mouth joins is a question only looking can answer — and `--flat png|tiff` writes
a full-size one when the layers are never going to be touched.

### Measured on twenty portraits

A folder from a client project, 20 photographs, five
subjects at four frames each. All 20 cleared the gates at `--max-magnification 8` (median
magnification 2.47), giving exactly five composites and no remainder. The whole mix — 20
tiles measured, five documents and five previews written — took **1.0 s** and 120 MB.
Every quadrant of every document decodes pixel-identical against its source tile under
`psd-tools`, the markers are hidden at the right coordinates, and the flattened composite
is the four quadrants assembled.

### One photograph per composite

Two faces found in one photograph are two tiles with the same `sourcePath`, and quartering
a portrait with itself is not the piece. A candidate whose source is already in the
composite is refused outright; if refusing would leave nothing, the constraint gives way
and the quadrant is recorded as `randomFallback`, because every tile is still used exactly
once.

### The measured failure: tone matching finds the same face

**On the twenty-portrait set every composite repeats a sitter, and two of the five take
three quadrants from one person.** The set is five subjects at four frames each, and each
frame is its own file — so the source guard above never fires.

The cause is not a bug, it is the objective working exactly as specified. The matcher is
asked to find the strip that most closely matches the one beside it, and nothing matches a
face's tone as well as the same face. Given four frames of one sitter in the pool, the best
mouth partner for one of them is almost always another of them.

Nothing in the current measurement can tell "the same person again" from "a very good
match", because at the seam those are the same thing. Two ways out, neither built:

- **Identity.** `w600k_r50.onnx` sits in `~/.insightface/models/buffalo_l` beside the
  detectors already in use. One embedding per tile and a cosine-distance floor between the
  four quadrants would settle it properly, and would also catch the same sitter appearing
  under a different filename.
- **Agreement across all eight strips.** Two frames of one sitter match on *every* strip at
  once; two different faces that happen to meet at the mouth do not also meet at the nose
  bridge and both cheeks. That signal is already computed and currently thrown away. It
  needs a threshold, which means tuning, which means a corpus larger than five people.

On a corpus of distinct identities — the 2,560-image one this is aimed at — the situation
does not arise. On any corpus with several frames per sitter it does, and it is visible
immediately.

### Also not finished

- **Nothing reads the finished canvas.** The manifest now carries `worstSeam` per
  composite — the largest colour difference at any single point along any join, which is
  the figure that corresponds to what a viewer sees, and which an average hides. It is
  still computed from the tiles' own strips rather than from the assembled document, so it
  cannot see anything the composition itself introduces.

---

## 15. The settings that define a run

A run is not just its tiles. Four values decide what those tiles are, and every one of them
was, at some point, held in two places that could disagree: in the manifest of the run on
disk, and in whatever the app happened to default to. Each disagreement destroyed work, and
none of them produced an error.

| setting | what it decides | what losing it looks like |
|---|---|---|
| `maxMagnification` | how far a source may be enlarged | tiles declined and deleted; a correction cannot rescue them |
| `maxStretch` | vertical stretch, so the mouth reaches its target *y* | mouths short of the seam, and a drag that moves the marker and not the face |
| `maxShear` | horizontal shear, so the mouth reaches its target *x* | mouths beside the seam, whatever the stretch does |
| `detector` | Vision or InsightFace | every yaw reported as 0°, and a mix whose pose sort is silently a proxy |

All four are now **written down** in preferences, **adopted** from the run being opened and
from any run already in the output folder, and **recorded** in the manifest. The rule is
that the control describes what pressing the button would actually do, in both directions.

### Why this cost so much

The same corpus of 204 portraits was destroyed three times in one session before the
pattern was visible, and each time the fault was one rung further out than the last:

1. The gate was a constant with no control at all.
2. It became a control, adopted when a run was opened for review — but the app opens with
   no run, which is how it opens from Finder, so nothing set it.
3. It was adopted and persisted, and Fine Tune still ignored it: a drag re-solves against
   `ReviewSession.options`, read from the manifest, and the slider set something else
   entirely. A control that was correct in one place and unreachable from the other.

The third is the one worth remembering. Widening the slider was a real fix to a real
limit — the solver never had a ceiling, only the UI did — and it changed nothing, because
it was connected to the wrong end. "No change" was the correct report.

### Measured: the GUI and the CLI produce the same run

The check that closes it. Align 204 portraits from the command line, then press **Analyse**
in the app on the same corpus and compare:

```
manifest checksum before   56e89e351af833e0ec5b306f10436302
manifest checksum after    56e89e351af833e0ec5b306f10436302
```

Byte-identical. The app re-derived the whole run from scratch — same detector, same caps,
same landmarks, same transforms — and landed exactly where the CLI did. 204 candidates,
204 written, worst mouth error 0.00 px, yaw median 2.71°.

No test can produce this evidence. It needs the real button, the real models and 204 real
photographs, and it is the only thing that demonstrates the two paths are one pipeline
rather than two that agree today.

### Placing a mouth needs both axes

Both eyes are pinned exactly, so the mouth is reached by stretching about the eye line and
shearing about it. Measured on the same 204 portraits with InsightFace landmarks:

| stretch cap | tiles clamped | worst mouth error |
|---|---|---|
| 5 % | 103 / 204 | 140.5 px |
| 12 % | 11 / 204 | 73.2 px |
| 25 % | 0 / 204 | 32.5 px |
| 50 % | 0 / 204 | 32.5 px |

25 % frees every tile and 50 % buys nothing — worth knowing before reaching for a bigger
number than the work needs. The 32.5 px that survives an *uncapped* stretch is entirely
horizontal: stretch owns *y*, shear owns *x*, and the shear budget was still at 5 %. At
**25 % stretch and 20 % shear the worst mouth error over all 204 tiles is 0.00 px** — every
mouth exactly on target.

The cost is narrower than the numbers suggest. Median applied stretch is 4.92 % at both
12 % and 25 %: the extra range is only ever spent on the faces whose proportions were
fighting the canvas, so raising the cap does not distort the corpus.

### A mix folder is output that looks exactly like input

A folder of 51 composites and its `previews/` were added to Import beside the portraits.
Analyse took **306 candidates instead of 204**. The gates rejected 101 of them on coverage
and magnification — and one got through, so a quartered portrait of four different people
entered the corpus as a face.

That ratio is about what it should be. A composite is 2048 × 2048 with two eyes and a mouth
within a few pixels of where a portrait's are, *because that is what it was built from*.
There is no reliable way to tell one from a photograph by looking at the pixels. There is a
completely reliable way to tell by looking beside them: `mix-manifest.json`.

Any directory holding one is now skipped whole, `previews/` included. The output directory
had been excluded for the same reason since the beginning — a run must not import its own
tiles — but that rule only ever covered one folder, and a mix written anywhere else was
invisible to it.

A folder left out this way is **named, not emptied**. `SourceScan.excluded` is kept separate
from `unreadable` because nothing went wrong, and the row says which folder and why:
somebody who drags a mix folder in and reads "0 images found" has been told nothing.
