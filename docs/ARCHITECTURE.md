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
| `MoveIt/UI` | Controls (`NavigationSplitView`), activity stream, app-switch picker, welcome, permissions |
| `MoveIt/Engine` | Scheduler, humanization, idle debounce, activity event stream, intensity periods |
| `MoveIt/HID` | Virtual HID descriptors + CGEvent fallback |
| `MoveIt/Support` | Permissions, launch-at-login, app switching, focus safety, build identity, native glass helpers |
| `MoveIt/Resources` | Info.plist, asset catalog (icons, welcome preview) |
| `Design/` | Icon Composer source (`.icon`) — not duplicated elsewhere |
| `Config/` | Shared `Version.xcconfig` |
| `Scripts/` | Version bump + release packaging |
| `docs/` | Architecture, detection, build/release guides |

## Runtime behavior

1. **Welcome (first launch)** — menu-bar primer + Accessibility request; then accessory (menu-bar-only) mode.
2. **Start** — arm engine; wait until real user idle ≥ debounce; simulate bursts; yield if user returns.
3. **Bursts** — mouse / scroll / silent or character keys / optional restricted app or window switch from the allow list.
4. **Intensity** — user sets a Quietest–Busiest range; engine picks an effective level every ~10 minutes.
5. **Dock Quit / ⌘Q** — dismiss to menu bar (does not quit). **Quit** in UI — full terminate.
6. **Launch at login** — enabled by default on first run via `SMAppService`.
7. **Debug vs Release** — Debug ships as “MoveIt Dev” with a distinct bundle id so Accessibility grants don’t collide with Release.

## Input safety

- Mouse moves + scroll; **no clicks**
- Silent modifiers by default; letters/digits/arrows only when opted in, and skipped while editing text / terminal focus
- App switching only among user-selected apps/windows (never global ⌘Tab)
- No F-keys / Escape / Page Up-Down / Home / End (avoid system shortcuts)
