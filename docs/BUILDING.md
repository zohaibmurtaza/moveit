# Building MoveIt

## Requirements

- Apple Silicon Mac
- macOS 13+
- Xcode 15+ (16/26/27 also fine)

## Debug (local)

```bash
xcodebuild -scheme MoveIt -configuration Debug -arch arm64 \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES

open "build/Build/Products/Debug/MoveIt.app"
```

Or open `MoveIt.xcodeproj` in Xcode → scheme **MoveIt** → Run.

## Release zip (shareable, ad-hoc)

```bash
./Scripts/build-release.sh
# → dist/MoveIt-<version>-build<n>.zip
```

Recipients: unzip, drag **MoveIt.app** into **Applications**, then open it from Applications.

## Accessibility

1. Launch MoveIt  
2. Welcome / controls → **Request Permission**  
3. Enable **MoveIt** in System Settings → Privacy & Security → Accessibility  

Status updates automatically once granted.

## Project layout

See [ARCHITECTURE.md](ARCHITECTURE.md). Do not put scratch screenshots in the repo root — the welcome preview lives in `MoveIt/Resources/Assets.xcassets/WelcomeGuidePreview.imageset/`.
