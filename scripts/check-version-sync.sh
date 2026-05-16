#!/usr/bin/env bash
# Verify MARKETING_VERSION in the committed Xcode project matches project.yml.
#
# project.yml is the XcodeGen source of truth, but the generated pbxproj is
# also committed (so xcodebuild works without xcodegen on every checkout).
# When project.yml is bumped without re-running `just gen`, local builds and
# released DMGs end up stamped with the stale pbxproj version, and the
# in-app update checker prompts every launch.
#
# Run locally via `just check-version` and from CI on every PR + release.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_YML="$REPO_ROOT/project.yml"
PBXPROJ="$REPO_ROOT/PrusaStatusBar.xcodeproj/project.pbxproj"

if [[ ! -f "$PROJECT_YML" ]]; then
    echo "ERROR: $PROJECT_YML not found." >&2
    exit 1
fi
if [[ ! -f "$PBXPROJ" ]]; then
    echo "ERROR: $PBXPROJ not found." >&2
    exit 1
fi

YML_VERSION=$(grep -E '^[[:space:]]*MARKETING_VERSION:' "$PROJECT_YML" \
    | head -n1 \
    | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"([^"]+)".*/\1/')

if [[ -z "$YML_VERSION" ]]; then
    echo "ERROR: failed to parse MARKETING_VERSION from project.yml" >&2
    exit 1
fi

# Collect unique MARKETING_VERSION values from pbxproj (Debug/Release/Prototype).
# Compatible with Bash 3.2 (macOS default), avoid mapfile.
PBX_VERSIONS=$(grep -E 'MARKETING_VERSION = ' "$PBXPROJ" \
    | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' \
    | sort -u)

if [[ -z "$PBX_VERSIONS" ]]; then
    echo "ERROR: no MARKETING_VERSION entries found in pbxproj" >&2
    exit 1
fi

PBX_COUNT=$(printf '%s\n' "$PBX_VERSIONS" | wc -l | tr -d '[:space:]')

if [[ "$PBX_COUNT" -ne 1 || "$PBX_VERSIONS" != "$YML_VERSION" ]]; then
    echo "ERROR: MARKETING_VERSION drift between project.yml and pbxproj." >&2
    echo "  project.yml:                     $YML_VERSION" >&2
    echo "  PrusaStatusBar.xcodeproj/...     $(echo "$PBX_VERSIONS" | tr '\n' ' ')" >&2
    echo "" >&2
    echo "  Fix locally:" >&2
    echo "    just gen" >&2
    echo "    git add PrusaStatusBar.xcodeproj/project.pbxproj" >&2
    echo "    git commit -m 'build: regenerate Xcode project'" >&2
    exit 1
fi

echo "MARKETING_VERSION in sync: $YML_VERSION"
