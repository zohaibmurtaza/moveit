#!/usr/bin/env bash
# Build a Release .app and zip it into dist/ for sharing.
# Ad-hoc signed by default. For public distribution, sign + notarize (see docs/RELEASING.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="$ROOT/Config/Version.xcconfig"
marketing="$(grep -E '^MARKETING_VERSION' "$CONFIG" | awk -F'= ' '{print $2}' | tr -d '[:space:]')"
build="$(grep -E '^CURRENT_PROJECT_VERSION' "$CONFIG" | awk -F'= ' '{print $2}' | tr -d '[:space:]')"

DERIVED="${ROOT}/build"
OUT_DIR="${ROOT}/dist"
APP_NAME="MoveIt"
ZIP_NAME="MoveIt-${marketing}-build${build}.zip"
ENTITLEMENTS="${ROOT}/MoveIt/MoveIt.entitlements"

mkdir -p "$OUT_DIR"

echo "==> Building Release ${marketing} (build ${build})"
xcodebuild \
  -scheme MoveIt \
  -configuration Release \
  -arch arm64 \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES

APP="$DERIVED/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
  echo "Build failed: ${APP} not found" >&2
  exit 1
fi

# Re-sign Sparkle (and helpers) + the app with the same ad-hoc identity so the
# hardened runtime accepts the embedded framework.
resign_sparkle_and_app() {
  local app="$1"
  local sparkle="$app/Contents/Frameworks/Sparkle.framework"
  local ver="$sparkle/Versions/B"
  if [[ ! -d "$sparkle" ]]; then
    echo "Sparkle.framework missing from $app" >&2
    exit 1
  fi

  echo "==> Re-signing Sparkle helpers (ad-hoc)"
  local xpc
  for xpc in "$ver/XPCServices"/*.xpc; do
    [[ -e "$xpc" ]] || continue
    codesign --force --sign - --options runtime --timestamp=none "$xpc"
  done
  if [[ -f "$ver/Autoupdate" ]]; then
    codesign --force --sign - --options runtime --timestamp=none "$ver/Autoupdate"
  fi
  if [[ -d "$ver/Updater.app" ]]; then
    codesign --force --deep --sign - --options runtime --timestamp=none "$ver/Updater.app"
  fi
  codesign --force --sign - --options runtime --timestamp=none "$ver/Sparkle"
  codesign --force --sign - --options runtime --timestamp=none "$sparkle"
  codesign --force --sign - --options runtime --timestamp=none \
    --entitlements "$ENTITLEMENTS" "$app"
}

resign_sparkle_and_app "$APP"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Packaging ${ZIP_NAME}"
rm -f "${OUT_DIR}/${ZIP_NAME}"
ditto -c -k --sequesterRsrc --keepParent "$APP" "${OUT_DIR}/${ZIP_NAME}"

echo "==> Done"
echo "App: ${APP}"
echo "Zip: ${OUT_DIR}/${ZIP_NAME}"
echo
echo "Next for auto-updates:"
echo "  ./Scripts/update-appcast.sh \"${OUT_DIR}/${ZIP_NAME}\" \"v${marketing}\""
echo "  commit appcast.xml, tag, push, gh release upload the zip"
echo
echo "On another Mac: unzip, drag MoveIt.app to Applications, then open from there."
echo "For notarized distribution see docs/RELEASING.md"
