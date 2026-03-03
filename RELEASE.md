# Releasing PlayerKit

This document is the release checklist for stable public distribution.

## 1) Choose the version

- Follow Semantic Versioning.
- Use the next tag format: `X.Y.Z` (example: `1.1.1`).

## 2) Update release notes

- Update `CHANGELOG.md`:
  - Move items from `[Unreleased]` into the new version section.
  - Add the release date.

## 2.1) License and notice check

- Ensure `LICENSE` remains MIT.
- Update `NOTICE` if binary dependencies or their distribution terms change.
- Update `THIRD_PARTY_NOTICES.md` when binary target source URLs or upstream terms references change.

## 3) Validate package and artifacts

Run locally:

```bash
swift package describe
./scripts/verify_binary_targets.sh
./scripts/verify_third_party_notices.sh
xcodebuild -scheme PlayerKit -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme PlayerKit -destination 'generic/platform=iOS' build
./scripts/run_unit_tests.sh
```

## 4) If binary frameworks changed

When `VLCKit` or `GoogleCast` XCFramework zips are updated:

1. Upload the new zip files to the GitHub release assets.
2. Update `url` and `checksum` in `Package.swift`.
3. Re-run `./scripts/verify_binary_targets.sh`.

## 5) Tag and publish

```bash
git tag X.Y.Z
git push origin X.Y.Z
```

Create a GitHub release for the same tag and include release notes from `CHANGELOG.md`.

## 6) Post-release smoke check

- In a clean sample app, add the package from GitHub.
- Confirm package resolution and iOS build success.
