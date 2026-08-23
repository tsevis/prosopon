# Next session — GUI rework

Paste the block below into a fresh Claude Code session started in
`~/AI/ClaudeCode/prosopon`.

---

## The prompt

Work in `~/AI/ClaudeCode/prosopon` (private repo, `github.com/tsevis/prosopon`, branch
`master`, all pushed and clean). Read `README.md` and `docs/PLAN.md` first — the plan
carries the reasoning behind the fixed geometry and a running record of what has been
measured, including several places where an earlier assumption turned out to be wrong.

**What Prosopon is.** It maps portrait photographs onto one fixed 2048 × 2048 grid — the
viewer's left eye on (512, 512), the right on (1536, 512), the mouth on (1024, 1664) — so
that fragments of different faces can be cut up and recombined into mosaics. Those three
coordinates are non-negotiable. The pipeline is `align` → `qa` → `stack`, plus a SwiftUI
review app; everything is native Swift with no Python at runtime.

There are two jobs.

### 1. Two small fixes in the review app

Both were seen in the running app and neither blocks use.

- **A rejected tile shows a black thumbnail.** Tiles that fail a gate are never written
  to disk, so `TileRow` in `Sources/ProsoponReview/TileListView.swift` has no image to
  load. Correct behaviour, wrong appearance — it reads as an error rather than as
  "deliberately not exported". Render something that says so.
- **The metrics panel reads "Yaw: not measured"** even when the manifest holds a value.
  `ReviewEntry` (`Sources/ProsoponReview/ReviewEntry.swift`) re-solves from landmarks and
  never carries the detector's yaw through, so `QualityReport.evaluate` is called without
  it. Thread `yawDegrees` from the manifest's `TileRecord` into the entry.

### 2. Rework the GUI around CrewListr Pro's design logic

The reference is `~/AI/ClaudeCode/crewlistr/crewlisterpro/crewlisterpro/app.py`. It is
**PySide6, not SwiftUI** — take the interaction model, not the code.

What to borrow, as seen in that app's toolbar:

- A **stage strip on the left** of the toolbar, reading left to right as the actual
  workflow, each carrying a count once it has one.
- A **subject chip** next to it naming what is loaded and how far along it is
  (CrewListr shows `S/Y ANEMOS · 6/6 cleared`).
- **Actions right-aligned in priority order**, one filled primary and the rest plain,
  with unavailable ones dimmed rather than hidden.
- A **status banner** under the toolbar in plain language — CrewListr's reads
  "Crew list is ready to export."
- CrewListr's `On this Mac only` chip is worth keeping in spirit: Prosopon is entirely
  local too, and saying so costs one control.

The three stages, left to right:

1. **Import portraits** — currently missing entirely; the app can only open a folder that
   `prosopon align` already wrote.
2. **Analyze** — run detection and alignment, which today only exists as the CLI.
3. **Fine Tune** — the review surface that already exists: the queue, the draggable
   landmarks, the live re-solve, save.

#### First: lift the pipeline out of the CLI

Import and Analyze can only be real stages if the app can *run* alignment, and today only
`ProsoponCLI` can. Three files in `Sources/ProsoponCLI/` are pipeline rather than
presentation and belong in a target both the CLI and the app can depend on — say
`ProsoponPipeline`:

- `Pipeline.swift` (129 lines) — load, detect, solve, gate, render for one photograph,
  plus `OutputPlan`
- `BatchRunner.swift` (48 lines) — bounded-concurrency fan-out with progress
- `FaceSelection.swift` (27 lines) — all / largest / central

What stays behind is genuinely CLI: `AlignCommand`, `CalibrateCommand`, `QACommand`,
`StackCommand`, `Summary`, `CSVReport`, `AlignOptions`, `Diagnostics`.

Two things to watch while moving them. `FaceSelection` conforms to
`ExpressibleByArgument`, which is ArgumentParser's and must not follow it into a library
the app links — leave that conformance in the CLI as an extension. And `BatchRunner`
reports progress by writing a bar to stderr; the app needs the same numbers as values,
so give it a progress callback and let the CLI do its own drawing. There are no tests
over these three files today, which is its own argument for moving them somewhere
testable.

Do this before the UI work: it decides what the Analyze stage can actually call.

#### Then: Import portraits

The new surface, and it should follow what Apple's own apps do:

- Add **folders and individual files** in one panel — `NSOpenPanel` with
  `canChooseDirectories` and `canChooseFiles` both true, and multiple selection.
- **Drag and drop** onto the window, accepting a mix of folders and files.
- **Security-scoped bookmarks**, so a folder chosen once is still readable next launch
  rather than silently failing.
- A **source list** showing what was added, with counts, removal, and Reveal in Finder.
- **Recursive or not** as a visible choice, since these corpora nest.
- **Quick Look on space**, and a thumbnail grid rather than a bare list of paths.
- Say **how many images were found** and how many are already aligned, before anything
  runs.

### Things worth knowing before you start

- `./review.sh [run]` builds, wraps the binary in a `.app` and opens it. The bundle is not
  optional: a bare SwiftPM executable has no `Info.plist` and will run its event loop
  without ever showing a window. There is also deliberately **no
  `NSApplicationDelegateAdaptor`** — adding one back suppresses the window on cold launch.
  Both mistakes look identical from outside: live process, menu bar, no window, no error.
- The user's standing rule is **do not launch the app to verify a change unless asked**.
  All the review logic lives in `ProsoponReview` and is tested without opening a window;
  keep it that way and put new logic there too.
- If you kill and relaunch the app while debugging, **wait for the process to actually be
  gone**. `pkill; sleep 1` is not enough, and `open` on a surviving process sends a reopen
  event that makes a broken cold launch look fine.
- `swift test` is 161 tests and takes about five minutes. Run it before committing.
- There is a real corpus at
  `/Users/tsevis/01CLIENTI/a client project/LAB 3/The PEOPLE/ALL PEOPLE` — 2,560 Midjourney
  headshots — and a 16-image working set already aligned at `~/prosopon-test16`. Use the
  small one. The full run takes 25 GB and the volume has been near full.
- Two lessons from this project's own bugs, both worth applying to whatever you write:
  test fixtures should come from the real producer rather than be hand-written in the
  shape the reader expects, and a `try?` that swallows a decode error will hide a dead
  feature for weeks.

Start by reading the code and proposing a plan for the toolbar and the Import stage before
building either.
