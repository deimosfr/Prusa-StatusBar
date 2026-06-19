#!/usr/bin/env bash
# Download the embedded VLCKit framework if not already present locally.
#
# VLCKit (LGPLv2.1+) is the in-process libvlc engine that decodes the camera
# RTSP/HTTP streams directly, replacing the former bundled go2rtc helper. The
# framework is large (~80 MB per the static libvlc build) and is NOT committed
# to the repo. This script is idempotent: it skips the download when the
# extracted xcframework on disk already matches the expected version + sha256.
# Run automatically as a pre-build step from Xcode (see project.yml) and from
# the `just` recipes.
#
# Source: VideoLAN's official prebuilt VLCKit (the same binary CocoaPods ships),
# pinned by sha256 of the release tarball.
set -euo pipefail

# VLCKit 3.7.3 (stable 3.x line, libVLC 3.0.x + live555). Validated against the
# live Buddy camera (H.264/RTSP) -- the historical libVLC live555 SDP issue that
# motivated go2rtc does not reproduce on this line.
VERSION="3.7.3"
TARBALL="VLCKit-3.7.3-319ed2c0-79128878.tar.xz"
URL="https://download.videolan.org/cocoapods/prod/${TARBALL}"
TARBALL_SHA="019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/Vendor/VLCKit.xcframework"
STAMP="$REPO_ROOT/Vendor/.vlckit-version"

# Reconcile the xcframework Info.plist with our dSYM-stripped layout. The
# upstream xcframework declares `DebugSymbolsPath = dSYMs` per library, but we
# delete the .dSYM bundles above (and the empty `dSYMs` container does not
# survive git, which cannot track empty directories). Xcode 26+ hard-errors
# when that path is missing, so drop the now-dangling key and the empty dir.
# Idempotent: safe to run whether or not the key/dir is still present.
strip_debug_symbols_path() {
    local plist="$DEST/Info.plist"
    [[ -f "$plist" ]] || return 0
    local i=0
    while /usr/libexec/PlistBuddy -c "Print :AvailableLibraries:$i" "$plist" >/dev/null 2>&1; do
        /usr/libexec/PlistBuddy -c "Delete :AvailableLibraries:$i:DebugSymbolsPath" "$plist" >/dev/null 2>&1 || true
        i=$((i + 1))
    done
    rm -rf "$DEST"/macos-*/dSYMs 2>/dev/null || true
}

# Idempotent skip: a matching stamp means the framework on disk is the pinned
# build, so there is nothing to do (the common case on warm CI caches and
# incremental local builds). Still reconcile the Info.plist on the skip path so
# previously fetched/cached copies get the dangling DebugSymbolsPath removed.
if [[ -f "$DEST/Info.plist" && -f "$STAMP" ]]; then
    if [[ "$(cat "$STAMP" 2>/dev/null)" == "${VERSION} ${TARBALL_SHA}" ]]; then
        echo "VLCKit ${VERSION} already present, skipping download"
        strip_debug_symbols_path
        exit 0
    fi
fi

mkdir -p "$REPO_ROOT/Vendor"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $URL"
curl -fsSL --retry 3 --retry-delay 2 "$URL" -o "$WORK/vlckit.tar.xz"

actual="$(shasum -a 256 "$WORK/vlckit.tar.xz" | awk '{print $1}')"
if [[ "$actual" != "$TARBALL_SHA" ]]; then
    echo "Downloaded $TARBALL has unexpected sha256 $actual (expected $TARBALL_SHA)" >&2
    exit 1
fi

echo "Extracting xcframework"
tar -xJf "$WORK/vlckit.tar.xz" -C "$WORK"
SRC_XC="$(find "$WORK" -type d -name 'VLCKit.xcframework' -maxdepth 3 -print -quit)"
if [[ -z "$SRC_XC" ]]; then
    echo "VLCKit.xcframework not found inside $TARBALL" >&2
    exit 1
fi

# Drop debug symbols (.dSYM) before vendoring: they are not needed to build,
# embed, or run VLCKit, and they account for the bulk of the unpacked size.
find "$SRC_XC" -type d -name '*.dSYM' -prune -exec rm -rf {} + 2>/dev/null || true

# Atomically replace any prior copy.
rm -rf "$DEST"
mv "$SRC_XC" "$DEST"

# Drop the dangling DebugSymbolsPath key now that the .dSYM bundles are gone.
strip_debug_symbols_path

printf '%s %s\n' "$VERSION" "$TARBALL_SHA" > "$STAMP"

echo "VLCKit ${VERSION} fetched to $DEST"
lipo -archs "$DEST/macos-arm64_x86_64/VLCKit.framework/Versions/A/VLCKit" 2>/dev/null \
    || echo "(note: could not read framework arch -- check xcframework layout)"
