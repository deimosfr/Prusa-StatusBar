set shell := ["bash", "-cu"]

# Prefix for commands in recipes. Defaults to `rtk` (token-compacting proxy).
# Set RTK_DISABLE=1 to run commands unwrapped.
rtk := if env_var_or_default("RTK_DISABLE", "") == "1" { "" } else { "rtk" }

bundle_id := "com.deimosfr.prusastatusbar"
project := "PrusaStatusBar.xcodeproj"
scheme := "PrusaStatusBar"

_default:
    @just --list

# Verify the active Xcode + SDK match the version pinned in .xcode-version.
# Catches CI/local SDK skew that bakes different SwiftUI metrics into the
# binary (LC_BUILD_VERSION sdk gates Form padding, etc).
doctor:
    @./scripts/check-xcode-version.sh

# Verify project.yml MARKETING_VERSION matches generated pbxproj. Run after
# bumping the version, or to diagnose stale builds reporting old version.
check-version:
    @./scripts/check-version-sync.sh

# Generate Xcode project from project.yml (idempotent)
gen: doctor fetch-vlckit
    @command -v xcodegen >/dev/null || { echo "xcodegen not found. Install: brew install xcodegen"; exit 1; }
    {{rtk}} xcodegen generate

# Download the embedded VLCKit framework if missing locally (~80 MB, LGPL)
fetch-vlckit:
    {{rtk}} ./scripts/fetch-vlckit.sh

# Verify SwiftLint and SwiftFormat are installed
swift-tools-check:
    @command -v swiftlint >/dev/null || { echo "swiftlint not found. Install: brew install swiftlint"; exit 1; }
    @command -v swiftformat >/dev/null || { echo "swiftformat not found. Install: brew install swiftformat"; exit 1; }

# Lint Swift sources (zero tolerance, warnings become errors)
lint: swift-tools-check
    {{rtk}} swiftlint lint --strict --quiet

# Check formatting without modifying files (for CI / pre-commit)
format-check: swift-tools-check
    {{rtk}} swiftformat --lint .

# Auto-fix formatting in place
format: swift-tools-check
    {{rtk}} swiftformat .

# Run both lint and format checks, use before commits
check: lint format-check

# Run the test suite
test: gen
    set -o pipefail; {{rtk}} xcodebuild test \
        -project {{project}} \
        -scheme {{scheme}} \
        -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO \
        | xcpretty || {{rtk}} xcodebuild test \
            -project {{project}} \
            -scheme {{scheme}} \
            -destination 'platform=macOS' \
            CODE_SIGNING_ALLOWED=NO

# Debug build
build: gen
    if [ -f apple_sign.env ]; then set -a; . ./apple_sign.env; set +a; fi; \
    SIGN_ID="${MACOS_SIGN_IDENTITY:--}"; \
    TEAM_ID="${MACOS_TEAM_ID:-}"; \
    {{rtk}} xcodebuild build \
        -project {{project}} \
        -scheme {{scheme}} \
        -configuration Debug \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$SIGN_ID" \
        DEVELOPMENT_TEAM="$TEAM_ID"

# Prototype build (no real network calls; uses in-memory stub client)
build-prototype: gen
    if [ -f apple_sign.env ]; then set -a; . ./apple_sign.env; set +a; fi; \
    SIGN_ID="${MACOS_SIGN_IDENTITY:--}"; \
    TEAM_ID="${MACOS_TEAM_ID:-}"; \
    {{rtk}} xcodebuild build \
        -project {{project}} \
        -scheme {{scheme}} \
        -configuration Prototype \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$SIGN_ID" \
        DEVELOPMENT_TEAM="$TEAM_ID"

# Release build (Developer ID from apple_sign.env if present, else ad-hoc)
build-release: gen
    if [ -f apple_sign.env ]; then set -a; . ./apple_sign.env; set +a; fi; \
    SIGN_ID="${MACOS_SIGN_IDENTITY:--}"; \
    TEAM_ID="${MACOS_TEAM_ID:-}"; \
    {{rtk}} xcodebuild build \
        -project {{project}} \
        -scheme {{scheme}} \
        -configuration Release \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$SIGN_ID" \
        DEVELOPMENT_TEAM="$TEAM_ID"

