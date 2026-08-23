# Changelog

All notable changes to these actions are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Pin to `@v1` to track the current major, or to an exact tag such as `@v1.0.0`
for a fixed version.

## [Unreleased]

## [1.0.0]

### Added

- `simpleota-actions` (root): sign, upload and deploy a firmware build in one
  step, via the `/release/` endpoint.
- `simpleota-actions/upload`: sign and upload without deploying. Outputs
  `artifact-id` and `build-number` for a later, gated deploy.
- `simpleota-actions/deploy`: create and start a deployment for an existing
  artifact, with channel and group targeting and a canary strategy.
- `simpleota-actions/promote`: ramp, start, pause, resume, cancel or complete a
  deployment.
