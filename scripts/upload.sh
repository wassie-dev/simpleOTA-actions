#!/usr/bin/env bash
# Upload BINARY with its manifest, without deploying it. Prints the created
# artifact's JSON on stdout.
#
# Env: API_TOKEN, PROJECT_ID, BASE_URL, BINARY, and what manifest.sh reads.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$BINARY" ] || { echo "::error::binary not found: $BINARY" >&2; exit 1; }
manifest="$("$here/manifest.sh")"

"$here/api.sh" \
  "${BASE_URL%/}/api/v1/projects/${PROJECT_ID}/artifacts/" \
  -X POST \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -F "manifest=${manifest}" \
  -F "binary=@${BINARY}"
