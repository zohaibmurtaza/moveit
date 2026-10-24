#!/usr/bin/env bash
# Bump marketing / build version in Config/Version.xcconfig
# Usage:
#   ./Scripts/bump-version.sh patch   # 1.0.0 -> 1.0.1 (also +1 build)
#   ./Scripts/bump-version.sh minor   # 1.0.0 -> 1.1.0
#   ./Scripts/bump-version.sh major   # 1.0.0 -> 2.0.0
#   ./Scripts/bump-version.sh build   # build number only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/Config/Version.xcconfig"
PART="${1:-patch}"

if [[ ! -f "$CONFIG" ]]; then
  echo "Missing $CONFIG" >&2
  exit 1
fi

marketing="$(grep -E '^MARKETING_VERSION' "$CONFIG" | awk -F'= ' '{print $2}' | tr -d '[:space:]')"
build="$(grep -E '^CURRENT_PROJECT_VERSION' "$CONFIG" | awk -F'= ' '{print $2}' | tr -d '[:space:]')"

IFS='.' read -r major minor patch <<<"$marketing"
major=${major:-0}; minor=${minor:-0}; patch=${patch:-0}
build=${build:-1}

case "$PART" in
  major) major=$((major + 1)); minor=0; patch=0; build=$((build + 1)) ;;
  minor) minor=$((minor + 1)); patch=0; build=$((build + 1)) ;;
  patch) patch=$((patch + 1)); build=$((build + 1)) ;;
  build) build=$((build + 1)) ;;
  *)
    echo "Usage: $0 [major|minor|patch|build]" >&2
    exit 1
    ;;
esac

new_marketing="${major}.${minor}.${patch}"

cat >"$CONFIG" <<EOF
// Single source of truth for app versioning.
// MARKETING_VERSION = user-facing semver (CFBundleShortVersionString)
// CURRENT_PROJECT_VERSION = monotonic build number (CFBundleVersion)
//
// Bump with: ./Scripts/bump-version.sh [major|minor|patch|build]

MARKETING_VERSION = ${new_marketing}
CURRENT_PROJECT_VERSION = ${build}
EOF

echo "Version -> ${new_marketing} (build ${build})"
echo "Next: update CHANGELOG.md, commit, then tag v${new_marketing}"
echo "  git tag -a v${new_marketing} -m \"MoveIt ${new_marketing}\""
