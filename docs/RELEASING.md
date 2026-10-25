# Releasing MoveIt

## Version numbers

| Field | Where | Meaning |
| --- | --- | --- |
| **Marketing version** | `Config/Version.xcconfig` → `MARKETING_VERSION` | Semver users see (`1.2.0`) |
| **Build number** | `Config/Version.xcconfig` → `CURRENT_PROJECT_VERSION` | Monotonic integer for every ship (**Sparkle compares this**) |

Bump with:

```bash
./Scripts/bump-version.sh patch   # or minor | major | build
```

## Release steps (with Sparkle auto-update)

1. Update [`CHANGELOG.md`](../CHANGELOG.md) under a new `## [x.y.z] - YYYY-MM-DD` section  
2. Bump `Config/Version.xcconfig`  
3. Commit  
4. Build: `./Scripts/build-release.sh`  
5. Sign + appcast: `./Scripts/update-appcast.sh dist/MoveIt-x.y.z-buildN.zip vX.Y.Z`  
6. Commit `appcast.xml` (Sparkle clients read `https://raw.githubusercontent.com/zohaibmurtaza/moveit/main/appcast.xml`)  
7. Tag: `git tag -a vX.Y.Z -m "MoveIt X.Y.Z"`  
8. Push commits + tags  
9. Create GitHub Release and attach **the same zip filename** referenced in the appcast enclosure URL  

### Sparkle notes

- Feed URL / public key live in `MoveIt/Resources/Info.plist` (`SUFeedURL`, `SUPublicEDKey`)  
- Private EdDSA key is in the maintainer **Keychain** under account **`moveit`** (created with Sparkle’s `generate_keys --account moveit`)  
- Do **not** commit private keys  
- **MoveIt Dev** (Debug) does not check for updates — only Release `com.moveit.MoveIt`  
- Sparkle installs updates automatically when `SUAutomaticallyUpdate` is true; users can also use **Check for Updates…**  

### Semver guide

- **MAJOR** — breaking behavior for users or for experiments relying on known signals  
- **MINOR** — new features (profiles, backends, UI)  
- **PATCH** — bug fixes, docs, polish  
- **build** — packaging-only rebuild without marketing change  

## Ad-hoc vs Developer ID

| Mode | Who can run it | How |
| --- | --- | --- |
| Ad-hoc (`CODE_SIGN_IDENTITY="-"`) | Same machine / tech users: drag to Applications, then open | `./Scripts/build-release.sh` |
| Developer ID + Notarized | General public | Xcode Archive → Distribute → Developer ID → Notarize |

Sparkle verifies **EdDSA** signatures on the zip regardless. Developer ID + notarization still improves Gatekeeper trust for first install.

`build-release.sh` re-signs Sparkle’s nested helpers with the same ad-hoc identity as the app. The app also uses `com.apple.security.cs.disable-library-validation` so the hardened runtime accepts the embedded Sparkle binary under ad-hoc signing. When you move to a real Developer ID team, re-sign Sparkle with that team and consider dropping the entitlement.

### Notarized distribution (maintainers with Apple Developer Program)

1. Set signing team on the MoveIt target in Xcode  
2. **Product → Archive**  
3. **Distribute App → Developer ID → Upload** (notarize)  
4. Export the notarized app  
5. Zip / DMG, run `update-appcast.sh`, attach to the GitHub Release  

## Checklist

- [ ] `Version.xcconfig` bumped (build number must increase)  
- [ ] `CHANGELOG.md` updated  
- [ ] Debug smoke: Start / Stop / debounce / permissions  
- [ ] Release zip builds  
- [ ] `appcast.xml` updated and committed  
- [ ] Git tag pushed  
- [ ] GitHub Release asset name matches appcast enclosure URL  
- [ ] GitHub Release notes pasted from CHANGELOG  
