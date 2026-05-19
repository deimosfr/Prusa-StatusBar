#!/usr/bin/env bash
# Verify the go2rtc helper bundled inside a built PrusaStatusBar.app matches
# an expected architecture. Used by CI/release workflows to catch a regression
# where the wrong-arch helper ends up in the .app (see PR #16).
#
# Usage: scripts/verify-go2rtc-arch.sh <app-path> <expected-arch>
#   expected-arch: arm64 | x86_64
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <app-path> <expected-arch>" >&2
    exit 2
fi

APP="$1"
EXPECT="$2"
BIN="$APP/Contents/Resources/go2rtc"

if [[ ! -f "$BIN" ]]; then
    echo "go2rtc helper missing from app bundle at $BIN" >&2
    exit 1
fi

file "$BIN"
ARCHS="$(lipo -archs "$BIN")"
echo "go2rtc archs: $ARCHS"

if ! grep -qw "$EXPECT" <<<"$ARCHS"; then
    echo "ARCH MISMATCH: bundled go2rtc is '$ARCHS' but expected $EXPECT" >&2
    exit 1
fi
