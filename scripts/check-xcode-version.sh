#!/usr/bin/env bash
# Verify the active Xcode + SDK match the version pinned in .xcode-version.
# Run by `just doctor` and as a build prerequisite. CI workflows read the
# same .xcode-version file so local and CI link against identical SDKs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN_FILE="$REPO_ROOT/.xcode-version"

if [[ ! -f "$PIN_FILE" ]]; then
    echo "ERROR: $PIN_FILE not found. Cannot verify Xcode version."
    exit 1
fi

PINNED="$(tr -d '[:space:]' < "$PIN_FILE")"
PINNED_MAJOR="${PINNED%%.*}"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: xcodebuild not found. Install Xcode $PINNED."
    exit 1
fi

ACTIVE="$(xcodebuild -version 2>/dev/null | awk 'NR==1 { print $2 }')"
ACTIVE_MAJOR="${ACTIVE%%.*}"

SDK="$(xcodebuild -version -sdk macosx ProductVersion 2>/dev/null | tail -1)"
SDK_MAJOR="${SDK%%.*}"

FAIL=0

if [[ "$ACTIVE_MAJOR" != "$PINNED_MAJOR" ]]; then
    echo "ERROR: Xcode major version mismatch."
    echo "  Pinned (.xcode-version): $PINNED"
    echo "  Active (xcodebuild):     $ACTIVE"
    echo ""
    echo "  Builds across mismatched majors bake different SDK metrics into the"
    echo "  binary (LC_BUILD_VERSION sdk), which changes SwiftUI Form padding"
    echo "  and other layout behavior at runtime."
    echo ""
    echo "  Fix: install Xcode $PINNED.x and select it via:"
    echo "    sudo xcode-select -s /Applications/Xcode_$PINNED.app"
    FAIL=1
fi

if [[ -n "$SDK_MAJOR" && "$SDK_MAJOR" != "$PINNED_MAJOR" ]]; then
    echo "WARNING: macOS SDK major version mismatch."
    echo "  Pinned: $PINNED"
    echo "  SDK:    $SDK"
fi

if [[ "$FAIL" -eq 1 ]]; then
    exit 1
fi

echo "Xcode $ACTIVE / SDK $SDK matches pin ($PINNED). OK."
