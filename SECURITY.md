# Security Policy

## Supported Versions

Only the latest tagged release receives security fixes. Older versions are not
patched. Update via Homebrew (`brew upgrade --cask deimosfr/tap/prusa-statusbar`)
or by downloading the latest DMG from the GitHub Releases page.

## Reporting a Vulnerability

Please do **not** open a public GitHub issue for security problems.

Email **deimosfr+prusastatusbar@gmail.com** with:

- A description of the issue and its impact.
- Steps to reproduce, or a proof-of-concept if available.
- The app version (Preferences > About) and macOS version.
- Whether the issue is already public.

You should expect an acknowledgement within 7 days. If the report is valid, a
fix will be released and credited (unless you ask to remain anonymous). The
disclosure window is 90 days from the acknowledgement, after which the issue
may be disclosed publicly even if no fix has shipped.

## Scope

In scope:

- The Prusa StatusBar macOS app (this repository).
- Build pipeline, release artifacts (DMG), and the Homebrew cask in
  `deimosfr/homebrew-tap`.

Out of scope:

- Vulnerabilities in PrusaLink firmware or the Prusa printer itself: report
  those upstream to Prusa Research.
- Vulnerabilities in third-party dependencies (`go2rtc`, etc.): report to the
  upstream project. If the integration here exposes a dependency issue in a
  way the upstream project does not, we want to know.
