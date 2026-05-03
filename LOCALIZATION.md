# Localization

Prusa StatusBar uses Apple's classic `.strings` format. Every visible label in
the app reads its text from `PrusaStatusBar/Resources/<lang>.lproj/Localizable.strings`.

The point: **a contributor with no Xcode and no Swift experience can fix or add
a translation by editing one file**. Below is the full recipe.

## Already-shipped languages

| Code      | Language                |
|-----------|-------------------------|
| `en`      | English (source)        |
| `de`      | German                  |
| `fr`      | French                  |
| `es`      | Spanish                 |
| `it`      | Italian                 |
| `cs`      | Czech                   |
| `pl`      | Polish                  |
| `pt-BR`   | Portuguese (Brazil)     |
| `ja`      | Japanese                |
| `zh-Hans` | Simplified Chinese      |

The user picks the active language from Preferences > General > Language. The
default is "System", which follows the macOS preferred-language list.

## Fix a typo or improve a translation (1 step)

1. Open `PrusaStatusBar/Resources/<lang>.lproj/Localizable.strings`
   in any text editor (TextEdit, VS Code, Vim, anything that handles UTF-8).
2. Edit the right-hand side of the offending line. Keep the left-hand side
   (the key) and the trailing `;` untouched. Save. Open a PR.

Example:

```
"general.language.label" = "App language";   // <- edit only the right side
```

You do not need to install Xcode. You do not need to touch any Swift code.

## Add a brand-new language (3 steps)

1. Copy `PrusaStatusBar/Resources/en.lproj/Localizable.strings`
   to `PrusaStatusBar/Resources/<your-code>.lproj/Localizable.strings`.
   Use the canonical locale code (`fr`, `de`, `pt-BR`, `zh-Hant`, etc.).
2. Translate every value (right-hand side of `=`). Do **not** change the keys.
   Untranslated keys fall back to English at runtime, so partial PRs are
   welcome: ship what you have and let others fill the rest.
3. Add the new code to **three** places, then open a PR:
   - `PrusaStatusBar/Services/Localization/LanguageCode.swift`: add a `case`
     whose raw value matches your `.lproj` directory name.
   - `project.yml`: add the code to the `KNOWN_REGIONS` list and to
     `targets.PrusaStatusBar.info.properties.CFBundleLocalizations`.
   - Run `just gen` to regenerate the Xcode project (only needed if you build
     locally; CI re-runs it).

That is the entire workflow. No build steps, no key catalogs to register.

## Format strings

A handful of values contain placeholders such as `%@` (string) or `%lld`
(64-bit integer). Keep these placeholders **exactly as-is** in your
translation, in the same order. Example:

```
"menubar.refresh_connected.footer" = "Used while polling succeeds. %lld s to %lld min.";
```

If the target language naturally reorders the arguments, use positional
placeholders such as `%1$@`, `%2$lld`.

## Key naming convention

Keys are lowercase, dot-separated, and follow a `<surface>.<section>.<element>`
pattern:

- `general.language.label`
- `printer.connection.header`
- `dropdown.job.elapsed_label`
- `notification.finished.title`

If you add a new visible string in code, add the key to `en.lproj` first
(English is the canonical source); other languages can be filled in over
time. Missing keys fall back to English automatically; missing English
falls back to the raw key string, which makes regressions obvious during QA.

## What is intentionally not translated

- The brand name "Prusa StatusBar".
- Other Prusa product names: PrusaLink, PrusaConnect, Buddy Camera.
- Technical placeholders like the UUID example or sample IPs.
- The copyright line.
- SF Symbol names and asset names (those are not user-visible).
