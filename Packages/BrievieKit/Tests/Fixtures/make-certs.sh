#!/bin/sh
# Generates the test certificates used by BrievieCoreTests.
#
#   ca.pem          private CA (stands in for the server's Caddy CA)
#   leaf-a.pem      leaf for "localhost", signed by ca
#   leaf-b.pem      second leaf for "localhost", signed by ca (a renewed certificate)
#   other-ca.pem    an unrelated CA
#   other-leaf.pem  leaf for "localhost", signed by other-ca
#   ca.sha256       SHA-256 of ca.pem in DER form, lower-case hex
#   issued-at       UTC time the certificates were made; the tests evaluate trust at this moment
#                   plus one day, so they do not expire
#
# The CAs are valid for 20 years. Leaves are valid for 800 days: Apple refuses TLS server
# certificates valid for longer than 825 days ("exceeds maximum temporal validity period"),
# even under a private anchor. Private keys are thrown away.
# Usage: ./make-certs.sh (writes next to this script)
set -eu

OUT=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
CA_DAYS=7300
LEAF_DAYS=800

cat > "$WORK/ca.ext" <<'EOF'
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF

cat > "$WORK/leaf.ext" <<'EOF'
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
EOF

# make_ca <name> <common name>
make_ca() {
    openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/$1.key"
    openssl req -new -key "$WORK/$1.key" -subj "/CN=$2" -out "$WORK/$1.csr"
    openssl x509 -req -in "$WORK/$1.csr" -signkey "$WORK/$1.key" -days "$CA_DAYS" \
        -sha256 -extfile "$WORK/ca.ext" -out "$OUT/$1.pem"
}

# make_leaf <name> <issuer name>
make_leaf() {
    openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/$1.key"
    openssl req -new -key "$WORK/$1.key" -subj "/CN=localhost" -out "$WORK/$1.csr"
    openssl x509 -req -in "$WORK/$1.csr" -CA "$OUT/$2.pem" -CAkey "$WORK/$2.key" \
        -CAcreateserial -CAserial "$WORK/$2.srl" -days "$LEAF_DAYS" -sha256 \
        -extfile "$WORK/leaf.ext" -out "$OUT/$1.pem"
}

date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/issued-at"
make_ca ca "Brievie Test CA"
make_leaf leaf-a ca
make_leaf leaf-b ca
make_ca other-ca "Other Test CA"
make_leaf other-leaf other-ca

openssl x509 -in "$OUT/ca.pem" -outform der | shasum -a 256 | cut -d ' ' -f 1 > "$OUT/ca.sha256"
