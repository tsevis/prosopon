#!/usr/bin/env bash
#
# Launch the Prosopon review app on an aligned run.
#
#   ./review.sh                     the most recent run found under your home folder
#   ./review.sh ~/aligned           a specific run
#
# The argument is the directory `prosopon align -o` wrote to: the one holding
# manifest.json. With no argument and no run to find, the app opens at Import,
# where portraits can be added and analysed without the command line at all.
#
# A bare SwiftPM executable has no Info.plist, and without one AppKit will run its
# event loop quite happily while never putting a window on screen. So this wraps the
# binary in a minimal .app bundle, which also makes it double-clickable from Finder.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$REPO/.build/release/prosopon-review"
APP="$REPO/.build/Prosopon Review.app"

usage() {
    sed -n '3,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

# --- find the run -----------------------------------------------------------

RUN="${1:-}"
if [[ -z "$RUN" ]]; then
    RUN="$(find "$HOME" -maxdepth 3 -name manifest.json 2>/dev/null \
           | while read -r m; do d="$(dirname "$m")"; echo "$(stat -f '%m' "$d") $d"; done \
           | sort -rn | head -1 | cut -d' ' -f2- || true)"
    [[ -n "$RUN" ]] && echo "No run given; using the most recent: $RUN"
fi
# No run is not an error any more: the app can import and analyse on its own, so
# starting it empty is a perfectly good thing to do. A run that was *named* and is
# not one still is.
if [[ -n "$RUN" ]]; then
    RUN="${RUN/#\~/$HOME}"
    RUN="$(cd "$RUN" 2>/dev/null && pwd)" || { echo "error: no such directory: $1" >&2; exit 1; }
    [[ -f "$RUN/manifest.json" ]] || {
        echo "error: $RUN has no manifest.json — that is what 'prosopon align -o' writes." >&2
        exit 1
    }
fi

# --- build and wrap in an app bundle ----------------------------------------
#
# Assembly lives in scripts/make_app.sh so that this and the disk image cannot drift
# apart. Two of the four recorded causes of "a live process, a menu bar, and no window"
# were assembly mistakes; one copy of that code is one place to get it right.

"$REPO/scripts/make_app.sh" "$APP" --register

# --- launch -----------------------------------------------------------------

if [[ -n "$RUN" ]]; then
    tiles=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['tiles']))" \
            "$RUN/manifest.json" 2>/dev/null || echo "?")
    echo "Opening $tiles tile(s) from $RUN"
    open -a "$APP" --args "$RUN"
else
    echo "No aligned run found; opening at Import."
    open -a "$APP"
fi
echo "Launched. The app is at: $APP"
