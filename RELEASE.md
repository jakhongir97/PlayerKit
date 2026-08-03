# Releasing PlayerKit

This document is the release checklist for stable public distribution.

## 1) Choose the version

- Follow Semantic Versioning.
- Use the next tag format: `X.Y.Z` (example: `1.1.1`).
- The current unreleased package raises the iOS minimum from 14 to 15 and
  removes public API. It must ship in a new major version unless those breaking
  changes are reverted.

## 2) Update release notes

- Update `CHANGELOG.md`:
  - Move items from `[Unreleased]` into the new version section.
  - Add the release date.

## 2.1) License and notice check

- Ensure `LICENSE` remains MIT.
- Update `NOTICE` if binary dependencies or their distribution terms change.
- Update `THIRD_PARTY_NOTICES.md` when binary target source URLs or upstream terms references change.
- Do not release while any dependency has `Release status: blocked` in
  `THIRD_PARTY_NOTICES.md`.

## 3) Validate package and artifacts

Run locally:

```bash
swift package describe
PLAYERKIT_STRICT_BINARY_COMPLIANCE=1 ./scripts/verify_binary_targets.sh
./scripts/verify_third_party_notices.sh
swift build -c release
swift build -Xswiftc -swift-version -Xswiftc 6
xcodebuild -scheme PlayerKit -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme PlayerKit -destination 'generic/platform=iOS Simulator' SWIFT_VERSION=6 build
xcodebuild -scheme PlayerKit -destination 'generic/platform=iOS' build
./scripts/run_unit_tests.sh
swift package diagnose-api-breaking-changes <last-stable-tag> --products PlayerKit
```

Review every reported API break against `CHANGELOG.md`; any accepted break
requires a major version. The SwiftPM diagnostic covers the host platform, so
iOS-only protocol-conformance removals must also be recorded during the iOS
build/release review.

## 4) If binary frameworks changed

When `VLCKit` or `GoogleCast` XCFramework zips are updated:

1. Retain the exact upstream source, version, build recipe, and vendor
   signature/attestation before mirroring anything.
2. Confirm the artifact contains the required privacy manifest and applicable
   license/notice material; generate an SBOM from the exact build inputs.
3. Obtain legal confirmation that public mirroring is permitted.
4. Upload the verified zip files to immutable release assets.
5. Update `url`, `checksum`, and `THIRD_PARTY_NOTICES.md` together.
6. Re-run the strict binary verification command above.

## 5) Tag and publish

```bash
git tag -s X.Y.Z -m "PlayerKit X.Y.Z"
git tag -v X.Y.Z
git push origin X.Y.Z
```

Create a GitHub release for the same tag and include release notes from `CHANGELOG.md`.

## 6) Post-release smoke check

- In a clean sample app, add the package from GitHub.
- Confirm package resolution and iOS build success.
- Confirm Cast local-network permission, handoff failure recovery, PiP, VLC
  playback, screen sharing/capture posture, VoiceOver, and controller teardown
  on supported physical devices.
- Exercise a compact iPhone and iPad multitasking width at accessibility text
  sizes, plus Switch Control and Voice Control (setting
  `voiceControlRunningOverride` because UIKit exposes no public status API).
- While paused, switch into and out of VLC on hardware and confirm there is no
  audible or visible autoplay blip during its load-then-pause transition.
