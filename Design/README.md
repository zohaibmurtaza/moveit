# Design

- `moveit-icon.icon` — Apple **Icon Composer** source for the app icon (Liquid Glass / generated `.icns` at build time).
- Edit in Xcode: open the `.icon` file → **Open with Icon Composer**.

Raster assets used at runtime (menu bar template, welcome mark, welcome screenshot) live under `MoveIt/Resources/Assets.xcassets/` — do not duplicate large PNGs at the repo root.
