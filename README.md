<div align="center">

<img src="Branding/AppIcon-1024.png" width="128" height="128" alt="EasyShoot icon">

# EasyShoot

**Capture. Mark up. Share.**
A free, open-source screenshot app for macOS. Screenshots stay on your Mac.

[![Build](https://github.com/Haythamasalama/easyshoot/actions/workflows/build.yml/badge.svg)](https://github.com/Haythamasalama/easyshoot/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-FF5A1F.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0F0F12.svg)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138.svg)

[Download](https://github.com/Haythamasalama/easyshoot/releases/latest) · [Website](website/) · [Contributing](CONTRIBUTING.md) · [Report a bug](https://github.com/Haythamasalama/easyshoot/issues/new/choose)

![EasyShoot brand sheet](Branding/brand-sheet.png)

</div>

## Features

| | |
|---|---|
| **Capture** | Area, window and fullscreen capture, from the menu bar or global shortcuts you can change. |
| **Scrolling capture** | Capture full web pages, long chats and documents in any app. Scroll by hand or let Auto-scroll do it. Sticky headers appear once. |
| **Quick Access** | A floating thumbnail after every capture: copy, save, annotate, or drag it into another app. |
| **Annotate** | Arrows, lines, rectangles, ellipses, text, numbered counters, highlighter, pen and pixelate. Every mark stays editable. |
| **Arabic & RTL** | Text in Arabic or Hebrew writes right-to-left automatically. Use any installed font, or download one from Google Fonts. |
| **Background tool** | Gradients, solid colours or transparent, with padding, rounded corners, shadow, aspect ratio and alignment. |
| **Presets** | Save your style as a preset and make it the default for every new screenshot. |
| **Export** | PNG, JPEG, HEIC or TIFF, resized by percent or exact width. Copy, save, Save As or drag out. |
| **Five languages** | English, العربية, Français, Español and Deutsch. Arabic flips the whole interface to right-to-left. |
| **Private** | No account, no cloud and no analytics. The app only goes online if you download a Google font. |

On macOS 26 the interface uses Liquid Glass. On earlier versions it falls back to standard materials.

## Install

1. Download `EasyShoot.zip` from the [latest release](https://github.com/Haythamasalama/easyshoot/releases/latest) and move **EasyShoot.app** to **Applications**.
2. The build is not notarized yet, so macOS blocks it the first time. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or run:
   ```bash
   xattr -cr /Applications/EasyShoot.app
   ```
3. Open the app and use the Welcome window to grant **Screen Recording** permission. EasyShoot lives in the menu bar, not the Dock.

**Requirements:** macOS 14 Sonoma or later, on Apple silicon or Intel.

## Default shortcuts

| Action | Shortcut |
|---|---|
| Capture area (press Space to switch to window mode) | ⌥⇧⌘4 |
| Capture window | ⌥⇧⌘5 |
| Capture fullscreen | ⌥⇧⌘3 |
| Scrolling capture | ⌥⇧⌘6 |
| Annotate clipboard image | ⌥⇧⌘7 |

You can change any of them in **Settings → Shortcuts**. In the editor, single letters switch tools (**A** arrow, **T** text, **R** rectangle, **C** crop…), **⌘+ / ⌘−** resize text, and **⇧** constrains angles and proportions.

## Build from source

```bash
git clone https://github.com/Haythamasalama/easyshoot.git
cd easyshoot
swift test                    # run the unit tests
./scripts/build-app.sh        # build build/EasyShoot.app
open build/EasyShoot.app
```

You need Xcode 15 or later (Xcode 26 enables Liquid Glass). `UNIVERSAL=1 ./scripts/build-app.sh` builds for both Apple silicon and Intel. You can also open `Package.swift` in Xcode, but run the app through `build-app.sh` so macOS can grant it permissions.

## Contributing

Contributions are welcome: bug reports, features, translations and design. Read **[CONTRIBUTING.md](CONTRIBUTING.md)** to get started, and look for issues labelled `good first issue`. By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Project layout

```
Sources/EasyShoot/
  App/          entry point, menu bar, global shortcuts, welcome window, capture flow
  Capture/      screencapture wrapper, permissions, region picker, scrolling capture + stitcher
  Editor/       models, renderer (shared by canvas and export), canvas, SwiftUI editor, fonts
  Export/       encoding, clipboard, saving
  QuickAccess/  floating thumbnails after a capture
  Settings/     settings window, preferences, presets, shortcut recorder
  Support/      brand, Liquid Glass helpers, localization
Resources/      Info.plist, app icon, translations (*.lproj)
Tests/          stitcher, RTL detection, layout and render tests
website/        the marketing site (static HTML, five languages)
Branding/       logo, icon sources and the brand guide
```

## License

[MIT](LICENSE) © 2026 [Haytham A. Salama](https://haythamasalama.me) · [GitHub](https://github.com/Haythamasalama)
