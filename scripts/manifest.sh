#!/usr/bin/env bash
# Build the FirmwareManifest JSON on stdout.
#
# Uses jq rather than string concatenation so release notes containing quotes,
# newlines or backslashes cannot produce invalid JSON. The API rejects unknown
# keys, so optional fields are omitted entirely when empty rather than sent as
# empty strings.
set -euo pipefail

jq -nc \
  --arg framework            "${FRAMEWORK}" \
  --arg version_label        "${VERSION_LABEL}" \
  --arg chip_family          "${CHIP_FAMILY}" \
  --arg board_id             "${BOARD_ID:-}" \
  --arg partition_profile    "${PARTITION_PROFILE:-}" \
  --arg hw_min               "${HARDWARE_REVISION_MIN:-}" \
  --arg hw_max               "${HARDWARE_REVISION_MAX:-}" \
  --arg release_notes        "${RELEASE_NOTES:-}" \
  --arg security_mode        "${SECURITY_MODE}" \
  --arg key_id               "${KEY_ID:-}" \
  --arg signature            "${SIGNATURE_B64:-}" \
  '
    {framework: $framework, version_label: $version_label, chip_family: $chip_family}
    + (if $board_id          != "" then {board_id: $board_id}                       else {} end)
    + (if $partition_profile != "" then {partition_profile: $partition_profile}     else {} end)
    + (if $hw_min            != "" then {hardware_revision_min: $hw_min}            else {} end)
    + (if $hw_max            != "" then {hardware_revision_max: $hw_max}            else {} end)
    + (if $release_notes     != "" then {release_notes: $release_notes}             else {} end)
    + {security_mode: $security_mode}
    + (if $security_mode == "signed"
       then {signing_metadata: {key_id: $key_id, algorithm: "ed25519", signature: $signature}}
       else {} end)
  '
