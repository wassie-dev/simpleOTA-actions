#!/usr/bin/env bash
# Run the root action's "Upload and deploy" step and the upload action's
# "Upload artifact" step against a stub SimpleOTA API and a stub CLI, and
# check what they sent and what they reported.
#
# Guards two things: a signed build still goes out as one request (/release/
# or /artifacts/), and a failure to make it strict-ready (CLI missing, CLI too
# old, CLI error) leaves the step green with a warning instead of failing it.
#
# Usage: tests/release-step.sh   (from the repository root; needs python3
# with PyYAML, and jq)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT

# The actions as the runner would see them, with api.sh swapped for a stub.
mkdir -p "$t/action/upload" "$t/bin" "$t/nocli"
cp -r "$root/scripts" "$t/action/scripts"
cat > "$t/action/scripts/api.sh" <<'STUB'
#!/usr/bin/env bash
# Records each request as one JSON line, with whether the signing key was in
# its environment, and answers /release/ and /artifacts/ with canned JSON.
url="$1"; shift
printf '%s\0' "$@" | jq -Rsc --arg url "$url" \
  '{url: $url, args: (split("\u0000")[:-1]), key_in_env: ($ENV | has("SIGNING_KEY"))}' >> "$API_LOG"
[ "${API_FAIL:-}" = 1 ] && { echo "::error::SimpleOTA API returned HTTP 400: nope" >&2; exit 1; }
case "$url" in
  */api/v1/projects/proj-1/release/)
    printf '{"build_number": 57, "artifact_id": "art-1", "deployment_id": "dep-1"}' ;;
  */api/v1/projects/proj-1/artifacts/)
    printf '{"id": "art-2", "build_number": 57}' ;;
  *) echo "::error::unexpected request to $url" >&2; exit 1 ;;
esac
STUB
cat > "$t/bin/simpleota" <<'STUB'
#!/usr/bin/env bash
if [ "$1 $2" = "build --help" ]; then
  [ "${CLI_MODE:-}" = old ] || echo "  make-strict"
  exit 0
fi
[ "$1" = --version ] && { echo "simpleota 0.0.1"; exit 0; }
printf '%s\0' "$@" | jq -Rsc --arg token "$SIMPLEOTA_TOKEN" --arg project "$SIMPLEOTA_PROJECT" \
  --arg url "$SIMPLEOTA_API_URL" --arg key "$SIMPLEOTA_SIGNING_KEY" \
  '{argv: (split("\u0000")[:-1]), token: $token, project: $project, url: $url, key: $key}' \
  >> "$CLI_LOG"
[ "${CLI_MODE:-}" = fail ] && exit 1
exit 0
STUB
# A runner where the CLI cannot be downloaded: the real installer, with a curl
# that cannot connect.
printf '#!/usr/bin/env bash\necho "curl: (28) Connection timed out" >&2\nexit 28\n' \
  > "$t/nocli/curl"
chmod +x "$t/action/scripts/api.sh" "$t/bin/simpleota" "$t/nocli/curl"

# extract_step <action.yml> <step id> <action path>: prints the step's script.
extract_step() {
  python3 -c '
import sys, yaml
action, step_id, path = sys.argv[1:]
steps = yaml.safe_load(open(action))["runs"]["steps"]
run = next(s["run"] for s in steps if s.get("id") == step_id)
print(run.replace("${{ github.action_path }}", path))
' "$@"
}
extract_step "$root/action.yml" release "$t/action" > "$t/release.sh"
extract_step "$root/upload/action.yml" upload "$t/action/upload" > "$t/upload.sh"

printf '\xe9fake firmware' > "$t/fw.bin"
base_path="/usr/local/bin:/usr/bin:/bin"

# run_step <mode> [VAR=value...]: runs the step in $step, leaves its exit
# status in $status and its output in $t/out.
run_step() {
  local mode="$1"; shift
  : > "$t/api.log"; : > "$t/cli.log"; : > "$t/github_output"; : > "$t/summary"
  set +e
  env -i HOME="$t" PATH="$t/bin:$base_path" \
    API_LOG="$t/api.log" CLI_LOG="$t/cli.log" RUNNER_TEMP="$t" \
    GITHUB_OUTPUT="$t/github_output" GITHUB_STEP_SUMMARY="$t/summary" \
    FRAMEWORK=arduino VERSION_LABEL=1.2.3 CHIP_FAMILY=esp32 BOARD_ID= \
    PARTITION_PROFILE= HARDWARE_REVISION_MIN= HARDWARE_REVISION_MAX= RELEASE_NOTES= \
    SECURITY_MODE="$mode" KEY_ID=k1 SIGNATURE_B64=c2ln \
    API_TOKEN=tok-1 PROJECT_ID=proj-1 BINARY="$t/fw.bin" BASE_URL=https://example.test/ \
    ROLLOUT=050 CHANNEL="beta testers" SIGNING_KEY=key-pem CLI_VERSION= \
    "$@" bash --noprofile --norc -eo pipefail "$step" > "$t/out" 2>&1
  status=$?
  set -e
}

