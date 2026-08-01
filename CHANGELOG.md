# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic Versioning.

## [Unreleased]

### Added
- Reworked gesture layer. The volume and brightness swipes now cover a full half
  of the picture at full height instead of roughly a fifth of the surface, are
  axis-locked, and have an on-screen HUD again — `FeedbackView` had been deleted
  with nothing replacing it, so those gestures were producing no feedback at all.
- New gestures: horizontal drag-to-scrub with fine-scrub tiers, long-press for
  2× speed, two-finger tap for play/pause, and on macOS a scroll wheel and
  keyboard shortcuts — the first working desktop path to volume.
- First-run gesture walkthrough with a ghost fingertip beside each rail, plus a
  resting affordance, arm-on-contact probing and a confusion nudge. Re-runnable
  via `PlayerManager.showGestureCoach()`; configurable through
  `gestureConfiguration.coachPolicy`.
- `PlayerManager.gestureConfiguration`, `.gestureCapabilities`, `.volume`,
  `.skipForward()`, `.skipBackward()`, `.nudgeVolume(_:)`, `.nudgeBrightness(_:)`
  and `Notification.Name.PlayerKitGestureCoachingDidFinish`.
- Visible ±10s buttons in the transport row, and adjustable Volume/Brightness
  accessibility elements — those gestures previously had no non-gesture path at
  all.

### Fixed
- Reversing a double-tap skip re-read the live playhead, which on every real
  backend still reports the pre-seek position because seeks are asynchronous. A
  back tap after three fast forward taps from 100s landed at 90 while the overlay
  read "10 seconds" — a 40-second regression. It now re-bases on the last target
  actually issued.
- A double tap on a stream with no seekable window hid the entire interface and
  never put it back.
- A skip already hard against the end of the seekable window kept incrementing
  the readout for movement it had not delivered.
- The volume gesture wrote through an `MPVolumeView` that was never added to a
  view hierarchy, so the write reached nothing and iOS drew its own volume HUD
  over the video. Volume now drives the backend by default (`volumeTarget`
  opt-in for system volume), and an `MPVolumeView` is mounted purely to suppress
  the system HUD.
- A seek session could outlive the item it was opened on, so one tap after an
  episode change seeked the new item to the old item's position.
- Engaging a swipe jumped the level by a slop's worth, because the total
  translation was used rather than the travel since engagement.
- A gesture stolen by a system edge swipe, Notification Centre or a call banner
  left a half-applied change behind; the touch host now receives a real cancel.
- Gestures blocked by the lock now report themselves instead of failing silently.
- **The lock was cosmetic.** Locking the player set every control to
  `opacity(0)` but left the whole chrome inside `allowsHitTesting(true)`, so an
  invisible play/pause button, close button and scrubber stayed fully tappable
  and VoiceOver still read them out. Visibility, hit testing and accessibility
  are now driven by one predicate per control.
- Gesture capabilities were computed once when the view reached its window,
  before any backend existed, so the volume half fell through to brightness —
  and with autoplay off nothing ever recomputed them, so the volume gesture
  never arrived at all.
- Auto-hide no longer runs under VoiceOver, Switch Control or Guided Access.

### Changed
- **Brightness and volume swap sides**: brightness is now the leading half,
  volume the trailing half, matching VLC, Infuse and MX Player. Set
  `gestureConfiguration.railMapping = .volumeLeading` to keep the old
  arrangement.
- The brightness gesture pins the panel at 8% and fades a compositing scrim
  below that, rather than driving the panel to black.
- `DoubleTapSeekOverlayState` stores a unit origin rather than a raw point, so
  the ripple survives a rotation.

- Lock-screen and Control Center support: `PlayerManager.isNowPlayingEnabled`
  publishes now-playing metadata and installs the system transport controls
  (play/pause/toggle, 15s skip, scrub, next/previous), and
  `PlayerManager.nowPlayingArtwork` supplies the artwork. Off by default.
  `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter` are process-global, so
  the host's prior state is snapshotted and restored, and each command is
  enabled only when it would do something. Live streams publish no duration and
  set `MPNowPlayingInfoPropertyIsLiveStream`.
- `PlayerManager.isMuted` silences the backend without touching system volume.
  Every backend could already do this and none of them exposed it.
- `PlayerManager.autoplay` (default `true`, i.e. unchanged) controls whether
  loading an item also starts playing it.
- `PlayerManager.isBackgroundPlaybackEnabled` lets audio continue when the app
  is backgrounded. Off by default, because pausing in the background is part of
  PlayerKit's capture-protection posture. Requires `audio` in the host app's
  `UIBackgroundModes`, which a package cannot declare — see the README.

