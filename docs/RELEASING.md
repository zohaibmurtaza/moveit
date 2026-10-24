# Releasing MoveIt

## Version numbers

| Field | Where | Meaning |
| --- | --- | --- |
| **Marketing version** | `Config/Version.xcconfig` → `MARKETING_VERSION` | Semver users see (`1.2.0`) |
| **Build number** | `Config/Version.xcconfig` → `CURRENT_PROJECT_VERSION` | Monotonic integer for every ship |

Bump with:

```bash
./Scripts/bump-version.sh patch   # or minor | major | build
```

Then:

1. Update [`CHANGELOG.md`](../CHANGELOG.md) under a new `## [x.y.z] - YYYY-MM-DD` section  
2. Commit  
3. Tag: `git tag -a vX.Y.Z -m "MoveIt X.Y.Z"`  
4. Push commits + tags  
5. Build: `./Scripts/build-release.sh`  
6. Attach `dist/MoveIt-X.Y.Z-buildN.zip` to the GitHub Release  

### Semver guide

- **MAJOR** — breaking behavior for users or for experiments relying on known signals  
- **MINOR** — new features (profiles, backends, UI)  
- **PATCH** — bug fixes, docs, polish  
- **build** — packaging-only rebuild without marketing change  

## Ad-hoc vs Developer ID

| Mode | Who can run it | How |
| --- | --- | --- |
| Ad-hoc (`CODE_SIGN_IDENTITY="-"`) | Same machine / tech users with right-click Open | `./Scripts/build-release.sh` |
| Developer ID + Notarized | General public | Xcode Archive → Distribute → Developer ID → Notarize |

### Notarized distribution (maintainers with Apple Developer Program)

1. Set signing team on the MoveIt target in Xcode  
2. **Product → Archive**  
3. **Distribute App → Developer ID → Upload** (notarize)  
4. Export the notarized app  
5. Zip / DMG and attach to the GitHub Release  

## Checklist

- [ ] `Version.xcconfig` bumped  
- [ ] `CHANGELOG.md` updated  
- [ ] Debug smoke: Start / Stop / debounce / permissions  
- [ ] Release zip builds  
- [ ] Git tag pushed  
- [ ] GitHub Release notes pasted from CHANGELOG  
