# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## [Unreleased]

### Added
- CI workflow for package validation and iOS builds.
- Release runbook (`RELEASE.md`) and binary target verification script.
- MIT license and open-source policy files (`LICENSE`, `NOTICE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`).
- Third-party dependency inventory (`THIRD_PARTY_NOTICES.md`) and validation script (`scripts/verify_third_party_notices.sh`).
- Portable simulator test runner script (`scripts/run_unit_tests.sh`) for local and CI environments.
- Error reporting API with `PlayerKitError` and `PlayerKitDidFail` notifications.
- Unit-test baseline for core state and model behavior.
- Public `Player` facade API (`PlayerKit.Player`) for lightweight embed/integration flows.
- Dubber HLS integration guide (`docs/playerkit-integration.md`) with end-to-end session/start/play examples.
- Built-in Dubber control button in player top controls (opt-in via `DubberConfiguration`).
- Dubber integration primitives (`DubberConfiguration`, Dubber client, and manager facade methods).

### Changed
- `Package.swift` now explicitly processes package resources.
- Menu view model ownership moved to `@StateObject` for stable lifecycle behavior.
- Player lifecycle/state propagation now uses internal event protocols instead of direct wrapper-to-singleton mutations.
- Runtime playback state updates are event-driven from player wrappers with a timer fallback for non-emitting players.
- Player UI/menu viewmodels now support injected `PlayerManager` instances (default `.shared`) for better testability and composition.
- Runtime integrations (audio session, cast subscriptions, controller events) are configured lazily on first player setup.
- CI now executes simulator unit tests and validates third-party notice coverage for binary targets.
- `PlayerView(playerManager:)` now bootstraps non-destructively to preserve active playback state when using external manager/facade ownership.
- Player manager now supports safe async swapping from source HLS to Dubber-generated master HLS while preserving playback position.

### Fixed
- Player state subscription lifecycle split into long-lived vs resettable subscriptions.
- AVPlayer playback-end observer cleanup for repeated media loads.
- Public access control on `TrackInfo` and `StreamingInfo` model members.
- Episode prev/next button disabled states.
- Lock button icon now reflects actual lock state.
- `shouldDismiss` naming consistency across the codebase.
- Automatic `contentType` handling for episode and movie loading flows.
- Accessibility labels, hints, and identifiers for primary playback controls.
- Removed direct `PlayerManager.shared` coupling in AV/VLC wrappers and core managers (`CastManager`, `AudioSessionManager`, `GestureManager`, `OrientationManager`) via injected callbacks.
- Removed direct `PlayerManager.shared` coupling from player views and menu viewmodels by propagating one manager instance through the UI tree.
- Prevented unintended player resets caused by SwiftUI `PlayerView` re-initialization by moving startup side effects from initializers to one-time `onAppear` bootstrap.

## [1.1.0] - 2025-09-25

### Changed
- Liquid Glass adaptation fixes.
