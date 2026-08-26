#!/usr/bin/env bash
#
# Assemble the Prosopon Review .app bundle.
#
#   scripts/make_app.sh <destination.app> [--register]
#
# Shared by review.sh and make_dmg.sh rather than written twice, because getting a
# bundle subtly wrong is this project's most expensive recurring mistake. Four separate
# causes have produced one identical symptom -- a live process, a menu bar, and no
# window -- and two of them were assembly: a missing Info.plist, and copying only the
# executable so `Bundle.module` found no resources. See docs/PLAN.md section 12.
#
# --register touches the bundle and hands it to LaunchServices, which is needed before
# opening it locally and pointless for one being staged into a disk image.

set -euo pipefail

APP="${1:?usage: make_app.sh <destination.app> [--register]}"
REGISTER="${2:-}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.build/release/prosopon-review"
RESOURCE_BUNDLE="$REPO/.build/release/Prosopon_ProsoponReview.bundle"

# --- build if needed --------------------------------------------------------

if [[ ! -x "$BIN" ]] || [[ -n "$(find "$REPO/Sources" "$REPO/Package.swift" -newer "$BIN" -print -quit 2>/dev/null)" ]]; then
    echo "Building prosopon-review…"
    ( cd "$REPO" && swift build -c release --product prosopon-review )
fi

[[ -d "$RESOURCE_BUNDLE" ]] || {
    echo "error: $RESOURCE_BUNDLE is missing. Did the build finish?" >&2
    exit 1
}

# --- assemble ---------------------------------------------------------------

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

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
    <key>CFBundleShortVersionString</key><string>0.4.2</string>
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
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
cp -f "$REPO/Resources/Prosopon.icns" "$APP/Contents/Resources/Prosopon.icns"

# Say so here rather than discovering it in the running app.
for required in \
    "Contents/Info.plist" \
    "Contents/MacOS/prosopon-review" \
    "Contents/Resources/Prosopon.icns" \
    "Contents/Resources/Prosopon_ProsoponReview.bundle/Resources/AboutBanner.jpg" \
    "Contents/Resources/Prosopon_ProsoponReview.bundle/Resources/AppMark.png"
do
    [[ -e "$APP/$required" ]] || { echo "error: the bundle is missing $required" >&2; exit 1; }
done

if [[ "$REGISTER" == "--register" ]]; then
    # Let LaunchServices see the finished bundle before opening it. Registering a bundle
    # whose Info.plist was still being written leaves it launchable but window-less: the
    # menu bar appears and no content window ever does.
    touch "$APP"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$APP" >/dev/null 2>&1 || true
fi
