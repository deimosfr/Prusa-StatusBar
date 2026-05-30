#!/usr/bin/env bash
# Build a distributable DMG from a built PrusaStatusBar.app bundle.
#
# Usage: scripts/make-dmg.sh <app-path> <output-dmg>
#
# Signing is env-driven (inside-out, --deep is deprecated):
#   SIGN_IDENTITY              codesign identity ("-" for ad-hoc, default)
#   ENTITLEMENTS_PATH          app entitlements (default: PrusaStatusBar/PrusaStatusBar.entitlements)
#   SIGN_DMG=1                 also sign the DMG itself (Developer ID only)
#   NOTARIZE=1                 submit DMG to Apple notary + staple ticket
#   NOTARY_PROFILE             notarytool keychain profile name (local dev)
#   NOTARY_KEY / NOTARY_KEY_ID / NOTARY_ISSUER  API-key path + creds (CI)
#
# When SIGN_IDENTITY is "-" the binary is ad-hoc signed and the DMG is NOT
# notarized. Users will then need the Homebrew cask (which strips the
# quarantine xattr in postflight) or run
# `xattr -dr com.apple.quarantine /Applications/PrusaStatusBar.app`.
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <app-path> <output-dmg>" >&2
    exit 1
fi

APP="$1"
DMG="$2"

if [[ ! -d "$APP" ]]; then
    echo "App bundle not found: $APP" >&2
    exit 1
fi

command -v create-dmg >/dev/null || {
    echo "create-dmg not found. Install: brew install create-dmg" >&2
    exit 1
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET_SRC="$REPO_ROOT/PrusaStatusBar/Assets.xcassets/AppIcon.appiconset"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$REPO_ROOT/PrusaStatusBar/PrusaStatusBar.entitlements}"
SIGN_DMG="${SIGN_DMG:-0}"
NOTARIZE="${NOTARIZE:-0}"

is_developer_id() {
    [[ "$SIGN_IDENTITY" != "-" && -n "$SIGN_IDENTITY" ]]
}

CODESIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if is_developer_id; then
    CODESIGN_FLAGS+=(--options=runtime --timestamp)
fi

# Sign nested Mach-O / dylib / so files first (inside-out), skipping the main
# bundle executable (signed last). The static VLCKit build ships no plugin
# dylibs, but this still covers any nested binaries that appear.
while IFS= read -r -d '' f; do
    case "$f" in
        "$APP/Contents/MacOS/"*) continue ;;
    esac
    codesign "${CODESIGN_FLAGS[@]}" "$f" 2>/dev/null || true
done < <(find "$APP/Contents" \( -name '*.dylib' -o -name '*.so' \) -type f -print0)

# Sign the embedded VLCKit framework bundle (after nested dylibs, before the
# main executable and the app bundle).
VLCKIT_FRAMEWORK="$APP/Contents/Frameworks/VLCKit.framework"
if [[ -d "$VLCKIT_FRAMEWORK" ]]; then
    codesign "${CODESIGN_FLAGS[@]}" "$VLCKIT_FRAMEWORK"
fi

# Sign main executable (without entitlements; bundle gets them).
MAIN_BIN="$APP/Contents/MacOS/PrusaStatusBar"
if [[ -f "$MAIN_BIN" ]]; then
    codesign "${CODESIGN_FLAGS[@]}" "$MAIN_BIN"
fi

# Sign the app bundle last with entitlements.
BUNDLE_FLAGS=(--force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS_PATH")
if is_developer_id; then
    BUNDLE_FLAGS+=(--options=runtime --timestamp)
fi
codesign "${BUNDLE_FLAGS[@]}" "$APP"

# Verify signature integrity.
codesign --verify --strict --verbose=4 "$APP"
if is_developer_id; then
    spctl -a -vvv -t exec "$APP" || {
        echo "spctl rejected app bundle (pre-notarization is expected to fail Gatekeeper assessment)" >&2
    }
fi

# Build a .icns from the appiconset PNGs.
ICONSET_DIR="$WORKDIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
declare -a SIZES=("16" "32" "128" "256" "512")
for size in "${SIZES[@]}"; do
    cp "$ICONSET_SRC/icon-${size}.png"   "$ICONSET_DIR/icon_${size}x${size}.png"
    cp "$ICONSET_SRC/icon-${size}@2x.png" "$ICONSET_DIR/icon_${size}x${size}@2x.png"
done
ICNS="$WORKDIR/AppIcon.icns"
iconutil -c icns -o "$ICNS" "$ICONSET_DIR"

# create-dmg expects a staging directory containing only the .app.
STAGE="$WORKDIR/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

rm -f "$DMG"
create-dmg \
    --volname "Prusa StatusBar" \
    --volicon "$ICNS" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 96 \
    --icon "$(basename "$APP")" 160 180 \
    --app-drop-link 380 180 \
    --hide-extension "$(basename "$APP")" \
    --no-internet-enable \
    "$DMG" \
    "$STAGE"

# Sign the DMG itself so spctl accepts it before mount.
if [[ "$SIGN_DMG" == "1" ]]; then
    if ! is_developer_id; then
        echo "SIGN_DMG=1 requires a Developer ID identity (got '$SIGN_IDENTITY')" >&2
        exit 1
    fi
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

# Notarize + staple. Apple notary accepts DMG; ticket attaches to DMG and
# propagates to the embedded app on first launch.
if [[ "$NOTARIZE" == "1" ]]; then
    if ! is_developer_id; then
        echo "NOTARIZE=1 requires a Developer ID identity (got '$SIGN_IDENTITY')" >&2
        exit 1
    fi
    NOTARY_ARGS=()
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    elif [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
        NOTARY_ARGS=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
    else
        echo "NOTARIZE=1 requires NOTARY_PROFILE or (NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER)" >&2
        exit 1
    fi
    echo "Submitting $DMG to Apple notary service (this can take several minutes)"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait --timeout 60m
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl -a -vvv -t install "$DMG"
fi

echo "Built: $DMG"
shasum -a 256 "$DMG"