# Build then install into /Applications and relaunch
install: build-release
    -pkill PrusaStatusBar 2>/dev/null || true
    sleep 1
    DERIVED=$({{rtk}} xcodebuild -project {{project}} -scheme {{scheme}} -showBuildSettings -configuration Release 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR / { print $3 }' | head -1); \
    cp -Rf "$DERIVED/PrusaStatusBar.app" /Applications/
    sleep 1
    open /Applications/PrusaStatusBar.app

# Build a distributable DMG for the host arch (ad-hoc signed, not notarized)
dmg:
    @just _dmg "$(uname -m)"

# Build an arm64-only DMG (cross-compile if run on Intel)
dmg-arm64:
    @just _dmg arm64

# Build an x86_64-only DMG (cross-compile if run on Apple Silicon)
dmg-x86_64:
    @just _dmg x86_64

# Internal: build + package a single-arch DMG. ARG = arm64 | x86_64
_dmg ARCH: gen
    @command -v create-dmg >/dev/null || { echo "create-dmg not found. Install: brew install create-dmg"; exit 1; }
    ./scripts/fetch-vlckit.sh
    {{rtk}} xcodebuild \
        -project {{project}} \
        -scheme {{scheme}} \
        -configuration Release \
        -derivedDataPath build \
        ARCHS="{{ARCH}}" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="-" \
        DEVELOPMENT_TEAM="" \
        clean build
    lipo -info "build/Build/Products/Release/PrusaStatusBar.app/Contents/MacOS/PrusaStatusBar"
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "dev"); \
    ./scripts/make-dmg.sh \
        "build/Build/Products/Release/PrusaStatusBar.app" \
        "PrusaStatusBar-$VERSION-{{ARCH}}.dmg"

# Build a Developer ID-signed DMG (requires DEVELOPER_ID env var)
dmg-signed ARCH:
    @command -v create-dmg >/dev/null || { echo "create-dmg not found. Install: brew install create-dmg"; exit 1; }
    @test -n "${DEVELOPER_ID:-}" || { echo "DEVELOPER_ID env var is required (e.g. 'Developer ID Application: Name (TEAMID)')"; exit 1; }
    ./scripts/fetch-vlckit.sh
    {{rtk}} xcodebuild \
        -project {{project}} \
        -scheme {{scheme}} \
        -configuration Release \
        -derivedDataPath build \
        ARCHS="{{ARCH}}" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
        DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
        OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
        clean build
    lipo -info "build/Build/Products/Release/PrusaStatusBar.app/Contents/MacOS/PrusaStatusBar"
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "dev"); \
    SIGN_IDENTITY="${DEVELOPER_ID}" SIGN_DMG=1 \
    ./scripts/make-dmg.sh \
        "build/Build/Products/Release/PrusaStatusBar.app" \
        "PrusaStatusBar-$VERSION-{{ARCH}}.dmg"

# Notarize a previously-built DMG and staple the ticket (uses notarytool keychain profile prusa-notary)
notarize DMG:
    xcrun notarytool submit "{{DMG}}" --keychain-profile prusa-notary --wait --timeout 60m
    xcrun stapler staple "{{DMG}}"
    xcrun stapler validate "{{DMG}}"
    spctl -a -vvv -t install "{{DMG}}"

# One-shot: build signed DMG and notarize it. Local equivalent of release.yml.
dmg-release ARCH:
    @test -n "${DEVELOPER_ID:-}" || { echo "DEVELOPER_ID env var is required"; exit 1; }
    ./scripts/fetch-vlckit.sh
    {{rtk}} xcodebuild \
        -project {{project}} \
        -scheme {{scheme}} \
        -configuration Release \
        -derivedDataPath build \
        ARCHS="{{ARCH}}" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
        DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
        OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
        clean build
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "dev"); \
    SIGN_IDENTITY="${DEVELOPER_ID}" SIGN_DMG=1 NOTARIZE=1 \
    NOTARY_PROFILE="${NOTARY_PROFILE:-prusa-notary}" \
    ./scripts/make-dmg.sh \
        "build/Build/Products/Release/PrusaStatusBar.app" \
        "PrusaStatusBar-$VERSION-{{ARCH}}.dmg"

# Verify a DMG passes Gatekeeper, codesign, and stapler checks.
verify-dmg DMG:
    spctl -a -vvv -t install "{{DMG}}"
    xcrun stapler validate "{{DMG}}"
    @echo "Mounting DMG to verify embedded app signature..."
    @MOUNT=$(hdiutil attach -nobrowse -readonly "{{DMG}}" | tail -1 | awk '{print $NF}'); \
    APP=$(find "$MOUNT" -maxdepth 2 -name '*.app' -print -quit); \
    codesign --verify --deep --strict --verbose=4 "$APP"; \
    codesign -dv --verbose=2 "$APP/Contents/Frameworks/VLCKit.framework" 2>&1 | head -20; \
    hdiutil detach "$MOUNT" -quiet

# Remove derived data and generated project
clean:
    rm -rf {{project}} build .build DerivedData

# OpenSpec helpers
spec-list:
    @command -v openspec >/dev/null || { echo "openspec not found. Install: brew install openspec"; exit 1; }
    openspec spec list

spec-validate:
    openspec validate --strict
