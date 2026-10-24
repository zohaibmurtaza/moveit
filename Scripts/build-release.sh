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

echo "==> Packaging ${ZIP_NAME}"
rm -f "${OUT_DIR}/${ZIP_NAME}"
ditto -c -k --sequesterRsrc --keepParent "$APP" "${OUT_DIR}/${ZIP_NAME}"

echo "==> Done"
echo "App: ${APP}"
echo "Zip: ${OUT_DIR}/${ZIP_NAME}"
echo
echo "On another Mac: unzip, then right-click → Open (Gatekeeper)."
echo "For notarized distribution see docs/RELEASING.md"
