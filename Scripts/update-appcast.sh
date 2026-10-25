#!/usr/bin/env bash
# Sign a release zip and upsert it into appcast.xml for Sparkle.
#
# Usage:
#   ./Scripts/update-appcast.sh [zip-path] [git-tag]
#
# Defaults:
#   zip  = newest MoveIt-*-build*.zip under dist/
#   tag  = v$MARKETING_VERSION from Config/Version.xcconfig
#
# Requires Sparkle CLI tools (sign_update) with Keychain account "moveit".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="$ROOT/Config/Version.xcconfig"
marketing="$(grep -E '^MARKETING_VERSION' "$CONFIG" | awk -F'= ' '{print $2}' | tr -d '[:space:]')"
build="$(grep -E '^CURRENT_PROJECT_VERSION' "$CONFIG" | awk -F'= ' '{print $2}' | tr -d '[:space:]')"

ZIP="${1:-}"
TAG="${2:-v${marketing}}"

if [[ -z "$ZIP" ]]; then
  ZIP="$(ls -t dist/MoveIt-*-build*.zip 2>/dev/null | head -1 || true)"
fi
if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "No zip found. Pass a path or run ./Scripts/build-release.sh first." >&2
  exit 1
fi

ZIP_BASENAME="$(basename "$ZIP")"
DOWNLOAD_URL="https://github.com/zohaibmurtaza/moveit/releases/download/${TAG}/${ZIP_BASENAME}"

find_sign_update() {
  if command -v sign_update >/dev/null 2>&1; then
    command -v sign_update
    return
  fi
  for path in \
    /tmp/sparkle-tools/bin/sign_update \
    "$ROOT/Tools/Sparkle/bin/sign_update"
  do
    if [[ -x "$path" ]]; then
      echo "$path"
      return
    fi
  done
  return 1
}

SIGN_UPDATE="$(find_sign_update)" || {
  echo "sign_update not found. Install Sparkle tools and ensure Keychain account 'moveit' exists." >&2
  exit 1
}

echo "==> Signing ${ZIP_BASENAME} (Keychain account: moveit)"
SIGNATURE="$("$SIGN_UPDATE" --account moveit -p "$ZIP" | tr -d '[:space:]')"
LENGTH="$(stat -f%z "$ZIP")"
PUBDATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
TITLE="MoveIt ${marketing}"
SHORT_VERSION="$marketing"
BUNDLE_VERSION="$build"

APPCAST="$ROOT/appcast.xml"
ITEM_FILE="$(mktemp)"
trap 'rm -f "$ITEM_FILE"' EXIT

cat >"$ITEM_FILE" <<EOF
    <item>
        <title>${TITLE}</title>
        <pubDate>${PUBDATE}</pubDate>
        <sparkle:version>${BUNDLE_VERSION}</sparkle:version>
        <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
        <enclosure
            url="${DOWNLOAD_URL}"
            length="${LENGTH}"
            type="application/octet-stream"
            sparkle:edSignature="${SIGNATURE}" />
    </item>
EOF

python3 - "$APPCAST" "$BUNDLE_VERSION" "$ITEM_FILE" <<'PY'
import re, sys
from pathlib import Path

appcast_path = Path(sys.argv[1])
version = sys.argv[2]
item = Path(sys.argv[3]).read_text(encoding="utf-8").rstrip() + "\n"

if appcast_path.exists():
    text = appcast_path.read_text(encoding="utf-8")
else:
    text = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>MoveIt</title>
    <link>https://github.com/zohaibmurtaza/moveit/releases</link>
    <description>MoveIt updates</description>
    <language>en</language>
  </channel>
</rss>
"""

# Drop any existing item with this CFBundleVersion.
text = re.sub(
    r"\s*<item>\s*.*?<sparkle:version>\s*"
    + re.escape(version)
    + r"\s*</sparkle:version>.*?</item>",
    "",
    text,
    flags=re.S,
)

m = re.search(r"(<language>.*?</language>)", text, re.S)
if not m:
    raise SystemExit("appcast.xml missing <language> element")
text = text[: m.end()] + "\n" + item + text[m.end() :]
appcast_path.write_text(text, encoding="utf-8")
print(f"Wrote {appcast_path} (sparkle:version={version})")
PY

echo
echo "Enclosure: ${DOWNLOAD_URL}"
echo "sparkle:version (CFBundleVersion): ${BUNDLE_VERSION}"
echo "Next: commit appcast.xml, tag/push, attach ${ZIP_BASENAME} to Release ${TAG}"
