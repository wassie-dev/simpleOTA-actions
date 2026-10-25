# Changelog

All notable changes to these actions are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Pin to `@v1` to track the current major, or to an exact tag such as `@v1.0.0`
for a fixed version.

## [Unreleased]

## [1.0.3] - 2026-08-24

### Fixed

- API errors now report the server's explanation instead of a bare curl exit
  code. Every request used `curl --fail-with-body` inside a command
  substitution under `set -e`: on an HTTP error curl wrote the body to stdout
  and exited non-zero, which killed the step before anything read the captured
  variable. A rejected upload or an illegal deployment transition surfaced in
  CI as `curl: (22) The requested URL returned error: 400`, with the
  `{"detail": ...}` message discarded. Requests now go through
  `scripts/api.sh`, which captures the status and body separately and fails
  the step with the `detail` text. A `pause` on a draft deployment reports
  `cannot pause deployment in state 'draft'`. Applies to all four actions;
  no input or output changed.

### Changed

- CI now exercises all four actions against a real project, walking upload,
  deploy (with `start`), promote (ramp, pause, resume) and the root release
  action, then cancelling what it created. Previously only `upload` ran live,
  which is why a broken transition path in `deploy` and `promote` reached a
  release with a green tick. The channel id `deploy` needs is looked up from
  the API at run time rather than configured, so no new secret or variable is
  required. The live job is now limited to `main` and manual runs, because each
  run consumes two of the test project's monthly artifact uploads.

## [1.0.2] - 2026-08-24

### Fixed

- `deploy` and `promote` posted deployment transitions to
  `/deployments/{id}/actions/`, which is no longer a route. The endpoint is
  `/deployments/{id}/transition/`. Both actions returned a `404` from every
  call: `promote` in full, and `deploy` whenever `start` was left at its
  default of `true`, so a deployment was created but never started and no
  device was offered the build. The request bodies were already correct, so
  this is a path fix only, with no change to inputs or outputs. The root
  action was unaffected: it uses `/release/`, which uploads, deploys and
  starts in one call.

## [1.0.1] - 2026-08-23

### Fixed

- Required inputs are now validated before anything else runs. GitHub does not
  enforce `required: true` for composite actions, so an input that was never
  set, or was read from the wrong store, previously reached the API as an empty
  value: an empty `project-id` produced the URL `/api/v1/projects//artifacts/`
  and an opaque `405`. All four actions now fail immediately, naming every
  empty input and pointing at the Secrets versus Variables distinction that
  causes most of these. Validation runs before signing, so a misconfigured
  workflow never touches the signing key.

### Changed

- The input validator reads values by indirect expansion rather than `eval`.
  The previous form would have executed a crafted variable name such as
  `VAR-$(cmd)`. It was not reachable, since the names are fixed in each
  `action.yml` rather than supplied by callers, but it was an avoidable
  code-execution surface.
- Values are read by name from the environment, so no token appears in `argv`.

## [1.0.0]

### Added

- `simpleOTA-actions` (root): sign, upload and deploy a firmware build in one
  step, via the `/release/` endpoint.
- `simpleOTA-actions/upload`: sign and upload without deploying. Outputs
  `artifact-id` and `build-number` for a later, gated deploy.
- `simpleOTA-actions/deploy`: create and start a deployment for an existing
  artifact, with channel and group targeting and a canary strategy.
- `simpleOTA-actions/promote`: ramp, start, pause, resume, cancel or complete a
  deployment.

[Unreleased]: https://github.com/wassie-dev/simpleOTA-actions/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/wassie-dev/simpleOTA-actions/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/wassie-dev/simpleOTA-actions/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/wassie-dev/simpleOTA-actions/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/wassie-dev/simpleOTA-actions/releases/tag/v1.0.0
