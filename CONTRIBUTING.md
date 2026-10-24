# Contributing to MoveIt

Thanks for helping improve MoveIt for **educational and authorized testing** use.

## Ground rules

- Keep project messaging aligned with education / authorized testing — not misuse.  
- If you change how activity is generated, update [`docs/DETECTION.md`](docs/DETECTION.md) when observable signals change.  
- Keep the v1 safety bar unless there is a clear, documented reason to expand it (no clicks by default).

## Setup

See [`docs/BUILDING.md`](docs/BUILDING.md).

## Workflow

1. Fork + branch from `main` (`feature/…` or `fix/…`)  
2. Make focused changes  
3. Build Debug and smoke-test Start / Stop / debounce / permissions  
4. Update docs / `CHANGELOG.md` `[Unreleased]` when behavior changes  
5. Open a PR with **why** + how you tested  

## Version bumps

Maintainers bump versions with `./Scripts/bump-version.sh` — contributors usually only edit `[Unreleased]` in the changelog.

## Code style

- Swift, SwiftUI, macOS 13+ APIs  
- Prefer small files matching the existing `App` / `UI` / `Engine` / `HID` / `Support` layout  
- No secrets, certificates, or personal screenshots in the repo  

## License

By contributing, you agree your work is licensed under the MIT License (`LICENSE`).
