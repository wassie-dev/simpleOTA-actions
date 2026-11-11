#!/usr/bin/env bash
# Install the SimpleOTA CLI into the directory given as $1 and print the path
# of the binary.
#
# The release and the SHA-256 of each of its archives are pinned in
# cli-pin.txt, next to this script, so a given version of this action always
# runs the same CLI: a later CLI release, or a changed one, is not picked up.
# CLI_VERSION names another release instead; that one is checked against its
# own checksums.txt, which pins nothing, so it is the caller's choice.
#
# Run this without secrets in the environment. It needs none.
#
# Env: CLI_VERSION (optional)
set -euo pipefail

dest="${1:?usage: install-cli.sh <directory>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pin="$here/cli-pin.txt"
releases="https://github.com/wassie-dev/simpleOTA-cli/releases/download"

fail() { echo "::error::$*" >&2; exit 1; }
fetch() { curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$2" "$1"; }
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

pinned="$(awk '$1 == "version" { print $2 }' "$pin")"
version="${CLI_VERSION:-$pinned}"
version="${version#v}"
case "$version" in
  ''|*[!0-9A-Za-z.+-]*) fail "invalid cli-version '${version}'" ;;
esac

case "$(uname -s)" in
  Linux)  os=linux ;;
  Darwin) os=darwin ;;
  *) fail "the SimpleOTA CLI cannot be installed on this runner's OS ($(uname -s)). Put simpleota on PATH before this action." ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) fail "the SimpleOTA CLI cannot be installed on this runner's CPU ($(uname -m)). Put simpleota on PATH before this action." ;;
esac

archive="simpleota_${version}_${os}_${arch}.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch "$releases/v$version/$archive" "$tmp/$archive" ||
  fail "could not download SimpleOTA CLI $version ($archive)"

if [ "$version" = "$pinned" ]; then
  checksums="$pin"
else
  echo "::notice::cli-version $version replaces the CLI release this action pins ($pinned). It is checked against that release's own checksums." >&2
  checksums="$tmp/checksums.txt"
  fetch "$releases/v$version/checksums.txt" "$checksums" ||
    fail "could not download the checksums of SimpleOTA CLI $version"
fi
want="$(awk -v f="$archive" '$2 == f { print $1 }' "$checksums")"
[ -n "$want" ] || fail "no checksum is known for $archive"
got="$(sha256_of "$tmp/$archive")"
[ "$got" = "$want" ] || fail "checksum mismatch for $archive: expected $want, got $got"

mkdir -p "$dest"
tar -xzf "$tmp/$archive" -C "$dest" simpleota
chmod 0755 "$dest/simpleota"
printf '%s\n' "$dest/simpleota"
