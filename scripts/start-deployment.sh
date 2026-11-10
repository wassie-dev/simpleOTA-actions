#!/usr/bin/env bash
# Create a deployment of ARTIFACT_ID to one channel and start it. Prints the
# started deployment's JSON on stdout.
#
# Env: API_TOKEN, PROJECT_ID, BASE_URL, ARTIFACT_ID, CHANNEL_ID, ROLLOUT
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base="${BASE_URL%/}/api/v1/projects/${PROJECT_ID}/deployments/"

body="$(jq -nc \
  --arg artifact_id "$ARTIFACT_ID" \
  --arg channel_id "$CHANNEL_ID" \
  --argjson pct "$ROLLOUT" \
  '{artifact_id: $artifact_id, rollout_strategy: "immediate", rollout_percentage: $pct,
    target_channel_ids: [$channel_id], target_group_ids: [],
    notes: "Created by the SimpleOTA release action."}')"

resp="$("$here/api.sh" "$base" -X POST \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "$body")"
dep="$(jq -r '.id' <<<"$resp")"

"$here/api.sh" "${base}${dep}/transition/" -X POST \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"action":"start"}'
