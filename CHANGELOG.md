# Changelog

All notable changes to MoveIt are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Marketing version and build number live in [`Config/Version.xcconfig`](Config/Version.xcconfig).

## [Unreleased]

### Planned
- Optional signed/notarized release workflow notes for maintainers

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