fail() { echo "FAIL: $*"; echo "--- step output"; cat "$t/out"; exit 1; }

# Each step makes one request carrying everything, without the signing key in
# its environment, and its outputs come from the response.
check_request() {
  [ "$(wc -l < "$t/api.log")" -eq 1 ] || fail "expected exactly one API request, got: $(cat "$t/api.log")"
  jq -e --arg bin "binary=@$t/fw.bin" '
      (.args | any(. == "Authorization: Bearer tok-1"))
      and (.args | any(. == $bin))
      and .key_in_env == false
    ' "$t/api.log" >/dev/null || fail "unexpected request: $(cat "$t/api.log")"
  grep -qx 'build-number=57' "$t/github_output" || fail "build-number output missing"
}
check_release() {
  check_request
  jq -e '
      .url == "https://example.test/api/v1/projects/proj-1/release/"
      and (.args | any(. == "rollout_percentage=050"))
      and (.args | any(. == "channel_name=beta testers"))
    ' "$t/api.log" >/dev/null || fail "unexpected release request: $(cat "$t/api.log")"
  grep -qx 'artifact-id=art-1'    "$t/github_output" || fail "artifact-id output missing"
  grep -qx 'deployment-id=dep-1'  "$t/github_output" || fail "deployment-id output missing"
}
check_upload() {
  check_request
  jq -e '.url == "https://example.test/api/v1/projects/proj-1/artifacts/"' "$t/api.log" >/dev/null ||
    fail "unexpected upload request: $(cat "$t/api.log")"
  grep -qx 'artifact-id=art-2' "$t/github_output" || fail "artifact-id output missing"
}

manifest() {
  jq -r '.args[] | select(startswith("manifest=")) | sub("^manifest="; "")' "$t/api.log"
}

for name in release upload; do
  step="$t/$name.sh"
  check="check_$name"

  # Signed, and the CLI makes it strict-ready.
  run_step signed
  [ "$status" -eq 0 ] || fail "$name: signed build failed"
  "$check"
  manifest | jq -e '.security_mode == "signed" and .signing_metadata.key_id == "k1"
                    and .signing_metadata.signature == "c2ln"' >/dev/null ||
    fail "$name: signed manifest wrong: $(manifest)"
  jq -e --arg bin "$t/fw.bin" '
      .argv == ["build", "make-strict", "57", $bin]
      and .token == "tok-1" and .project == "proj-1"
      and .url == "https://example.test" and .key == "key-pem"
    ' "$t/cli.log" >/dev/null || fail "$name: CLI called wrongly: $(cat "$t/cli.log")"
  grep -q '^::warning::' "$t/out" && fail "$name: warning on a successful strict step"

  # Signed, and making it strict-ready fails in each way the review listed
  # that a stub can reproduce. The build still stands, the step stays green,
  # and nothing marks the job as failed.
  for case in fail old missing; do
    if [ "$case" = missing ]; then
      run_step signed PATH="$t/nocli:$base_path"
    else
      run_step signed CLI_MODE="$case"
    fi
    [ "$status" -eq 0 ] || fail "$name: strict failure ($case) failed the step"
    "$check"
    grep -q '^::warning::.*57' "$t/out" || fail "$name: no warning naming the build ($case)"
    grep -q '^::error::' "$t/out" && fail "$name: error annotation on a green step ($case)"
    [ -z "$(ls -d "$t"/simpleota-cli.* 2>/dev/null)" ] || fail "$name: work directory left behind ($case)"
  done

  # Unsigned: one request, and the CLI is never run.
  run_step basic
  [ "$status" -eq 0 ] || fail "$name: unsigned build failed"
  "$check"
  manifest | jq -e '.security_mode == "basic" and (has("signing_metadata") | not)' >/dev/null ||
    fail "$name: unsigned manifest wrong: $(manifest)"
  [ ! -s "$t/cli.log" ] || fail "$name: CLI ran for an unsigned build"
  grep -q '^::warning::' "$t/out" && fail "$name: warning on an unsigned build"

  # A failed request still fails the step, and nothing is made strict.
  run_step signed API_FAIL=1
  [ "$status" -ne 0 ] || fail "$name: a failed request was reported as success"
  [ ! -s "$t/cli.log" ] || fail "$name: CLI ran after a failed request"
done

echo "release and upload steps ok"
