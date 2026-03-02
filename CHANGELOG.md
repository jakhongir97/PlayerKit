# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## [Unreleased]

### Added
- CI workflow for package validation and iOS builds.
- Release runbook (`RELEASE.md`) and binary target verification script.
- MIT license and open-source policy files (`LICENSE`, `NOTICE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`).
- Error reporting API with `PlayerKitError` and `PlayerKitDidFail` notifications.
- Unit-test baseline for core state and model behavior.

### Changed
- `Package.swift` now explicitly processes package resources.
- Menu view model ownership moved to `@StateObject` for stable lifecycle behavior.
- Player lifecycle/state propagation now uses internal event protocols instead of direct wrapper-to-singleton mutations.
- Runtime playback state updates are event-driven from player wrappers with a timer fallback for non-emitting players.
- Player UI/menu viewmodels now support injected `PlayerManager` instances (default `.shared`) for better testability and composition.

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

## [1.1.0] - 2025-09-25

### Changed
- Liquid Glass adaptation fixes.
