# EasyShoot

A native macOS screenshot app inspired by CleanShot X. You can capture, annotate, frame and export screenshots. **Everything stays on your Mac**: there's no cloud, no account and no uploads.

## Features

**Capture**
- **Area / Window / Fullscreen** capture from the menu bar or global shortcuts
- **Scrolling Capture** of any scrollable content (web pages, long chats, documents, code) in any app. Scroll by hand, or press **Auto-scroll** and EasyShoot scrolls for you. Frames are stitched automatically, and sticky headers and footers are kept only once.
- **Quick Access overlay** after each capture: Copy, Save, Annotate, drag the image into any app, or dismiss
- Annotate any image file, or the image on your clipboard

**Make your point, fast** (editor)
- **Arrows, lines, rectangles, filled rectangles, ellipses, pen, highlighter, pixelate (blur)**
- **Counters** (numbered steps 1, 2, 3…)
- **Text** with bubble, outline or plain styles
- **Arabic / RTL support**: Auto mode detects Arabic or Hebrew and writes right-to-left (you can also force LTR or RTL). Includes Arabic fonts (Geeza Pro, Kufi, Naskh, Baghdad).
- **Crop** with aspect presets (1:1, 4:3, 16:9, 9:16…)
- Select, move and resize annotations; undo/redo; color palette and per-annotation styles

**Background tool**
- Gradient, solid, custom-gradient or transparent backgrounds
- Padding, corner radius, shadow, aspect ratio (Auto, 1:1, 4:3, 16:9, 9:16…) and 9-way alignment

**Presets**
- Save the background, annotation style and export settings as a **preset**
- Mark one preset as **default** and it's applied to every new screenshot, so they all match your style or brand
- Built-in starter presets are included

**Export**
- PNG, JPEG, HEIC, TIFF with a quality setting
- Resize by percent or exact width (the output size is shown live)
- Copy, Save (to your chosen folder), Save As…, or drag out

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ (or the Swift 5.9+ command-line tools)

## Build & run

```bash
./scripts/build-app.sh            # builds build/EasyShoot.app for this Mac
open build/EasyShoot.app
```

To build a universal app (Apple Silicon + Intel), run `UNIVERSAL=1 ./scripts/build-app.sh`.

Each push also builds a universal `EasyShoot.zip` on GitHub Actions (**Actions → Build → Artifacts**). It's ad-hoc signed, so after unzipping run:

```bash
xattr -dr com.apple.quarantine EasyShoot.app
```

You can also open `Package.swift` in Xcode to edit the code. Run the app through `build-app.sh` so it runs as a real `.app` bundle, which macOS needs to grant permissions.

## First launch

EasyShoot is a menu bar app with no Dock window. On first launch, a **Welcome** window walks you through Screen Recording permission and the shortcuts. You can reopen it any time by opening the app again or choosing **Welcome & Permissions…** from the menu bar icon.

If macOS says *"EasyShoot.app" Not Opened*, the build isn't notarized by Apple. Move the app to **Applications**, then either:
- go to **System Settings → Privacy & Security** and click **Open Anyway**, or
- run `xattr -dr com.apple.quarantine /Applications/EasyShoot.app`.

## Permissions

| Permission | Why |
|---|---|
| **Screen Recording** (required) | Taking screenshots. Enable EasyShoot in *System Settings → Privacy & Security → Screen & System Audio Recording*, then quit and reopen it. |
| **Accessibility** (optional) | Only for **Auto-scroll** in Scrolling Capture. |

> Builds are ad-hoc signed, so macOS may ask for Screen Recording again after you rebuild. Signing with a real identity avoids this: `SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh`.

## Shortcuts

| Action | Shortcut |
|---|---|
| Capture Area | ⌥⇧⌘4 (press Space to switch to window mode) |
| Capture Window | ⌥⇧⌘5 |
| Capture Fullscreen | ⌥⇧⌘3 |
| Scrolling Capture | ⌥⇧⌘6 |
| Annotate clipboard image | ⌥⇧⌘7 |

Editor tools: **V** select · **C** crop · **A** arrow · **L** line · **R** rectangle · **F** filled rectangle · **O** ellipse · **T** text · **N** counter · **H** highlighter · **P** pen · **B** pixelate. Hold **⇧** to constrain angles or make squares. Press **⌫** to delete, use the arrow keys to nudge, **⌘Z / ⇧⌘Z** to undo/redo, **⇧⌘C** to copy, **⌘S** to save, and **⇧⌘S** to Save As.

When writing text, press **Esc** or click outside the text box to finish, and **Return** for a new line.

## Project layout

```
Sources/EasyShoot/
  App/          entry point, menu bar, global hotkeys, capture flow
  Capture/      screencapture wrapper, permissions, region picker, scrolling capture + stitcher
  Editor/       models, renderer (shared by canvas & export), canvas, SwiftUI editor
  Export/       encoding, clipboard, saving
  QuickAccess/  post-capture floating thumbnails
  Settings/     settings window, preferences, presets
Tests/          stitcher, RTL detection, layout & render tests
```