### Removed
- **Breaking:** the Dubber live-dubbing integration is removed. It had been
  inert behind `PlayerKitFeatureFlags.isDubberEnabled = false`, and that flag
  is removed with it. Gone from the public API: `Player`/`PlayerManager`'s
  `configureDubber(_:)`, `startDubbedPlayback(language:translateFrom:)`,
  `setDubLanguage(code:)`, `setDubSourceLanguage(code:)` and
  `stopDubbingAndReturnToOriginalAudio()`; the twelve public `@Published` dub
  properties; `PlayerKitError.dubberNotConfigured`, `.dubberSourceMissing` and
  `.dubberRequestFailed`; `PlayerItem.dubTitle`, including the parameter in
  both public initializers; and the `DubberConfiguration`,
  `DubberLanguageOption` and `DubberClient` types.
  No behaviour changes for hosts — every one of those was already a no-op with
  the flag off — but a call that silently did nothing is now a compile error.
  `PlayerManager` drops from 4,075 to 1,681 lines, 567 KB of bundled video
  leaves the consumer bundle, and complete-concurrency diagnostics fall from
  291 to 202.

### Changed
- `seek(to:)` always uses the backend's ordinary tolerant seek. The
  zero-tolerance precise path existed only for dubbed streams.
- `playerDidFail(with:)` no longer swallows `.mediaLoadFailed` while a dubbed
  master was loaded, so those failures now set `lastError` and post
  `.PlayerKitDidFail` like every other failure.

### Fixed (codebase audit)
- Playback time display dropped the hour component, rendering a 2h02m film as
  `122:05`. The UI now uses the hour-aware `PlayerKitTimeFormatter`, which also
  caches its `DateComponentsFormatter` instead of allocating one per call.
- `loadEpisodes(playerItems:currentIndex:)` stored an out-of-range index
  verbatim; a subsequent `playPrevious()` then trapped on an unguarded array
  subscript. The index is clamped and the subscript is guarded.
- Picture in Picture was inert on the AVPlayer backend: `setupPiP()` assigned
  `nil` and the capability flag was hard-coded `false`, so the already-complete
  `AVPictureInPictureControllerDelegate` conformance could never fire.
- Seeking was a silent no-op on live/DVR HLS, where `duration` is 0. Seeks now
  clamp into the backend's seekable window when no finite duration exists.
- Playback speed was stored in `AVPlayer.rate` (0 while paused) and so reset to
  1× on every resume. It is now held separately and re-applied on play.
- `play()` used `playImmediately(atRate:)`, which forces
  `automaticallyWaitsToMinimizeStalling` off — contradicting the load path's own
  documented anti-crackle behaviour.
- `SmoothPlayer` silently discarded the completion handler of any superseded
  seek, replayed queued seeks with the previous request's tolerances, and
  mutated its coalescing state from two threads unsynchronized.
- The seek completion handler wrote `@Published` state and mutated media
  selection from AVFoundation's queue instead of the main thread.
- The built-in Dub button forced the target language to Uzbek, defeating
  `setDubLanguage(code:)`.
- `DubberConfiguration.baseURL` no longer defaults to a live third-party
  endpoint; it is a required parameter.
- Dismissing the player left playback running, observers live, the diagnostics
  sampler ticking, and the audio session, idle-timer override, screen brightness
  and `GCController` handlers all still held. Added `PlayerManager.tearDown()`,
  called from `PlayerView.onDisappear`.
- Audio-session interruptions resumed playback the user had already paused.
- `AVAudioSession` was activated once and never deactivated.
- VLC backends: `bufferedDuration` reported the playhead rather than the buffer;
  `seek(to:)` fabricated a success result; delegate callbacks mutated observed
  state off the main thread; track identifiers were non-unique display names and
  the derived display name was empty for single-word tracks; playback speed
  reset on every load; the resume-position seek was untethered from its media.
- macOS VLC backend now checks `libvlc_get_version()` before binding symbols
  declared against the 3.x ABI, and uses `RTLD_LOCAL`.
- `MacOSPlaybackHealthMonitor.stop()` captured `self` in a `Task` and is
  reachable from `deinit`, resurrecting a deallocating object.
- Diagnostics report generation allocated an `ISO8601DateFormatter` per call,
  including inside sort comparators; date sorts now compare `Date` directly.
- Window capture-protection registry never pruned deallocated windows, so a
  reused `ObjectIdentifier` could pin a new window's `sharingType`.
- `DesktopVLCPlayerWrapper.stop()` left its 0.5s poll timer running.
- Removed always-true `#available` ladders whose fallback branches were
  unreachable, clearing the `buildLimitedAvailability` crash-risk warnings.
- The playback slider is now operable by VoiceOver via an adjustable action.
- CI builds and tests the macOS target, which compiles the ~9.7k-line
  `#if os(macOS)` diagnostics subsystem and runs its previously-unexercised tests.
- `verify_third_party_notices.sh` used `rg` while only checking for `awk`.

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
