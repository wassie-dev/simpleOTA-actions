#!/usr/bin/env bash
# Decide the security mode and validate the signing inputs agree with it.
# Prints the resolved mode on stdout.
#
# "auto" means: signed when a signing key is supplied, basic otherwise. That
# keeps the common cases zero-config while still allowing an explicit choice.
set -euo pipefail

MODE="${SECURITY_MODE:-auto}"
if [ "$MODE" = "auto" ]; then
  if [ -n "${SIGNING_KEY:-}" ]; then MODE="signed"; else MODE="basic"; fi
fi

case "$MODE" in
  basic|token|signed) ;;
  *) echo "::error::security-mode must be one of auto, basic, token, signed (got '$MODE')" >&2; exit 1 ;;
esac

if [ "$MODE" = "signed" ]; then
  [ -n "${SIGNING_KEY:-}" ] || { echo "::error::security-mode is 'signed' but signing-key is empty" >&2; exit 1; }
  [ -n "${KEY_ID:-}" ]      || { echo "::error::security-mode is 'signed' but key-id is empty. It must match a signing key id on the project." >&2; exit 1; }
elif [ -n "${SIGNING_KEY:-}" ]; then
  echo "::warning::a signing-key was supplied but security-mode resolved to '$MODE', so the build will be uploaded unsigned."
fi

echo "$MODE"
