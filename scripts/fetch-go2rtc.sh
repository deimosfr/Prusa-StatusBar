#!/usr/bin/env bash
# Download the bundled go2rtc helper if not already present locally.
#
# The helper is large (~18 MB) and not committed to the repo. This script
# is idempotent: it skips the download when the binary on disk already
# matches the expected sha256. Run automatically as a pre-build step from
# Xcode (see project.yml) and from the `just` recipes.
set -euo pipefail

VERSION="v1.9.14"
ARM64_ASSET="go2rtc_mac_arm64.zip"
ARM64_SHA="6e5039d56d652d2d325cb3ce3f7cc20248a34db42fe8abf9bb13488494ac023e"
AMD64_ASSET="go2rtc_mac_amd64.zip"
AMD64_SHA=""

# Resolve the destination relative to the repo root.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/PrusaStatusBar/Resources/go2rtc"
mkdir -p "$(dirname "$DEST")"

# Set UNIVERSAL=1 to produce a fat (arm64+x86_64) binary via lipo.
# Defaults to native-arch download for fast local dev loops.
UNIVERSAL="${UNIVERSAL:-0}"

# Helper: download go2rtc for a given asset name + sha into a temp file.
# Args: $1 = asset name, $2 = expected sha256 (may be empty), $3 = output path.
fetch_one() {
    local asset="$1"
    local sha="$2"
    local out="$3"
    local url="https://github.com/AlexxIT/go2rtc/releases/download/$VERSION/$asset"
    local tmp
    tmp="$(mktemp -d)"
    echo "Downloading $url"
    curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$tmp/go2rtc.zip"
    unzip -q -o "$tmp/go2rtc.zip" -d "$tmp"
    if [[ -n "$sha" ]]; then
        local actual
        actual="$(shasum -a 256 "$tmp/go2rtc" | awk '{print $1}')"
        if [[ "$actual" != "$sha" ]]; then
            echo "Downloaded $asset has unexpected sha256 $actual (expected $sha)" >&2
            rm -rf "$tmp"
            exit 1
        fi
    fi
    mv "$tmp/go2rtc" "$out"
    rm -rf "$tmp"
}

if [[ "$UNIVERSAL" == "1" ]]; then
    # Universal build: download both arches and lipo-merge into a fat binary.
    if [[ -f "$DEST" ]] && lipo -info "$DEST" 2>/dev/null | grep -q "x86_64 arm64\|arm64 x86_64"; then
        echo "Universal go2rtc already present, skipping download"
        exit 0
    fi
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    fetch_one "$ARM64_ASSET" "$ARM64_SHA" "$WORK/go2rtc.arm64"
    fetch_one "$AMD64_ASSET" "$AMD64_SHA" "$WORK/go2rtc.x86_64"
    lipo -create "$WORK/go2rtc.arm64" "$WORK/go2rtc.x86_64" -output "$DEST"
    chmod +x "$DEST"
    echo "Universal go2rtc written to $DEST"
    lipo -info "$DEST"
    exit 0
fi

# Native single-arch path (local dev). ARCH override lets CI cross-fetch
# the amd64 asset from an arm64 runner (and vice versa).
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
    arm64)  ASSET="$ARM64_ASSET"; SHA="$ARM64_SHA" ;;
    x86_64) ASSET="$AMD64_ASSET"; SHA="$AMD64_SHA" ;;
    *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

if [[ -f "$DEST" && -n "$SHA" ]]; then
    actual="$(shasum -a 256 "$DEST" | awk '{print $1}')"
    if [[ "$actual" == "$SHA" ]]; then
        echo "go2rtc already present and matches expected sha256, skipping download"
        exit 0
    fi
    echo "go2rtc sha mismatch (have $actual, want $SHA), re-downloading"
fi

fetch_one "$ASSET" "$SHA" "$DEST"
chmod +x "$DEST"
echo "go2rtc fetched to $DEST"
