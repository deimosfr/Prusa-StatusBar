# Contributing to Prusa StatusBar

Thanks for considering a contribution.

## Prerequisites

- macOS 14 Sonoma or later.
- Xcode 16+ (Swift Testing required).
- Homebrew tooling:

  ```sh
  brew install just xcodegen swiftlint swiftformat create-dmg
  ```

## First-time setup

```sh
git clone https://github.com/deimosfr/Prusa-StatusBar.git
cd Prusa-StatusBar
just gen           # Generate Xcode project from project.yml
open PrusaStatusBar.xcodeproj
```

`just gen` also runs `scripts/fetch-go2rtc.sh` which downloads the bundled
camera helper (~18 MB, MIT licensed, not committed to the repo).

### Code signing for local builds

By default the project signs ad-hoc (`-`), so any contributor can run
`just build` / `just install` without provisioning a cert. The downside of
ad-hoc signing is that the Keychain item holding your PrusaLink API key
rebinds on every rebuild, so you'll re-grant Keychain access each time.

If you have an Apple Developer ID Application certificate in your login
Keychain, drop an `apple_sign.env` next to `justfile` (gitignored) with at
least:

```sh
MACOS_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID1234)'
MACOS_TEAM_ID='TEAMID1234'
```

The local build recipes pick it up automatically and your Keychain ACL
stays stable across rebuilds.

### Producing a signed + notarized DMG locally

For maintainers with an Apple Developer ID. CI runs the same flow on tag push.

One-time setup, store notarization credentials in the login Keychain:

```sh
xcrun notarytool store-credentials prusa-notary \
    --key ~/path/to/AuthKey_XXXXXXXXXX.p8 \
    --key-id XXXXXXXXXX \
    --issuer YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY
```

Then:

```sh
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID1234)"
just dmg-release arm64        # build, sign, notarize, staple
just verify-dmg PrusaStatusBar-<version>-arm64.dmg
```

`just dmg-signed <arch>` only signs (skips notarization). `just notarize <dmg>`
notarizes a DMG that was already signed.

## Workflow

### 1. Implement and test

```sh
just check        # swiftlint + swiftformat in lint mode
just test         # Swift Testing suite via xcodebuild
just build        # Debug build
just build-prototype   # PROTOTYPE_MODE: in-memory stubs, no network
```

OS integrations (`URLSession`, `SMAppService`, `UNUserNotificationCenter`)
live behind protocols so features stay unit-testable with fakes. New behavior
should land with at least one test.

### 2. Open a PR

The PR template includes a checklist (tests added, `just check` and
`just test` green, prototype mode still builds, screenshots for UI changes).
CI runs the same checks; PRs that fail CI will not be reviewed until they're
green.

## Style rules

- **Strict concurrency**: `SWIFT_STRICT_CONCURRENCY=complete` is on for all
  configs. Treat data races as compile errors.
- **No force unwraps** in production code paths except at framework
  boundaries with an inline justification comment.
- **No API key in `UserDefaults`**. The PrusaLink API key lives in the
  Keychain, period. Never log it, even at debug level.
- **No real network or system side effects from prototype mode code paths.**
  Use the protocol seams.

## Reporting issues

- Bug reports use the bug template (macOS version, app version, printer
  model, firmware, repro steps, logs from
  `log show --predicate 'subsystem == "com.deimosfr.prusastatusbar"' --last 1h`).
- Security issues: see [SECURITY.md](SECURITY.md). Do not file public issues
  for vulnerabilities.

## Code of Conduct

Participation in this project is governed by the
[Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). Report violations
to deimosfr+prusastatusbar@gmail.com.

## License

By contributing, you agree your contributions are licensed under the Apache
License 2.0 (see [LICENSE](LICENSE)).
