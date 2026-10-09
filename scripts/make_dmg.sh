#!/usr/bin/env bash
#
# Build a disk image holding Prosopon Review.app, signed and notarised.
#
#   scripts/make_dmg.sh [output.dmg] [--ad-hoc] [--no-notarise]
#
# Writes dist/Prosopon-Review-<version>.dmg **inside the repository**, where git ignores
# it (dist/*.dmg): attach the signed image to a GitHub Release rather than committing it.
# Not .build/ -- that is SwiftPM's scratch directory, and `swift package clean` deletes
# it, so an image built there exists only until the next tidy-up.
#
# The bundle inside is assembled by scripts/make_app.sh, the same code review.sh uses, so
# the app in the image is the app that gets tested rather than a second attempt at
# building one.
#
# The image is compressed, read-only, and carries an /Applications symlink so it can be
# installed by dragging.
#
# Signing needs a Developer ID Application certificate in the login keychain, and
# notarising needs credentials stored once with
#
#     xcrun notarytool store-credentials prosopon-notary \
#         --apple-id <apple-id> --team-id <TEAM_ID>
#
# The certificate is found by Apple team ID, read from PROSOPON_TEAM_ID (or APPLE_TEAM_ID);
# set PROSOPON_SIGN_IDENTITY to name the certificate directly instead.
#
# With neither a team ID (PROSOPON_TEAM_ID or APPLE_TEAM_ID) nor PROSOPON_SIGN_IDENTITY
# set, the script exits with an error unless --ad-hoc is passed. With a team ID but no
# matching certificate it says so and falls back to an ad-hoc image; with no notarytool
# credentials it signs but skips notarising. An ad-hoc image is refused by Gatekeeper on
# any other Mac. --ad-hoc forces that image; --no-notarise signs properly but skips the
# round trip to Apple, which is what you want while iterating.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="Prosopon Review"
VERSION="$(grep -o 'CFBundleShortVersionString</key><string>[^<]*' "$REPO/scripts/make_app.sh" \
           | head -1 | sed 's/.*<string>//')"
VERSION="${VERSION:-0.4.2}"

TEAM_ID="${PROSOPON_TEAM_ID:-${APPLE_TEAM_ID:-}}"
NOTARY_PROFILE="${PROSOPON_NOTARY_PROFILE:-prosopon-notary}"

STAGING="$REPO/.build/dmg-staging"
OUTPUT=""
FORCE_AD_HOC=0
NOTARISE=1

usage() {
    sed -n '3,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
}

for arg in "$@"; do
    case "$arg" in
        -h|--help)                usage ;;
        --ad-hoc|--adhoc)         FORCE_AD_HOC=1 ;;
        --no-notarise|--no-notarize) NOTARISE=0 ;;
        -*)                       echo "error: unknown option $arg" >&2; exit 1 ;;
        *)                        OUTPUT="$arg" ;;
    esac
done
OUTPUT="${OUTPUT:-$REPO/dist/Prosopon-Review-$VERSION.dmg}"

# --- who is signing ---------------------------------------------------------
#
# Resolved once, up front, so the script can say what kind of image it is about to make
# before spending two minutes making it.

IDENTITY=""
if (( ! FORCE_AD_HOC )); then
    IDENTITY="${PROSOPON_SIGN_IDENTITY:-}"
    if [[ -z "$IDENTITY" ]]; then
        [[ -n "$TEAM_ID" ]] || {
            echo "error: set APPLE_TEAM_ID (or PROSOPON_SIGN_IDENTITY) to sign, or pass --ad-hoc" >&2
            exit 1
        }
        IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
                    | sed -n "s/.*\"\(Developer ID Application: .*($TEAM_ID)\)\".*/\1/p" \
                    | head -1)"
    fi
    [[ -z "$IDENTITY" ]] && echo "note: no Developer ID Application certificate for team $TEAM_ID; falling back to ad-hoc" >&2
fi

if [[ -n "$IDENTITY" ]] && (( NOTARISE )); then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
        echo "note: no notarytool credentials under profile '$NOTARY_PROFILE'; signing without notarising" >&2
        NOTARISE=0
    }
fi

# --- signing ----------------------------------------------------------------
#
# --options runtime is what makes the signature notarisable: Apple rejects a submission
# without the hardened runtime. There is no nested code in the bundle -- ONNX Runtime is
# a static library, so `otool -L` shows nothing outside /usr/lib and /System -- which is
# why one codesign call over the .app is the whole job and --deep is not needed. No
# entitlements are claimed: the app is not sandboxed, it JITs nothing, and CoreML runs
# under the hardened runtime unaided.

