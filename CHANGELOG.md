# Changelog

All notable changes to MoveIt are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Marketing version and build number live in [`Config/Version.xcconfig`](Config/Version.xcconfig).

## [Unreleased]

### Planned
- Optional signed/notarized release workflow notes for maintainers

## [1.1.1] - 2026-10-26

### Added
- **Automatic updates via Sparkle** — checks the GitHub Releases appcast daily and installs updates in the background
- **Check for Updates…** in the menu bar panel and Appearance → Updates (Release builds only)
- `Scripts/update-appcast.sh` to sign zips and refresh `appcast.xml`

### Changed
- Release docs describe the Sparkle + GitHub Releases publish flow
- Install guidance: unzip, drag **MoveIt.app** to **Applications**, then open from there

### Fixed
- Ad-hoc Release builds with Sparkle open correctly under the hardened runtime (library-validation entitlement + re-sign Sparkle in `build-release.sh`)

## [1.1.0] - 2026-10-26

### Added
- **Restricted app & window switching** — activate only user-selected apps/windows (no global ⌘Tab); optional browser ⌃Tab when an allow-listed browser is frontmost
- **App/window picker** — choose targets and optional window titles in the Switching tab
- **Configurable switch intervals** — random wait between min/max after each switch
- **Live activity stream** — Status tab past → now → next conveyor with mouse / keyboard / scroll / switch icons and right-to-left transitions
- **Intensity range** — Quietest/Busiest bounds; effective level resampled every 10 minutes so captures don’t stay flat
- **Focus safety** — skip character keys while a text field, editor, or terminal is focused
- **Silent keyboard by default** — modifiers on; character/number keys opt-in
- **Dev vs Release identity** — Debug builds as “MoveIt Dev” (`com.moveit.MoveIt.dev`) alongside Release `MoveIt`
- **Native Settings-style window** — `NavigationSplitView` sidebar (Simulation / App groups)
- **Native Liquid Glass surfaces** — system `glassEffect` / glass buttons on macOS 26+ (no custom vibrancy layer)
- **Expanded menu-bar icon set** — many more SF Symbol choices in Appearance
- Edge-aware mouse paths that stay inside the visible display inset

### Changed
- Controls window reorganized into Activity / Keyboard / Switching / Appearance / Status
- Activity settings grouped into clear cards (Idle wait, Activity style, How busy, Startup)
- Menu bar panel spacing with dividers between control groups
- Idle wait placed above activity style for a clearer setup flow
- Phase status shown as plain text in the footer (avoids toolbar double-glass chips)
- Humanization burst length scales with effective intensity

### Fixed
- App/window activate reported success without bringing the target forward — activation now uses AX frontmost + `activateIgnoringOtherApps` on the main thread
- Activity stream layout no longer grows/jitters as history increases (fixed-slot conveyor)
- Traffic lights overlapping sidebar rows and duplicated navigation titles from stacked headers
- Stop / Start control styling and menu-bar icon fade behavior polish from the 1.0.x iteration

## [1.0.0] - 2026-10-24

### Added
- Native Apple Silicon menu-bar app with humanized mouse / keyboard activity
- Idle debounce (default 20s) before simulation resumes
- Profiles: Subtle / Office / Intensive + intensity control
- Virtual HID path with CGEvent fallback
- Welcome guide with Accessibility request flow
- Launch at login (enabled by default on first run)
- Icon Composer app icon + menu-bar template glyph
- Notes on observable signals (`docs/DETECTION.md`)

### Security / ethics
- Documented educational / authorized-testing-only use
- Safe key set (letters, numbers, arrows, modifiers — no F-keys / Esc / Page keys)
- No mouse clicks in v1
