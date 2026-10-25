# SimpleOTA GitHub Actions

Ship ESP32 firmware from CI. Sign a build, upload it to
[SimpleOTA](https://simpleota.com), and deploy it, without writing the openssl
and curl plumbing yourself.

Four actions live here. Most pipelines only need the first.

| Action | Use it when |
|---|---|
| `wassie-dev/simpleOTA-actions@v1` | Every merge should ship. Signs, uploads and deploys in one step. |
| `wassie-dev/simpleOTA-actions/upload@v1` | CI builds and uploads, but a human decides when it ships. |
| `wassie-dev/simpleOTA-actions/deploy@v1` | Deploy a build that was uploaded earlier. |
| `wassie-dev/simpleOTA-actions/promote@v1` | Ramp a canary, or pause and cancel a rollout. |

## Ship on every merge

```yaml
- uses: wassie-dev/simpleOTA-actions@v1
  with:
    api-token:    ${{ secrets.SIMPLEOTA_API_TOKEN }}
    project-id:   ${{ vars.SIMPLEOTA_PROJECT_ID }}
    binary:       build/my-firmware.ino.bin
    version-label: ${{ steps.version.outputs.version }}
    chip-family:  esp32
    board-id:     esp32-devkitc
    signing-key:  ${{ secrets.SIMPLEOTA_SIGNING_KEY }}
    key-id:       prod-2026
```

Omit `signing-key` and `key-id` and the build uploads unsigned.

Note that `api-token` and `signing-key` come from **Secrets**, while
`project-id` comes from **Variables**. GitHub keeps those in two separate
stores, and referencing one as the other yields an empty string with no useful
error.

## Upload now, ship after approval

Split the two when a person should decide. Use a GitHub Environment with
required reviewers to gate the second job.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      artifact-id: ${{ steps.up.outputs.artifact-id }}
    steps:
      - uses: actions/checkout@v4
      # ... compile ...
      - uses: wassie-dev/simpleOTA-actions/upload@v1
        id: up
        with:
          api-token:     ${{ secrets.SIMPLEOTA_API_TOKEN }}
          project-id:    ${{ vars.SIMPLEOTA_PROJECT_ID }}
          binary:        build/my-firmware.ino.bin
          version-label: ${{ github.run_number }}
          chip-family:   esp32
          signing-key:   ${{ secrets.SIMPLEOTA_SIGNING_KEY }}
          key-id:        prod-2026

  ship:
    needs: build
    environment: production      # required reviewers gate this
    runs-on: ubuntu-latest
    steps:
      - uses: wassie-dev/simpleOTA-actions/deploy@v1
        with:
          api-token:   ${{ secrets.SIMPLEOTA_API_TOKEN }}
          project-id:  ${{ vars.SIMPLEOTA_PROJECT_ID }}
          artifact-id: ${{ needs.build.outputs.artifact-id }}
          channel-ids: ${{ vars.SIMPLEOTA_STABLE_CHANNEL_ID }}
```

## Canary, then ramp

```yaml
      - uses: wassie-dev/simpleOTA-actions/deploy@v1
        id: canary
        with:
          api-token:          ${{ secrets.SIMPLEOTA_API_TOKEN }}
          project-id:         ${{ vars.SIMPLEOTA_PROJECT_ID }}
          artifact-id:        ${{ needs.build.outputs.artifact-id }}
          channel-ids:        ${{ vars.SIMPLEOTA_STABLE_CHANNEL_ID }}
          rollout-strategy:   canary
          rollout-percentage: '10'

      # ... watch the rollout, then in a gated job ...

      - uses: wassie-dev/simpleOTA-actions/promote@v1
        with:
          api-token:          ${{ secrets.SIMPLEOTA_API_TOKEN }}
          project-id:         ${{ vars.SIMPLEOTA_PROJECT_ID }}
          deployment-id:      ${{ needs.canary.outputs.deployment-id }}
          action:             ramp
          rollout-percentage: '100'
```

## Inputs and outputs

Every action takes `api-token`, `project-id` and `base-url` (default
`https://simpleota.com`, override for staging). See each `action.yml` for the
full list; the descriptions there are the reference.

The release action outputs `build-number`, `artifact-id` and `deployment-id`.
`upload` outputs the first two, `deploy` outputs `deployment-id` and `state`,
`promote` outputs `state`.

## Things worth knowing

**Upload the application binary, not a merged image.** Arduino CLI also emits
`.ino.merged.bin`, which contains the bootloader and partition table and is
meant for a factory flash over USB. It will not fit an OTA slot, and it is the
most common cause of `update_begin_failed`.

**Compatibility fields are matched exactly.** If `chip-family`, `board-id` or
`partition-profile` do not match what a device reports, that device is never
offered the build and reports `no_compatible_build`. Compare against a device
row in the dashboard if a deployment looks active but nothing updates.

**Build numbers come from the server.** `version-label` is for humans; update
ordering uses the build number SimpleOTA allocates.

**Guard the release path yourself.** These actions do not check the branch, so
add `if: github.ref == 'refs/heads/main'` unless you want pull requests
shipping firmware.

**The signing key never touches disk outside the runner.** It is written to
`RUNNER_TEMP` with `umask 077`, used, and removed by an EXIT trap so a failure
part-way through does not leave it behind.

## Requirements

`bash`, `curl`, `jq` and OpenSSL 3.x, all present on GitHub-hosted Ubuntu
runners. Nothing is installed at runtime.

## Related

- [SimpleOTAClient for Arduino](https://github.com/wassie-dev/simpleOTAClient-Arduino)
- [SimpleOTA component for ESP-IDF](https://github.com/wassie-dev/simpleOTAClient-ESP-IDF)
- [Developer API reference](https://wiki.simpleota.com/api/developer-api/)

## License

MIT. See [LICENSE](LICENSE).
