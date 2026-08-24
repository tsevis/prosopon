# Next session — Mix

Paste the block below into a fresh Claude Code session started in
`~/AI/ClaudeCode/prosopon`.

---

## The prompt

Work in `~/AI/ClaudeCode/prosopon` (private repo, `github.com/tsevis/prosopon`, branch
`master`, all pushed and clean). Read `README.md` and `docs/PLAN.md` first — the plan
carries the reasoning behind the fixed geometry, a record of what has been measured, and
several places where an earlier assumption turned out to be wrong.

**What Prosopon is.** It maps portrait photographs onto one fixed 2048 × 2048 grid —
viewer's left eye on (512, 512), right on (1536, 512), mouth on (1024, 1664) — so
fragments of different faces can be cut up and recombined into mosaics. Those three
coordinates are non-negotiable. The pipeline is `align` → `qa` → `stack` on the command
line, plus a SwiftUI app with three stages: Import, Analyze, Fine Tune. Native Swift, no
Python at runtime. `swift test` is 253 tests and about five minutes.

### The job

**Everything built so far produces the raw material. This is the first thing that makes
the actual artwork.** Add a fourth stage — call it **Mix** — that takes a folder of
aligned tiles and composes them into quartered portraits: each output is one 2048 × 2048
canvas divided into four 1024 × 1024 quadrants, each quadrant coming from a different
photograph.

The reference is a Photoshop document built by hand. Its layer stack is:

```
Color Fill 1 copy 2   olive, mask = black with one white dot   (hidden)
Color Fill 1 copy     olive, mask = black with one white dot   (hidden)
Color Fill 1          olive, mask = black with one white dot   (hidden)
Layer 3               portrait, mask = black with white square, top-left
Layer 2               portrait, mask = black with white square, top-right
Layer 4               portrait, mask = black with white square, bottom-left
Layer 1               portrait, no mask  (fills the remaining quadrant)
Background            white, locked
```

Four faces, four quadrants, and the three hidden fill layers are the landmark markers —
the two eyes and the mouth.

### The geometry, and the one thing about it that matters

The quadrant seams are at **x = 1024** and **y = 1024**. On the fixed grid that puts:

- the left eye (512, 512) well inside the top-left quadrant,
- the right eye (1536, 512) well inside the top-right,
- and **the mouth (1024, 1664) exactly on the vertical seam.**

So the two bottom quadrants each carry one half of a mouth, from two different people.
That is visible in the reference document and it is the hardest join in the picture — it
only works because both mouths are on the same pixels by construction. Do not
"helpfully" move the seam off the mouth to avoid it.

### Assignment — driven by a measurement, not random

Hundreds of aligned tiles in, N ÷ 4 composites out. **Each source image is used exactly
once, in one quadrant, in one composite** — no image appears twice anywhere in the batch.
Only tiles that were actually written count; a tile the gates declined has no file.

Choose each set of four so the joins work, rather than shuffling and hoping. The seam
that matters most is the vertical one between the two bottom quadrants, because the mouth
sits exactly on it and each side carries half a mouth: match on tone and brightness
sampled from a narrow strip along that seam, then the horizontal seams. Prefer the most
frontal faces — lowest yaw — for the two top quadrants, where the eyes are and where the
eye goes first.

Treat this as best-effort. It is a matching problem over hundreds of tiles, so a good
greedy pass is fine and an optimal one is not required. Keep it seeded and reproducible,
and have the run manifest record what each quadrant was matched on, so a bad join can be
traced rather than guessed at. If the matching cannot place a tile, fall back to random
for the remainder rather than dropping it — every image is still used exactly once.

Decide and write down what happens to the remainder when N is not a multiple of four.

### Output — positioned 1024 × 1024 layers, no masks

**Do not implement layer masks.** Each layer carries only its own quadrant and sits at its
own offset, which the format already supports through the layer record's bounding
rectangle. Leave `StackWriter+Layers.swift` writing `no layer mask` as it does today.

This is a deliberate trade and both halves of it should stay written down. It gives files
roughly a quarter the size — about 13 MB a composite instead of 50 — and needs no new
format work at all. What it costs is the thing the reference document is arranged for: a
seam can no longer be slid in Photoshop afterwards to reveal more of a face, and the
document has to be regenerated instead. That cost is accepted.

`ProsoponPSD` cannot write masks today in any case: `StackWriter+Layers.swift:173` writes
a literal `no layer mask` into every layer record, and `StackLayer` is a name and a URL —
full-canvas layers only. The writer is streamed and validated against `psd-tools` by
`scripts/validate_psd.py`; keep both properties.

The three marker layers are worth reproducing as hidden solid-colour layers, because they
are what lets a join be checked by eye.

A hundred composites is over a gigabyte, so decide between one document per composite and
one document holding many, and say why.

### Where it goes in the app

The chrome is already built for this. `Stage` is an enum in
`Sources/ProsoponReview/Chrome/Stage.swift`; adding a case gives you a tab, a badge and a
tooltip. What the toolbar says and which control is filled comes from `CommandSet`, the
banner line from `StatusBanner`, and both are pure functions of a flat `ChromeState` — so
**every string and every dimmed control in the new stage is testable without opening a
window**, and that is the standing arrangement, not an optional one. Follow it: put the
composition logic in a library target with tests, and leave the SwiftUI file holding
arrangement.

The composing itself belongs in a target the CLI can reach too, alongside
`ProsoponPipeline`, so this is scriptable over the 2,560-image corpus without the app.

### Things worth knowing before you start

- `./review.sh [run]` builds, wraps the binary in a `.app` and opens it. **The bundle is
  not optional** and there is deliberately no `NSApplicationDelegateAdaptor`.
- **Four separate causes in this project have produced one identical symptom: a live
  process, a menu bar, and no window.** A missing `Info.plist`; the delegate adaptor; a
  bundle registered while its plist was still being written; and reading a manifest during
  scene construction, which races with the window being created. `docs/PLAN.md` §12 lists
  them. If you measure whether a window appeared, assemble the bundle the way `review.sh`
  does — a hand-copied binary without `touch` and `lsregister` reproduces the failure and
  wasted two hours of an earlier session.
- **Do not launch the app to verify a change unless asked.** If you kill and relaunch while
  debugging, wait for the process to actually be gone; `pkill; sleep 1` is not enough, and
  `open` on a survivor sends a reopen event that makes a broken cold launch look fine.
- Use the 16-image set at `~/prosopon-test16`, not the 2,560-image corpus at
  `/Users/tsevis/01CLIENTI/a client project/LAB 3/The PEOPLE/ALL PEOPLE`. The full run is 25 GB and
  the volume has been near full. Note that test16's sources need `--max-magnification 8`
  to clear the gates.
- Two lessons from this project's own bugs, both still live: **test fixtures should come
  from the real producer** rather than be hand-written in the shape the reader expects, and
  **a `try?` that swallows a decode error will hide a dead feature for weeks**.
- Run `swift test` before committing.

Start by reading the code and proposing a plan — the matching rules, the file layout, and
how a composite is named and recorded — before building any of it.
