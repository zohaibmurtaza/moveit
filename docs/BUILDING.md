# Building MoveIt

## Requirements

- Apple Silicon Mac
- macOS 13+
- Xcode 15+ (16/26/27 also fine)

## Debug (local)

Debug builds are signed with a **stable local certificate** (`MoveIt Local Signing`) so Accessibility and Screen Recording survive rebuilds. Ad-hoc signing (`-`) changes the code hash every build and forces you to toggle permissions off/on again.

```bash
# Once per machine (creates the cert in your login keychain)
./Scripts/ensure-local-signing.sh

xcodebuild -scheme MoveIt -configuration Debug -arch arm64 \
  -derivedDataPath build

open "build/Build/Products/Debug/MoveIt Dev.app"
```

Do **not** pass `CODE_SIGN_IDENTITY="-"` for Debug — that forces ad-hoc signing and breaks TCC across rebuilds.

Debug builds as **MoveIt Dev** (`com.moveit.MoveIt.dev`). Or open `MoveIt.xcodeproj` in Xcode → scheme **MoveIt** → Run.

After the first Debug build with the local cert, grant Accessibility + Screen Recording **once**. Later rebuilds should keep those grants.

## Release zip (shareable, ad-hoc)

```bash
./Scripts/build-release.sh
# → dist/MoveIt-<version>-build<n>.zip
```

Recipients: unzip, drag **MoveIt.app** into **Applications**, then open it from Applications.

Release remains ad-hoc for easy sharing; each new Release binary may need permissions granted again.

## Accessibility & Screen Recording

1. Launch MoveIt  
2. Welcome / controls → **Request Permission**  
3. Enable **MoveIt** / **MoveIt Dev** in System Settings → Privacy & Security → **Accessibility** and **Screen & System Audio Recording**

Accessibility status updates live. Screen Recording does **not**: macOS caches `CGPreflightScreenCaptureAccess()` for the process lifetime, so after you enable the toggle you must **relaunch** the app (the UI offers **Relaunch Now**).

## Project layout

See [ARCHITECTURE.md](ARCHITECTURE.md). Do not put scratch screenshots in the repo root — the welcome preview lives in `MoveIt/Resources/Assets.xcassets/WelcomeGuidePreview.imageset/`.