sign() {
    local target="$1"
    if [[ -n "$IDENTITY" ]]; then
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$target"
        codesign --verify --strict "$target" \
            || { echo "error: the Developer ID signature on $(basename "$target") did not verify" >&2; exit 1; }
    else
        # An ad-hoc signature buys no Gatekeeper trust. What it does buy is a bundle
        # macOS treats as intact rather than as damaged code with no signature at all,
        # which is worth the one line.
        codesign --force --sign - --timestamp=none "$target" 2>/dev/null \
            || echo "warning: could not ad-hoc sign $(basename "$target"); the image is still usable" >&2
        codesign --verify --strict "$target" 2>/dev/null \
            || echo "warning: the ad-hoc signature did not verify" >&2
    fi
}

# Both the app and the image get their own ticket. Stapling only the image would leave
# the copy dragged to /Applications relying on an online check at first launch, which is
# the one moment a new user is least forgiving of a spinner and a refusal.
notarise() {                       # notarise <what-to-upload> <what-to-staple>
    local upload="$1" target="$2" out id
    echo "  submitting $(basename "$target") to Apple…"
    out="$(xcrun notarytool submit "$upload" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
    id="$(printf '%s\n' "$out" | sed -n 's/^ *id: \([0-9a-f-]\{36\}\)$/\1/p' | head -1)"
    if ! printf '%s\n' "$out" | grep -q "status: Accepted"; then
        printf '%s\n' "$out" | sed 's/^/    /' >&2
        echo "error: notarisation did not succeed" >&2
        [[ -n "$id" ]] && echo "  xcrun notarytool log $id --keychain-profile $NOTARY_PROFILE" >&2
        exit 1
    fi
    xcrun stapler staple "$target" >/dev/null \
        || { echo "error: could not staple the ticket to $(basename "$target")" >&2; exit 1; }
}

# --- the app ----------------------------------------------------------------

rm -rf "$STAGING"
mkdir -p "$STAGING"

# No --register: LaunchServices has no business knowing about a copy that exists only to
# be compressed into an image.
"$REPO/scripts/make_app.sh" "$STAGING/$NAME.app"

sign "$STAGING/$NAME.app"

if [[ -n "$IDENTITY" ]] && (( NOTARISE )); then
    # notarytool will not take a bare .app, and ditto's zip is the archive format Apple
    # documents for this. It exists only to carry the bundle there; the ticket is
    # stapled to the .app itself.
    ZIP="$REPO/.build/$NAME.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$STAGING/$NAME.app" "$ZIP"
    notarise "$ZIP" "$STAGING/$NAME.app"
    rm -f "$ZIP"
fi

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

sign "$OUTPUT"

if [[ -n "$IDENTITY" ]] && (( NOTARISE )); then
    notarise "$OUTPUT" "$OUTPUT"
fi

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

# The question a user's Mac will ask, asked here first. On a notarised build this prints
# "accepted" with source=Notarized Developer ID; a signed-but-unnotarised one is rejected
# by design, so it is only worth asking when a ticket should exist.
GATEKEEPER=""
if [[ -n "$IDENTITY" ]] && (( NOTARISE )); then
    GATEKEEPER="$(spctl --assess --type exec -vv "$MOUNT/$NAME.app" 2>&1 | sed -n 's/^source=/source /p' | head -1)"
    spctl --assess --type exec "$MOUNT/$NAME.app" >/dev/null 2>&1 \
        || { echo "error: Gatekeeper rejects the app on the finished image" >&2; exit 1; }
fi

SIZE="$(du -h "$OUTPUT" | cut -f1 | tr -d ' ')"
echo
echo "  $(basename "$OUTPUT")  $SIZE, version $VERSION"
echo "  every file checked on the mounted image"
case "$OUTPUT" in
    "$REPO/"*) echo "  ${OUTPUT#"$REPO/"}  (git-ignored — attach it to a GitHub Release)" ;;
    *)         echo "  $OUTPUT" ;;
esac
echo
if [[ -n "$IDENTITY" ]] && (( NOTARISE )); then
    echo "  Signed as $IDENTITY"
    echo "  Notarised and stapled, app and image both${GATEKEEPER:+ — Gatekeeper: $GATEKEEPER}"
    echo "  It will open on another Mac with a double-click."
elif [[ -n "$IDENTITY" ]]; then
    echo "  Signed as $IDENTITY, not notarised."
    echo "  Gatekeeper still refuses it elsewhere; run without --no-notarise for a release."
else
    echo "  Unsigned beyond ad-hoc: on another Mac, open it once from the context menu, or"
    echo "  run  xattr -dr com.apple.quarantine \"/Applications/$NAME.app\""
fi
echo
