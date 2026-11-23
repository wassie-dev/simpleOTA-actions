#!/usr/bin/env bash
# Run the root action's "Upload and deploy" step and the upload action's
# "Upload artifact" step against a stub SimpleOTA API and a stub CLI, then
# with the real api.sh and curl against a local capture server, and check
# what they sent and what they reported.
#
# Guards three things: a signed build still goes out as one request (/release/
# or /artifacts/), a failure to make it strict-ready (CLI missing, CLI too
# old, CLI error) leaves the step green with a warning instead of failing it,
# and the form fields curl sends arrive exactly as built.
#
# Usage: tests/release-step.sh   (from the repository root; needs python3
# with PyYAML, jq and curl)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
t="$(mktemp -d)"
server_pid=""
trap '[ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null; rm -rf "$t"' EXIT

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
  jq -e --arg bin "binary=@\"$t/fw.bin\"" '
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

# The same steps with the real api.sh and curl, against a server on
# 127.0.0.1 that saves the bytes of each multipart part it receives. Text
# that curl's -F would parse (`;`, quotes, a leading @) must reach
# the server unchanged, and a binary path with `;` or `,` must send that
# file under its own name, not a sibling whose name is a prefix of it.
mkdir -p "$t/real/upload" "$t/received"
cp -r "$root/scripts" "$t/real/scripts"
extract_step "$root/action.yml" release "$t/real" > "$t/real-release.sh"
extract_step "$root/upload/action.yml" upload "$t/real/upload" > "$t/real-upload.sh"
cat > "$t/server.py" <<'PY'
import email.parser, email.policy, http.server, os, re, sys
out, port_fifo = sys.argv[1:]
count = 0
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        global count
        count += 1
        body = self.rfile.read(int(self.headers["Content-Length"]))
        head = b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n"
        msg = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(head + body)
        d = os.path.join(out, str(count))
        os.mkdir(d)
        for part in msg.iter_parts():
            name = part.get_param("name", header="content-disposition")
            with open(os.path.join(d, name), "wb") as f:
                f.write(part.get_payload(decode=True))
            # The raw header value: form-data does not backslash-escape the
            # filename, and the email parser would unescape it.
            disposition = dict(part.raw_items())["Content-Disposition"]
            filename = re.search(r'filename="([^"]*)"', disposition)
            if filename:
                with open(os.path.join(d, name + ".filename"), "w") as f:
                    f.write(filename.group(1))
        resp = b'{"build_number": 57, "artifact_id": "art-1", "deployment_id": "dep-1", "id": "art-2"}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_fifo, "w") as f:
    f.write(f"{server.server_port}\n")
server.serve_forever()
PY
mkfifo "$t/port"
exec 3<>"$t/port"
python3 -I "$t/server.py" "$t/received" "$t/port" &
server_pid=$!
read -r -t 10 port <&3 || { echo "FAIL: capture server did not start"; exit 1; }
exec 3<&-

notes='Fix A; add B, "quoted" \ backslash, type=text/plain
second line; filename=x'
channel='@beta; "eu", west'
mkdir "$t/paths"
printf 'sibling' > "$t/paths/fw"
binaries=('fw;1.bin' 'fw,1.bin' 'fw\1;2.bin' 'q"x\y.bin')
for file in "${binaries[@]}"; do
  printf 'firmware at %s' "$file" > "$t/paths/$file"
done
expected="$(FRAMEWORK=arduino VERSION_LABEL=1.2.3 CHIP_FAMILY=esp32 SECURITY_MODE=basic \
  RELEASE_NOTES="$notes" "$root/scripts/manifest.sh")"

n=0
for name in release upload; do
  step="$t/real-$name.sh"
  n=$((n + 1))
  run_step basic BASE_URL="http://127.0.0.1:$port/" RELEASE_NOTES="$notes" CHANNEL="$channel"
  [ "$status" -eq 0 ] || fail "$name: request through curl failed"
  got="$t/received/$n"
  printf '%s' "$expected" | cmp -s - "$got/manifest" ||
    fail "$name: manifest changed in transit: $(cat "$got/manifest" 2>/dev/null)"
  cmp -s "$t/fw.bin" "$got/binary" || fail "$name: binary changed in transit"
  if [ "$name" = release ]; then
    printf '%s' "$channel" | cmp -s - "$got/channel_name" ||
      fail "$name: channel_name changed in transit: $(cat "$got/channel_name" 2>/dev/null)"
    printf '050' | cmp -s - "$got/rollout_percentage" ||
      fail "$name: rollout_percentage changed in transit"
  fi

  for file in "${binaries[@]}"; do
    n=$((n + 1))
    run_step basic BASE_URL="http://127.0.0.1:$port/" BINARY="$t/paths/$file"
    [ "$status" -eq 0 ] || fail "$name: upload of '$file' failed"
    got="$t/received/$n"
    cmp -s "$t/paths/$file" "$got/binary" || fail "$name: '$file' sent other bytes than its own"
    # curl escapes `"` in the filename header, so a name with one does not
    # arrive byte for byte.
    case "$file" in
      *'"'*) ;;
      *) printf '%s' "$file" | cmp -s - "$got/binary.filename" ||
           fail "$name: '$file' sent under another name: $(cat "$got/binary.filename" 2>/dev/null)" ;;
    esac
  done
done

echo "release and upload steps ok"
