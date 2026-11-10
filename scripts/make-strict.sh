#!/usr/bin/env bash
# Make an uploaded signed build strict-ready, so devices in strict mode are
# offered it.
#
# The SimpleOTA CLI does the work: it signs the build's project, key, build
# number and SHA-256 with the signing key and attaches that strict signature.
# Using the CLI keeps one implementation of what gets signed. A `simpleota`
# already on PATH is used as it is; otherwise the release named by CLI_VERSION
# (the latest when empty) is installed into RUNNER_TEMP, checked against the
# release's checksums by its install script.
#
# Env: API_TOKEN, PROJECT_ID, BASE_URL, SIGNING_KEY (PEM), BUILD, BINARY,
#      CLI_VERSION (optional)
set -euo pipefail

: "${SIGNING_KEY:?signing-key is empty}"
: "${BUILD:?build number is empty}"

INSTALL_URL="https://github.com/wassie-dev/simpleOTA-cli/releases/latest/download/install.sh"
WORK="$(mktemp -d "${RUNNER_TEMP:-/tmp}/simpleota-cli.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

CLI="$(command -v simpleota || true)"
if [ -z "$CLI" ]; then
  if ! curl -fsSL "$INSTALL_URL" |
       SIMPLEOTA_VERSION="${CLI_VERSION:-}" SIMPLEOTA_INSTALL_DIR="$WORK/bin" \
       SIMPLEOTA_NO_MODIFY_PATH=1 sh >&2; then
    echo "::error::could not install the SimpleOTA CLI, so build ${BUILD} was uploaded but is not strict-ready and was not deployed. Run the job again, or finish with: simpleota build make-strict ${BUILD} <bin>" >&2
    exit 1
  fi
  CLI="$WORK/bin/simpleota"
fi

# cobra prints the parent's help for an unknown subcommand and exits 0, so
# look for the command by name.
if ! "$CLI" build --help 2>/dev/null | grep -q 'make-strict'; then
  echo "::error::this SimpleOTA CLI ($("$CLI" --version 2>/dev/null || echo unknown version)) has no 'build make-strict', so build ${BUILD} was uploaded but is not strict-ready and was not deployed. Leave cli-version empty for the latest release, or update the simpleota on PATH." >&2
  exit 1
fi

# The CLI reads everything from the environment, so neither the token nor the
# key is placed in argv. Its config directory is a throwaway: nothing is
# stored on the runner.
if ! SIMPLEOTA_TOKEN="$API_TOKEN" \
     SIMPLEOTA_PROJECT="$PROJECT_ID" \
     SIMPLEOTA_API_URL="${BASE_URL%/}" \
     SIMPLEOTA_SIGNING_KEY="$SIGNING_KEY" \
     SIMPLEOTA_CONFIG_DIR="$WORK/config" \
     SIMPLEOTA_NO_KEYRING=1 \
     "$CLI" build make-strict "$BUILD" "$BINARY" >&2; then
  echo "::error::build ${BUILD} was uploaded but is not strict-ready, and was not deployed. Devices in strict mode will not be offered it. Finish with: simpleota build make-strict ${BUILD} <bin>" >&2
  exit 1
fi
