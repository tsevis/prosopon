#!/usr/bin/env bash
#
# Build a disk image holding Prosopon Review.app.
#
#   scripts/make_dmg.sh [output.dmg]
#
# Defaults to .build/Prosopon-Review-<version>.dmg. The bundle inside is assembled by
# scripts/make_app.sh, the same code review.sh uses, so the app in the image is the app
# that gets tested rather than a second attempt at building one.
#
# The image is compressed, read-only, and carries an /Applications symlink so it can be
# installed by dragging. It is **ad-hoc signed and not notarised**: on any Mac other than
# this one, Gatekeeper will refuse it on a double-click, and it has to be opened once
# from the context menu, or cleared with
#
#     xattr -dr com.apple.quarantine "/Applications/Prosopon Review.app"
#
# Notarising needs a Developer ID certificate, which this project does not have.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="Prosopon Review"
VERSION="$(grep -o 'CFBundleShortVersionString</key><string>[^<]*' "$REPO/scripts/make_app.sh" \
           | head -1 | sed 's/.*<string>//')"
VERSION="${VERSION:-0.1.0}"

OUTPUT="${1:-$REPO/.build/Prosopon-Review-$VERSION.dmg}"
STAGING="$REPO/.build/dmg-staging"

usage() {
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

# --- the app ----------------------------------------------------------------

rm -rf "$STAGING"
mkdir -p "$STAGING"

# No --register: LaunchServices has no business knowing about a copy that exists only to
# be compressed into an image.
"$REPO/scripts/make_app.sh" "$STAGING/$NAME.app"

# An ad-hoc signature is not a Developer ID one and buys no Gatekeeper trust. What it
# does buy is a bundle macOS treats as intact rather than as damaged code with no
# signature at all, which is worth the one line.
codesign --force --sign - --timestamp=none "$STAGING/$NAME.app" 2>/dev/null \
    || echo "warning: could not ad-hoc sign the bundle; the image is still usable" >&2
codesign --verify --deep --strict "$STAGING/$NAME.app" 2>/dev/null \
    || echo "warning: the ad-hoc signature did not verify" >&2

ln -s /Applications "$STAGING/Applications"

# --- the image --------------------------------------------------------------

rm -f "$OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"

hdiutil create \
    -volname "$NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    "$OUTPUT"

rm -rf "$STAGING"

# --- say what came out ------------------------------------------------------
#
# Verified rather than assumed: an image that mounts but holds an incomplete bundle is
# exactly the failure this project keeps meeting, and it is cheap to rule out here
# instead of on somebody else's Mac.

hdiutil verify "$OUTPUT" >/dev/null 2>&1 || { echo "error: the image does not verify" >&2; exit 1; }

MOUNT="$(mktemp -d)"
hdiutil attach "$OUTPUT" -mountpoint "$MOUNT" -nobrowse -quiet
trap 'hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT

for required in \
    "$NAME.app/Contents/Info.plist" \
    "$NAME.app/Contents/MacOS/prosopon-review" \
    "$NAME.app/Contents/Resources/Prosopon.icns" \
    "$NAME.app/Contents/Resources/Prosopon_ProsoponReview.bundle/Resources/AboutBanner.jpg" \
    "$NAME.app/Contents/Resources/Prosopon_ProsoponReview.bundle/Resources/AppMark.png" \
    "Applications"
do
    [[ -e "$MOUNT/$required" ]] || { echo "error: the image is missing $required" >&2; exit 1; }
done

SIZE="$(du -h "$OUTPUT" | cut -f1 | tr -d ' ')"
echo
echo "  $(basename "$OUTPUT")  $SIZE, version $VERSION"
echo "  every file checked on the mounted image"
echo "  $OUTPUT"
echo
echo "  Unsigned beyond ad-hoc: on another Mac, open it once from the context menu, or"
echo "  run  xattr -dr com.apple.quarantine \"/Applications/$NAME.app\""
echo
