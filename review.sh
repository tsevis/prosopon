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

# --- build if needed --------------------------------------------------------

if [[ ! -x "$BIN" ]] || [[ -n "$(find "$REPO/Sources" "$REPO/Package.swift" -newer "$BIN" -print -quit 2>/dev/null)" ]]; then
    echo "Building prosopon-review…"
    ( cd "$REPO" && swift build -c release --product prosopon-review )
fi

# --- wrap in an app bundle --------------------------------------------------

mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>prosopon-review</string>
    <key>CFBundleIdentifier</key><string>com.tsevis.prosopon.review</string>
    <key>CFBundleName</key><string>Prosopon Review</string>
    <key>CFBundleDisplayName</key><string>Prosopon Review</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>Prosopon</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
cp -f "$BIN" "$APP/Contents/MacOS/prosopon-review"

# The artwork is a SwiftPM resource bundle sitting beside the built binary, and
# `Bundle.module` looks for it in the app's Contents/Resources. Copying only the
# executable leaves the info panel rendering a bare gradient with no error anywhere --
# the same silent failure the code comments in Brand.swift are about, one level up.
mkdir -p "$APP/Contents/Resources"
RESOURCE_BUNDLE="$REPO/.build/release/Prosopon_ProsoponReview.bundle"
[[ -d "$RESOURCE_BUNDLE" ]] || {
    echo "error: $RESOURCE_BUNDLE is missing. Did the build finish?" >&2
    exit 1
}
rm -rf "$APP/Contents/Resources/Prosopon_ProsoponReview.bundle"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
cp -f "$REPO/Resources/Prosopon.icns" "$APP/Contents/Resources/Prosopon.icns"

# Say so here rather than discovering it in the running app.
for required in \
    "Contents/Resources/Prosopon.icns" \
    "Contents/Resources/Prosopon_ProsoponReview.bundle/Resources/AboutBanner.jpg" \
    "Contents/Resources/Prosopon_ProsoponReview.bundle/Resources/AppMark.png"
do
    [[ -e "$APP/$required" ]] || { echo "error: the bundle is missing $required" >&2; exit 1; }
done

# Let LaunchServices see the finished bundle before opening it. Registering a bundle
# whose Info.plist was still being written leaves it launchable but window-less: the
# menu bar appears and no content window ever does.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" >/dev/null 2>&1 || true

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
