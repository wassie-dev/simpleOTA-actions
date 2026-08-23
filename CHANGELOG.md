# Changelog

All notable changes to these actions are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Pin to `@v1` to track the current major, or to an exact tag such as `@v1.0.0`
for a fixed version.

## [Unreleased]

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

[Unreleased]: https://github.com/xanderwasserman/simpleOTA-actions/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/xanderwasserman/simpleOTA-actions/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/xanderwasserman/simpleOTA-actions/releases/tag/v1.0.0
