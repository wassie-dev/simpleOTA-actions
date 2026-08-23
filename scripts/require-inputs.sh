#!/usr/bin/env bash
# Fail with one clear message listing every required input that is empty.
#
# GitHub does not enforce `required: true` for composite actions, so a value
# that was never set, or was read from the wrong store, arrives as an empty
# string and would otherwise surface much later as a confusing HTTP error.
#
# Takes ENV_NAME:input-name pairs and reads the values from the environment,
# so no secret is ever placed in argv.
set -euo pipefail

missing=""
for spec in "$@"; do
  env_name="${spec%%:*}"
  friendly="${spec#*:}"
  # Indirect expansion, not eval: eval would execute a crafted name such as
  # `VAR-$(cmd)`, and there is no reason to accept that surface here.
  value="${!env_name-}"
  if [ -z "$value" ]; then
    missing="$missing $friendly"
  fi
done

if [ -n "$(printf '%s' "$missing" | tr -d ' ')" ]; then
  echo "::error::missing required input(s):$missing" >&2
  echo "::error::If you did set them, check which store they came from. GitHub keeps Secrets and Variables separate, so \${{ vars.X }} is empty when X was saved as a secret (and vice versa). Tokens and keys belong in Secrets; ids and hostnames in Variables." >&2
  exit 1
fi
