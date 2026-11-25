---
name: release
description: Publishes ziglint releases. Use when releasing, versioning, tagging, or publishing a new version.
---

# Releasing ziglint

The org's release workflow does the work; this repo supplies three things and a tag.

1. Move the `## [Unreleased]` section of `CHANGELOG.md` into `## [X.Y.Z] - DATE` and run `just release-prep X.Y.Z` from `~/code/baskingspot/.github`. The script stamps the section, writes `docs/releases/vX.Y.Z.md` from it for the GitHub release body, and sets `.version` in `build.zig.zon`. Do not add an install section; the workflow appends one.
2. Update `.github/release.yaml` only if the platforms change.
3. Commit, push, then `just release X.Y.Z`. It checks a clean tree on `main` level with `origin`, makes a signed tag, and pushes it.

A `v*` tag runs the shared workflow in `baskingspot/gh-actions`: the repo's CI, the builds for the platforms in `.github/release.yaml`, `SHA256SUMS`, an attestation, the GitHub release, and a Homebrew cask installed on macOS and Linux before it is committed to `baskingspot/homebrew-tap`.

Nothing is uploaded by hand. A release that fails leaves the tag; fix forward with the next version, or delete the release and re-run the whole workflow when the failure is the workflow's own.

## The notes file

A note opens with one `## ` heading that says what the release does, then a paragraph for someone deciding whether to upgrade, then `## Changes` or `## Fixes`. A user-visible behavior only: a rule that changed, a flag, an output format. Not a refactor, not a lint fix, not a dependency bump.
