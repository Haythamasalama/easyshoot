# Contributing to EasyShoot

Thank you for helping improve EasyShoot. This guide shows how to set up the project, what we expect in a pull request, and how to add a translation.

## Ways to help

- **Report a bug.** Open an [issue](https://github.com/Haythamasalama/easyshoot/issues/new/choose) with your macOS version, the steps to reproduce it, and a screenshot if you can.
- **Suggest a feature.** Describe the problem first, then the solution you have in mind.
- **Translate.** Improve an existing language or add a new one (see below).
- **Write code.** Pick an issue labelled `good first issue` or `help wanted`, and leave a comment so others know you're working on it.

## Set up

Requirements: macOS 14 or later and Xcode 15 or later (Xcode 26 to build the Liquid Glass look).

```bash
git clone https://github.com/<you>/easyshoot.git
cd easyshoot
swift build
swift test
./scripts/build-app.sh && open build/EasyShoot.app
```

macOS ties Screen Recording permission to the app's signature. Ad-hoc builds change signature each time, so you may need to grant the permission again after rebuilding. To avoid that, sign with your own certificate: `SIGN_IDENTITY="Apple Development: …" ./scripts/build-app.sh`.

## How the code is organized

- **`Renderer`** draws a document into a Core Graphics context. The editor canvas and the exporter both use it, so what you see is what you export. New annotation types go here first.
- **`EditorModel`** holds the document, the tool, undo history and export settings. Views read from it and call its methods.
- **`CanvasView`** (AppKit) handles mouse, keyboard and text editing. The rest of the editor is SwiftUI.
- **`ImageStitcher`** joins scrolling-capture frames using per-row signatures. It is plain Swift with unit tests, so you can work on it without capturing the screen.
- **`ShortcutStore`** and **`HotKeyManager`** own the global shortcuts.

## Code style

- Follow the style of the surrounding code: Swift 5 language mode, four-space indentation, `// MARK:` sections, and small types with clear names.
- UI code is `@MainActor`. Avoid new dependencies; the project uses only Apple frameworks.
- Every user-visible string goes through `L("…")` or a SwiftUI literal, so that it can be translated.
- Use `Brand.signal` for accents and the `glassSurface()` / `primaryButtonStyle()` helpers for surfaces and buttons, so the app looks consistent on macOS 14 and on macOS 26.
- Respect the privacy promise: no analytics, no network calls except what the user asks for.

## Translations

Translations live in `Resources/Localization/<language>.lproj/Localizable.strings`. The English text is the key.

1. **Improve a language:** edit its `.strings` file.
2. **Add a language:** copy `en.lproj` to `<code>.lproj`, translate the values, add the code to `CFBundleLocalizations` in `Resources/Info.plist`, and add it to `AppLanguage` in `Sources/EasyShoot/Support/Localization.swift`.
3. **Check coverage:** run
   ```bash
   python3 scripts/check-localizations.py
   ```
   It lists any missing keys or broken `%@` placeholders. CI runs the same check.

The website has its own translations in the `I18N` object at the bottom of `website/index.html`.

## Pull requests

1. Fork the repository and create a branch from `main`, for example `fix/crop-handles` or `feat/blur-tool`.
2. Keep each pull request focused on one change. Include tests for logic changes (stitching, rendering, layout).
3. Run `swift test` and `python3 scripts/check-localizations.py` before pushing.
4. For UI changes, attach before and after screenshots, in light and dark mode if the change affects colours.
5. Write clear commit messages in the imperative mood: "Add blur tool", not "Added blur tool".

CI builds the app on macOS, runs the tests, checks the translations and launches the app to make sure it starts. A maintainer reviews every pull request; expect a reply within a few days.

## Reporting security issues

Please don't open a public issue. See [SECURITY.md](SECURITY.md).
