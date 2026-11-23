#!/usr/bin/env bash
# Ensures a stable self-signed code-signing identity for Debug builds.
#
# Ad-hoc signatures (`CODE_SIGN_IDENTITY="-"`) change CDHash every rebuild, so macOS
# TCC treats each binary as a new app and Accessibility / Screen Recording must be
# re-granted. Signing with this fixed certificate keeps:
#   identifier "com.moveit.MoveIt.dev" and certificate root = H"<stable>"
# so grants survive rebuilds on this machine.
set -euo pipefail

CERT_NAME="MoveIt Local Signing"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P12="${ROOT}/Config/MoveItLocalSigning.p12"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
PASS=moveit
OPENSSL=/usr/bin/openssl

codesign_works() {
  local tmp
  tmp="$(mktemp -t moveit-sign)"
  echo 'int main(){return 0;}' >"${tmp}.c"
  if ! clang -o "$tmp" "${tmp}.c" 2>/dev/null; then
    rm -f "${tmp}.c" "$tmp"
    return 1
  fi
  if codesign -s "$CERT_NAME" -f "$tmp" >/dev/null 2>&1; then
    rm -f "${tmp}.c" "$tmp"
    return 0
  fi
  rm -f "${tmp}.c" "$tmp"
  return 1
}

import_p12() {
  security import "$P12" \
    -k "$KEYCHAIN" \
    -P "$PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -T /usr/bin/productbuild >/dev/null 2>&1 || true
}

if codesign_works; then
  echo "Using existing identity: ${CERT_NAME}"
  codesign -d -r- "$(mktemp -t moveit-probe)" 2>/dev/null || true
  # Show DR from a quick sign for confirmation
  probe="$(mktemp -t moveit-probe)"
  echo 'int main(){return 0;}' >"${probe}.c"
  clang -o "$probe" "${probe}.c" >/dev/null 2>&1
  codesign -s "$CERT_NAME" -f "$probe" >/dev/null 2>&1
  echo -n "Designated requirement sample: "
  codesign -d -r- "$probe" 2>&1 | sed -n 's/^designated => //p'
  rm -f "$probe" "${probe}.c"
  exit 0
fi

if [[ -f "$P12" ]]; then
  echo "Importing ${P12} into login keychain…"
  import_p12
  if codesign_works; then
    echo "Imported identity: ${CERT_NAME}"
    exit 0
  fi
  echo "Existing p12 did not produce a usable identity; recreating…"
fi

echo "Creating ${CERT_NAME} (system LibreSSL)…"
TMPDIR_CERT="$(mktemp -d /tmp/moveit-signing.XXXXXX)"
cleanup() { rm -rf "$TMPDIR_CERT"; }
trap cleanup EXIT

cat >"${TMPDIR_CERT}/cert.cnf" <<'EOF'
[ req ]
distinguished_name = req_dn
x509_extensions = v3_codesign
prompt = no
[ req_dn ]
CN = MoveIt Local Signing
O = MoveIt
C = US
[ v3_codesign ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 \
  -keyout "${TMPDIR_CERT}/key.pem" \
  -out "${TMPDIR_CERT}/cert.pem" \
  -days 3650 -nodes \
  -config "${TMPDIR_CERT}/cert.cnf" \
  -extensions v3_codesign >/dev/null 2>&1

"$OPENSSL" pkcs12 -export \
  -out "${TMPDIR_CERT}/cert.p12" \
  -inkey "${TMPDIR_CERT}/key.pem" \
  -in "${TMPDIR_CERT}/cert.pem" \
  -passout pass:"$PASS" \
  -name "$CERT_NAME" >/dev/null 2>&1

mkdir -p "${ROOT}/Config"
cp "${TMPDIR_CERT}/cert.p12" "$P12"
import_p12

if ! codesign_works; then
  echo "error: could not create a usable '${CERT_NAME}' identity" >&2
  echo "Try importing Config/MoveItLocalSigning.p12 manually in Keychain Access." >&2
  exit 1
fi

echo "Installed identity: ${CERT_NAME}"
echo "Saved ${P12} so rebuilds keep the same certificate."
echo "Grant Accessibility + Screen Recording once for MoveIt Dev; later Debug rebuilds should keep them."
