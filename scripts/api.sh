#!/usr/bin/env bash
# Call the SimpleOTA API and print the response body on stdout.
#
# Usage: api.sh <url> [curl args...]
#
# Why this exists rather than `curl --fail-with-body`:
# --fail-with-body writes the error body to stdout and exits non-zero. Inside
# a `RESP="$(curl ...)"` command substitution under `set -e`, the non-zero exit
# kills the step before anything reads RESP, so the body is captured and then
# thrown away. CI shows `curl: (22) The requested URL returned error: 400` and
# the server's actual explanation is lost, which is the one thing the operator
# needed. Capturing the status and the body separately lets us surface
# `detail` ourselves.
set -euo pipefail

url="$1"
shift

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

# Transport failures (DNS, refused, timeout) exit non-zero here with curl's
# own message already on stderr via -sS.
if ! code="$(curl -sS -o "$body_file" -w '%{http_code}' "$@" "$url")"; then
  echo "::error::could not reach SimpleOTA at ${url}" >&2
  exit 1
fi

body="$(cat "$body_file")"

if [ "$code" -ge 400 ]; then
  # The API's error envelope is {"detail": ...}, where detail is a string for
  # most errors and an array of objects for 422 schema failures. tostring
  # handles both without the caller having to care.
  detail=""
  if command -v jq >/dev/null 2>&1; then
    detail="$(jq -r 'if type == "object" and has("detail") then (.detail | tostring) else empty end' <<<"$body" 2>/dev/null || true)"
  fi
  echo "::error::SimpleOTA API returned HTTP ${code}: ${detail:-${body:-<empty response>}}" >&2
  exit 1
fi

printf '%s' "$body"
