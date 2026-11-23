#!/usr/bin/env bash
# Print a curl -F argument that sends the file at <path> as form field
# <field>, under the file's own name.
#
# Usage: form-file.sh <field> <path>
#
# curl reads `;` and `,` in an unquoted -F file name as syntax, so a path such
# as `fw;1.bin` would upload `fw` instead. The path is double-quoted, with `\`
# and `"` backslash-escaped, as curl's -F syntax documents.
set -euo pipefail

path="${2//\\/\\\\}"
path="${path//\"/\\\"}"
printf '%s=@"%s"' "$1" "$path"
