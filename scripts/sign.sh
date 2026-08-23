#!/usr/bin/env bash
# Sign a firmware binary with an Ed25519 private key and print the base64
# signature on stdout.
#
# The key is written to a temp file because openssl needs a file, and it is
# removed by an EXIT trap so it does not survive a failure part-way through.
#
# Env: SIGNING_KEY (PEM), BINARY (path)
set -euo pipefail

: "${SIGNING_KEY:?signing-key is empty}"
: "${BINARY:?binary path is empty}"

if [ ! -f "$BINARY" ]; then
  echo "::error::binary not found: $BINARY" >&2
  exit 1
fi

umask 077
KEYFILE="$(mktemp "${RUNNER_TEMP:-/tmp}/simpleota-key.XXXXXX")"
trap 'rm -f "$KEYFILE"' EXIT
printf '%s\n' "$SIGNING_KEY" > "$KEYFILE"

if ! openssl pkey -in "$KEYFILE" -noout >/dev/null 2>&1; then
  echo "::error::signing-key is not a readable private key PEM. Pass the whole file including the BEGIN and END lines." >&2
  exit 1
fi

# Ed25519 signs the message itself, so there is no -digest and no separate
# hash step. Requires OpenSSL 3.x, which GitHub-hosted runners have.
openssl pkeyutl -sign -inkey "$KEYFILE" -rawin -in "$BINARY" | openssl base64 -A
