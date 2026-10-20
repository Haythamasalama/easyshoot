# EasyShoot

Native macOS screenshot app: Swift Package Manager, SwiftUI + AppKit, macOS 14+, no third-party dependencies. See CONTRIBUTING.md for setup and conventions.

## Before changing UI

- Load `.claude/skills/swiftui-expert` and `.claude/skills/macos-development` for SwiftUI/AppKit work.
- Every window must work at its minimum size (the editor is 860 × 520) and at full screen. Never let a child decide a panel's width: give side panels a fixed width (`EditorView.inspectorWidth`) and make their content flexible (`FittingSegments`, `maxWidth: .infinity`, text that wraps or scales). Don't use `containerRelativeFrame` inside the inspector; in an `NSHostingView` it can resolve to the whole window.
- Use `ViewThatFits` with a compact variant for bars that can outgrow narrow windows (toolbar, text bar).
- Don't use SwiftUI `ColorPicker` in tight rows; it draws a wide capsule on macOS 26. Use `ColorWellButton`.
- Every user-visible string goes through `L("…")` with translations in all five `.lproj` files. Run `python3 scripts/check-localizations.py`.

## Checks

- `swift test` and `./scripts/build-app.sh` (macOS only; CI runs both).
- PR titles follow Conventional Commits (see CONTRIBUTING.md).
