# MoveIt

Native **Apple Silicon** macOS menu-bar app that generates **human-like mouse and keyboard activity**.

> **Educational / testing use only.** Run it on machines you own or are authorized to use for learning, demos, or controlled experiments. Do not use it to misrepresent activity to others.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20arm64-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Version](https://img.shields.io/badge/version-1.1.1-informational)

## What it does

MoveIt simulates idle-aware, human-like input (mouse paths, scrolls, and safe key taps) so you can study how systems behave when a Mac looks “active” without real work happening. It is more varied than fixed-interval mouse jigglers: idle debounce, Bezier motion, mixed mouse/keys, optional restricted app switching, and an optional virtual HID path.

## Features

- Menu-bar app with first-run welcome + Accessibility request  
- Idle debounce before activity (configurable)  
- Profiles: Subtle / Office / Intensive + **intensity range** (resampled every 10 minutes)  
- Humanized mouse paths (edge-aware), scroll, silent modifiers by default; characters opt-in with focus safety  
- Restricted app/window switching among targets you select (no global ⌘Tab)  
- Live activity stream (past → now → next) in the Status tab  
- Settings-style window with native sidebar; Liquid Glass on macOS 26+  
- Virtual HID when entitled; otherwise CGEvent fallback  
- Launch at login (on by default); many menu-bar icon choices  
- Dock Quit returns to menu bar; in-app **Quit** exits fully  
- Debug builds as **MoveIt Dev** (separate bundle id from Release)  
- Automatic updates from GitHub Releases (Sparkle; Release builds)  

## Quick start

```bash
git clone https://github.com/zohaibmurtaza/moveit.git
cd moveit
./Scripts/build-release.sh
open build/Build/Products/Release/MoveIt.app
```

Or open `MoveIt.xcodeproj` in Xcode and Run.

Full build notes: [`docs/BUILDING.md`](docs/BUILDING.md)

## Repository layout

```text
moveit/
├── Config/Version.xcconfig     # single source of truth for versions
├── Design/moveit-icon.icon     # Icon Composer source
├── MoveIt/                     # app sources + Resources
├── MoveIt.xcodeproj/
├── Scripts/                    # bump-version, build-release
├── docs/                       # architecture, notes, releasing
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── SECURITY.md
└── README.md
```

Scratch screenshots do **not** belong in the repo root. The welcome UI preview is stored in `MoveIt/Resources/Assets.xcassets/WelcomeGuidePreview.imageset/`.

## Versioning

| | |
| --- | --- |
| Marketing (semver) | `Config/Version.xcconfig` → `MARKETING_VERSION` |
| Build number | `Config/Version.xcconfig` → `CURRENT_PROJECT_VERSION` |

```bash
./Scripts/bump-version.sh patch   # also see minor | major | build
```

Release process: [`docs/RELEASING.md`](docs/RELEASING.md) · History: [`CHANGELOG.md`](CHANGELOG.md)

## Docs

| Doc | Purpose |
| --- | --- |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | How the app is structured |
| [`docs/DETECTION.md`](docs/DETECTION.md) | Observable signals (for education / research) |
| [`docs/BUILDING.md`](docs/BUILDING.md) | Build & run |
| [`docs/RELEASING.md`](docs/RELEASING.md) | Tags, zips, notarization |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to contribute |
| [`SECURITY.md`](SECURITY.md) | Responsible use & reports |

## Responsible use

MoveIt is published for **education and authorized testing**. Using it to falsify work activity or circumvent monitoring without permission is outside the intended use of this project.

## License

[MIT](LICENSE)
