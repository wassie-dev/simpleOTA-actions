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
# Write beside the pin and move it into place only once it is complete, so a
# failed run leaves the current pin as it was.
tmp="$(mktemp "$here/cli-pin.txt.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
{
  echo "# The SimpleOTA CLI release these actions run, and the SHA-256 of each of"
  echo "# its archives. Written by scripts/pin-cli.sh; read by scripts/install-cli.sh."
  echo "version ${version}"
  grep -E "^[0-9a-f]{64}  simpleota_${version//./\\.}_(linux|darwin)_(amd64|arm64)\.tar\.gz$" <<<"$sums" || true
} > "$tmp"
archives="$(grep -c 'tar\.gz$' "$tmp" || true)"
if [ "$archives" -ne 4 ]; then
  echo "expected 4 archives (linux and darwin, amd64 and arm64) in ${url}, found ${archives}" >&2
  exit 1
fi
chmod 0644 "$tmp"
mv "$tmp" "$here/cli-pin.txt"
cat "$here/cli-pin.txt"
