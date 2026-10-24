# Architecture

MoveIt is a native SwiftUI macOS app (Apple Silicon, macOS 13+) that simulates human-like input for **educational and authorized testing** use.

## High-level flow

```text
MenuBar / Window UI
        │
        ▼
  ActivityEngine  ──► IdleMonitor (real user idle debounce)
        │
        ▼
  Humanization (Bezier paths, gaps, key rhythms)
        │
        ├─► MouseSimulator ─┐
        └─► KeyboardSimulator ─┼─► VirtualHIDDevice
                               │      ├─ IOHIDUserDevice (if entitled)
                               │      └─ CGEvent fallback
                               ▼
                         macOS input stack
                               ▼
                      Observing apps / experiments under test
```

## Modules

| Path | Role |
| --- | --- |
| `MoveIt/App` | `@main` app, menu bar extra, window scene, app delegate |
| `MoveIt/UI` | Controls, welcome guide, permissions |
| `MoveIt/Engine` | Scheduler, humanization, idle debounce |
| `MoveIt/HID` | Virtual HID descriptors + CGEvent fallback |
| `MoveIt/Support` | Permissions, launch-at-login, window helpers |
| `MoveIt/Resources` | Info.plist, asset catalog (icons, welcome preview) |
| `Design/` | Icon Composer source (`.icon`) — not duplicated elsewhere |
| `Config/` | Shared `Version.xcconfig` |
| `Scripts/` | Version bump + release packaging |
| `docs/` | Architecture, detection, build/release guides |

## Runtime behavior

1. **Welcome (first launch)** — menu-bar primer + Accessibility request; then accessory (menu-bar-only) mode.
2. **Start** — arm engine; wait until real user idle ≥ debounce; simulate bursts; yield if user returns.
3. **Dock Quit / ⌘Q** — dismiss to menu bar (does not quit). **Quit** in UI — full terminate.
4. **Launch at login** — enabled by default on first run via `SMAppService`.

## Input safety (v1)

- Mouse moves + scroll; **no clicks**
- Keys: letters, digits, arrows, bare modifiers (not chorded)
- No F-keys / Escape / Page Up-Down / Home / End (avoid system shortcuts)
