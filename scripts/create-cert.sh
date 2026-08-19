#!/bin/bash
# Creates a self-signed code signing certificate named "Ledge Dev" in the login keychain.
# Run once per machine. Idempotent — does nothing if the cert already exists.

set -e

CERT_NAME="Ledge Dev"

# Check if cert already exists
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "Certificate '$CERT_NAME' already exists."
    exit 0
fi

echo "Creating self-signed code signing certificate '$CERT_NAME'..."

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Generate OpenSSL config for a code signing certificate
cat > "$TMPDIR/cert.conf" << EOF
[req]
distinguished_name = req_dn
x509_extensions = codesign
prompt = no

[req_dn]
CN = $CERT_NAME

[codesign]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# Generate key + self-signed certificate (valid 10 years)
openssl req -x509 -newkey rsa:2048 \
    -keyout "$TMPDIR/key.pem" \
    -out "$TMPDIR/cert.pem" \
    -days 3650 -nodes \
    -config "$TMPDIR/cert.conf" 2>/dev/null

# Package as PKCS12 for keychain import
# -legacy is required on newer OpenSSL/LibreSSL (macOS 14+) because the default
# encryption algorithm changed and security import doesn't understand the new one.
# Try with -legacy first; fall back without it for older OpenSSL that doesn't know the flag.
openssl pkcs12 -export \
    -out "$TMPDIR/cert.p12" \
    -inkey "$TMPDIR/key.pem" \
    -in "$TMPDIR/cert.pem" \
    -passout pass:ledgedev \
    -legacy 2>/dev/null || \
openssl pkcs12 -export \
    -out "$TMPDIR/cert.p12" \
    -inkey "$TMPDIR/key.pem" \
    -in "$TMPDIR/cert.pem" \
    -passout pass:ledgedev 2>/dev/null

# Import into login keychain, allowing codesign to use it
security import "$TMPDIR/cert.p12" \
    -k ~/Library/Keychains/login.keychain-db \
    -P ledgedev \
    -T /usr/bin/codesign

# On macOS 12+ the partition list (ACL) must be set explicitly for codesign access
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "" ~/Library/Keychains/login.keychain-db 2>/dev/null || true

echo ""
echo "Done! Verify with:"
echo "  security find-identity -v -p codesigning"
echo ""
echo "You should see a line containing '$CERT_NAME'."
echo "Now run: make reinstall"
