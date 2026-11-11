#!/usr/bin/env bash
# Print the id of the release channel named CHANNEL.
#
# Deployments target channels by id. Looking the name up first also means a
# wrong channel name fails before anything is uploaded.
#
# Env: API_TOKEN, PROJECT_ID, BASE_URL, CHANNEL
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
resp="$("$here/api.sh" \
  "${BASE_URL%/}/api/v1/projects/${PROJECT_ID}/channels/" \
  -H "Authorization: Bearer ${API_TOKEN}")"
id="$(jq -r --arg name "$CHANNEL" '.[] | select(.name == $name) | .id' <<<"$resp")"
if [ -z "$id" ]; then
  echo "::error::channel '${CHANNEL}' not found on this project" >&2
  exit 1
fi
printf '%s\n' "$id"
