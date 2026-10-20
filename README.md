<div align="center">

<img src="Branding/AppIcon-1024.png" width="96" height="96" alt="EasyShoot app icon">

# EasyShoot

**Screenshots that explain themselves.**<br>
A free, open-source screenshot app for macOS. Capture, mark up, frame and share, all on your Mac.

[![Build](https://github.com/Haythamasalama/easyshoot/actions/workflows/build.yml/badge.svg)](https://github.com/Haythamasalama/easyshoot/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/Haythamasalama/easyshoot?color=FF5A1F&label=release)](https://github.com/Haythamasalama/easyshoot/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-0F0F12.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0F0F12?logo=apple&logoColor=white)

[Website](https://easyshoot.haythamasalama.me) · [Download](https://github.com/Haythamasalama/easyshoot/releases/latest) · [Contribute](CONTRIBUTING.md)

<img src="Branding/readme-editor.png" width="720" alt="The EasyShoot editor: a checkout screen framed on a blue gradient, with numbered steps, a blurred card number, a highlighted plan and an arrow to the Pay button.">

</div>

## Install

Paste this into Terminal:

```bash
curl -fsSL https://easyshoot.haythamasalama.me/install.sh | bash
```

That's it. EasyShoot lands in **Applications** and opens. Click **Allow** in the Welcome window so it can capture the screen.

**Updates are automatic.** EasyShoot checks once a day and updates itself in one click. You can also use **Check for Updates…** in the menu bar.

<details>
<summary>Download the zip instead</summary>

Download **EasyShoot.zip** from the [latest release](https://github.com/Haythamasalama/easyshoot/releases/latest) and move **EasyShoot.app** to **Applications**. The app isn't notarized yet, so the first time macOS blocks it: open **System Settings → Privacy & Security** and click **Open Anyway**. You only do this once.

</details>

Needs macOS 14 Sonoma or later, on Apple silicon or Intel.

## Features

- **Capture** an area, a window or the full screen, each on its own shortcut.
- **Scrolling capture** for long pages, chats and documents.
- **Annotate** with arrows, shapes, text, numbered steps, highlighter and pixelate.
- **Arabic and right-to-left** text, in any Mac font or a Google font.
- **Backgrounds** with gradients, padding, rounded corners and shadow.
- **Presets**, or start each screenshot with your last settings.
- **Export** to PNG, JPEG, HEIC or TIFF, at any size.
- **Private:** no account, no cloud, no tracking.

The app speaks English, العربية, Français, Español and Deutsch.

## Shortcuts

| Action | Shortcut |
|:--|:--|
| Capture area | <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>4</kbd> |
| Capture window | <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>5</kbd> |
| Capture fullscreen | <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>3</kbd> |
| Scrolling capture | <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>6</kbd> |

Change them in **Settings → Shortcuts**. In the editor, single letters pick a tool: <kbd>A</kbd> arrow, <kbd>T</kbd> text, <kbd>N</kbd> step.

## Build from source

```bash
git clone https://github.com/Haythamasalama/easyshoot.git
cd easyshoot
./scripts/build-app.sh
open build/EasyShoot.app
```

You need Xcode 15 or later. Run `swift test` for the tests.

## Contributing

Bug reports, translations and pull requests are all welcome. Start with the [contributing guide](CONTRIBUTING.md), and please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE) · Made by [Haytham A. Salama](https://haythamasalama.me)
