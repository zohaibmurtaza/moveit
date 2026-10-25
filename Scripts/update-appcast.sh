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
# Requires Sparkle CLI tools (generate_keys / sign_update) with Keychain account "moveit".
# Download tools: https://github.com/sparkle-project/Sparkle/releases
#
# After running: commit appcast.xml, then ensure the GitHub Release asset name matches the zip.
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
  for candidate in \
    /tmp/sparkle-tools/bin/sign_update \
    "$HOME/Downloads/Sparkle*/bin/sign_update" \
    "$ROOT/Tools/Sparkle/bin/sign_update"
  do
    # shellcheck disable=SC2086
    for path in $candidate; do
      if [[ -x "$path" ]]; then
        echo "$path"
        return
      fi
    done
  done
  return 1
}

SIGN_UPDATE="$(find_sign_update)" || {
  echo "sign_update not found. Install Sparkle tools and ensure Keychain account 'moveit' exists:" >&2
  echo "  curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.8.0/Sparkle-2.8.0.tar.xz | tar x -C /tmp/sparkle-tools" >&2
  echo "  /tmp/sparkle-tools/bin/generate_keys --account moveit" >&2
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
TMP="$(mktemp)"

ITEM=$(cat <<EOF
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
)

if [[ ! -f "$APPCAST" ]]; then
  cat >"$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>MoveIt</title>
    <link>https://github.com/zohaibmurtaza/moveit/releases</link>
    <description>MoveIt updates</description>
    <language>en</language>
${ITEM}
  </channel>
</rss>
EOF
  echo "==> Created ${APPCAST}"
else
  # Drop any existing item with the same sparkle:version, then insert new item after <language>.
  python3 - "$APPCAST" "$BUNDLE_VERSION" "$ITEM" <<'PY'
import re, sys
path, version, item = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
# Remove item blocks that declare this bundle version.
pattern = re.compile(
    r"\s*<item>.*?sparkle:version>\s*" + re.escape(version) + r"\s*</sparkle:version>.*?</item>",
    re.S,
)
text = pattern.sub("", text)
# Insert after <language>...</language>
m = re.search(r"(<language>.*?</language>)", text, re.S)
if not m:
    raise SystemExit("appcast.xml missing <language> element")
insert_at = m.end()
text = text[:insert_at] + "\n" + item + text[insert_at:]
open(path, "w", encoding="utf-8").write(text)
PY
  echo "==> Updated ${APPCAST}"
fi

echo
echo "Enclosure: ${DOWNLOAD_URL}"
echo "sparkle:version (CFBundleVersion): ${BUNDLE_VERSION}"
echo "Next:"
echo "  1. Commit appcast.xml"
echo "  2. Attach ${ZIP_BASENAME} to GitHub Release ${TAG}"
echo "  3. Push main so SUFeedURL picks up the new appcast"
