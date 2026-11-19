#!/usr/bin/env bash
# Make an uploaded signed build strict-ready, so devices in strict mode are
# offered it.
#
# The SimpleOTA CLI does the work: it signs the build's project, key, build
# number and SHA-256 with the signing key and attaches that strict signature.
# Using the CLI keeps one implementation of what gets signed. A `simpleota`
# already on PATH is used as it is; otherwise install-cli.sh installs the
# pinned release into RUNNER_TEMP for this step.
#
# This step is best effort. On any failure it prints a ::warning:: that names
# the build and the command that finishes the job, and exits non-zero; the
# caller carries on. A build that is not strict-ready is still offered to
# devices in signed mode, and the server keeps it from devices in strict mode.
#
# Env: API_TOKEN, PROJECT_ID, BASE_URL, SIGNING_KEY (PEM), BUILD, BINARY,
#      CLI_VERSION (optional)
set -euo pipefail

: "${SIGNING_KEY:?signing-key is empty}"
: "${BUILD:?build number is empty}"

give_up() {
  echo "::warning::$1 Build ${BUILD} was uploaded but is not strict-ready. Finish with: simpleota build make-strict ${BUILD} <bin>" >&2
  exit 1
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d "${RUNNER_TEMP:-/tmp}/simpleota-cli.XXXXXX")" ||
  give_up "Could not create a work directory."
trap 'rm -rf "$WORK"' EXIT

CLI="$(command -v simpleota || true)"
if [ -z "$CLI" ]; then
  # The installer needs no secrets, so it gets none. Quiet, because its
  # ::error:: would mark a job red that this step leaves green.
  CLI="$(env -u SIGNING_KEY -u API_TOKEN CLI_INSTALL_QUIET=1 \
    "$here/install-cli.sh" "$WORK/bin")" ||
    give_up "Could not install the SimpleOTA CLI."
fi

# cobra prints the parent's help for an unknown subcommand and exits 0, so
# look for the command by name.
if ! "$CLI" build --help 2>/dev/null | grep -q 'make-strict'; then
  give_up "This SimpleOTA CLI ($("$CLI" --version 2>/dev/null || echo unknown version)) has no 'build make-strict'; use a newer cli-version or update the simpleota on PATH."
fi

# A stalled server must not hold the job until its timeout, which would turn
# it red after the release went out. macOS runners have no timeout(1).
limit=()
if command -v timeout >/dev/null 2>&1; then limit=(timeout 120); fi

# The CLI reads everything from the environment, so neither the token nor the
# key is placed in argv. Its config directory is a throwaway: nothing is
# stored on the runner.
SIMPLEOTA_TOKEN="$API_TOKEN" \
SIMPLEOTA_PROJECT="$PROJECT_ID" \
SIMPLEOTA_API_URL="${BASE_URL%/}" \
SIMPLEOTA_SIGNING_KEY="$SIGNING_KEY" \
SIMPLEOTA_CONFIG_DIR="$WORK/config" \
SIMPLEOTA_NO_KEYRING=1 \
  ${limit[@]+"${limit[@]}"} "$CLI" build make-strict "$BUILD" "$BINARY" >&2 ||
  give_up "The strict signature was not attached."
