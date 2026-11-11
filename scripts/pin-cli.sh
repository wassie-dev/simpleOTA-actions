#!/usr/bin/env bash
# Maintainers: pin the SimpleOTA CLI release the actions run.
#
# Usage: scripts/pin-cli.sh <version>
#
# Rewrites cli-pin.txt from that release's checksums.txt. Review the diff
# against the release before committing it: this file is what the actions
# trust.
set -euo pipefail

version="${1:?usage: pin-cli.sh <version>}"
version="${version#v}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
url="https://github.com/wassie-dev/simpleOTA-cli/releases/download/v${version}/checksums.txt"

sums="$(curl --proto '=https' --tlsv1.2 -fsSL "$url")"
{
  echo "# The SimpleOTA CLI release these actions run, and the SHA-256 of each of"
  echo "# its archives. Written by scripts/pin-cli.sh; read by scripts/install-cli.sh."
  echo "version ${version}"
  grep -E "  simpleota_${version}_(linux|darwin)_(amd64|arm64)\.tar\.gz$" <<<"$sums"
} > "$here/cli-pin.txt"
cat "$here/cli-pin.txt"
