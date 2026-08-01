# PlayerKit

PlayerKit is an iOS Swift Package for media playback with a ready-to-use SwiftUI player UI.

It supports:
- AVPlayer and VLCKit backends
- SwiftUI full-screen player controls
- Picture in Picture (requires the `audio` background mode and an active
  `.playback` audio session in the host app)
- Google Cast integration; AirPlay video routing is **opt-in** via
  `PlayerManager.isExternalPlaybackEnabled` (off by default, because PlayerKit
  configures `AVPlayer` for screen-capture protection)
- Audio/subtitle track selection
- A discoverable gesture layer: skip, volume, brightness, drag-to-scrub,
  speed hold, zoom, with on-screen feedback and a first-run walkthrough
- Accessibility labels, hints and an adjustable action on core playback controls

Not yet supported: localization (all user-facing strings are English; see
`HeuristicSkipButtonTitles` for the one injection seam), DRM/FairPlay, and
Dynamic Type in the player chrome.

## Requirements

- iOS 15.0+
- macOS 14.0+
- Xcode 15+
- Swift 5.10

## Installation (Swift Package Manager)

In Xcode, add package dependency:

`https://github.com/jakhongir97/PlayerKit`

Or in `Package.swift`:

```swift
.package(url: "https://github.com/jakhongir97/PlayerKit", from: "1.1.0")
```

## Quick Start

```swift
import SwiftUI
import PlayerKit

struct ContentView: View {
    private let player = PlayerKit.Player()

    var body: some View {
        player.makeView()
            .onAppear {
                player.load(url: URL(string: "https://example.com/video.m3u8")!)
                player.play()
            }
    }
}
```

You can also use `PlayerView(playerItem:)` directly if you prefer a view-first API.

## Lock Screen, Control Center and Background Audio

Both are **off by default** and additive — existing hosts are unaffected.

```swift
player.playerManager.isNowPlayingEnabled = true
player.playerManager.nowPlayingArtwork = UIImage(named: "poster")
```

`isNowPlayingEnabled` publishes title, subtitle, duration and elapsed time to
the lock screen and Control Center, and installs the system transport controls
(play, pause, toggle, 15-second skip, scrub, next/previous). `MPRemoteCommandCenter`
and `MPNowPlayingInfoCenter` are process-global, so PlayerKit snapshots whatever
the host had and restores it when the player goes away. Controls are enabled
only when they would do something: the scrubber follows the seekable window, and
next/previous follow `canPlayNextItem` / `canPlayPreviousItem`.

Live streams publish no total duration and set `MPNowPlayingInfoPropertyIsLiveStream`,
so the lock screen hides the scrubber rather than drawing a zero-length one.

PlayerKit does not download `PlayerItem.posterUrl` for artwork — that would mean
owning an image cache and a network policy. Supply a `UIImage`/`NSImage` via
`nowPlayingArtwork`.

### Background audio

```swift
player.playerManager.isBackgroundPlaybackEnabled = true
```

**This alone is not enough.** Background audio also needs the `audio` background
mode in *your app's* `Info.plist`, which a package cannot declare for you:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

Note that PlayerKit configures `AVPlayer` to pause in the background as part of
its capture-protection posture, alongside disabling external playback. Enabling
background playback is a deliberate relaxation of that posture. It affects the
AVFoundation backend only; the VLC backends are unaffected.

## Versioning and Stability

PlayerKit follows Semantic Versioning:
- Major (`X.0.0`): breaking public API changes
- Minor (`1.X.0`): backward-compatible features
- Patch (`1.1.X`): backward-compatible fixes

Public distribution is validated in CI with:
- package manifest validation
- binary artifact checksum verification
- iOS simulator/device builds

Internal architecture hardening includes:
- callback-based lifecycle/error propagation from player wrappers
- event-driven runtime state updates (with compatibility fallback polling)
- one manager instance threaded through the UI tree instead of views reaching
  for `PlayerManager.shared` directly

Known limitation: `PlayerManager` has a `private init`, so `.shared` is the only
instance that can exist. The `playerManager:` parameters on the views and view
models thread that one instance through the tree; they are not a seam for
substituting a different manager, and two simultaneous players are not supported.

Playback errors are surfaced through:
- `PlayerManager.shared.lastError`
- `Notification.Name.PlayerKitDidFail`, whose `object` is the `PlayerKitError`

## Gestures

Every gesture has on-screen feedback, an accessible equivalent, and a capability
that reports honestly when the platform cannot perform it.

| Gesture | Where | What it does |
|---|---|---|
| Single tap | anywhere | Show/hide the controls |
| Double tap, then keep tapping | outer 40% of either side | Skip ∓10s, accumulating |
| Vertical swipe | leading half, full height | Brightness |
| Vertical swipe | trailing half, full height | Volume |
| Horizontal drag | anywhere | Scrub, with fine-scrub tiers as you drag away from the axis |
| Long press (0.45s) | anywhere | 2× speed while held |
| Pinch | anywhere | Fit / fill |
| Two-finger tap | anywhere | Play / pause |
| Scroll wheel, arrow keys, space, `F` | macOS | The same actions |

Rails are anchored to the half the finger starts in and stay there for the life
of the touch, so a diagonal drag never switches control mid-gesture.

### Teaching them

Gestures nobody can see are gestures nobody uses. Four layers, cheapest first:

1. **Resting affordance** — a quiet track on each side while the controls are up.
2. **Arm on contact** — resting a finger on a half reveals that rail's current
   value at 55% opacity after 0.12s, before any travel. Lifting without moving is
   an ordinary tap that wrote nothing, so probing is free.
3. **First-run walkthrough** — on the first frame of playback, a ghost fingertip
   travels beside each rail with one line of copy. Under six seconds, no scrim,
   no modal, no pause, zero taps required. Performing the gesture while it is on
   screen hands the rail over live under the finger.
4. **Confusion nudge** — a one-line tip after a detectably failed attempt: a
   swipe that engaged and gave up, or three taps in one half by someone who has
   never swiped there.

Re-runnable at any time:

```swift
playerManager.showGestureCoach()   // ignores the "already seen" flag
playerManager.resetGestureCoach()  // clears every persisted coaching flag
```

### Configuration

```swift
playerManager.gestureConfiguration.volumeTarget = .system       // default .player
playerManager.gestureConfiguration.railMapping = .volumeLeading // default .brightnessLeading
playerManager.gestureConfiguration.brightnessMode = .overlayOnly // never touch the panel
playerManager.gestureConfiguration.coachPolicy = .disabled
playerManager.gestureConfiguration.isScrubGestureEnabled = false
```

`playerManager.gestureCapabilities` reports what is actually available right now,
so a host can hide an affordance rather than offer a control that does nothing.

### Accessibility

The walkthrough is never shown under VoiceOver, Switch Control or Voice Control —
teaching a swipe to someone who cannot emit one teaches nothing. They get the
equivalent instead: named actions on the video element, adjustable Volume and
Brightness rotor elements, visible ±10s buttons in the transport row, and
auto-hide is suppressed entirely so chrome does not vanish mid-scan.

## Lifecycle

Call `PlayerManager.tearDown()` when the player UI goes away. `PlayerView` does
this from `onDisappear`; hosts driving `PlayerManager` directly must call it
themselves. It stops playback and releases the resources PlayerKit acquires
process-wide: the shared `AVAudioSession`, the idle-timer override, screen
brightness, and `GCController` handlers.

## Release Management

- Changelog: `CHANGELOG.md`
- Release runbook: `RELEASE.md`
- Binary artifact verification script: `scripts/verify_binary_targets.sh`
- Third-party notice verification script: `scripts/verify_third_party_notices.sh`
- Simulator unit-test runner: `scripts/run_unit_tests.sh`

## Open Source Standards

- Contributing guide: `CONTRIBUTING.md`
- Code of Conduct: `CODE_OF_CONDUCT.md`
- Security policy: `SECURITY.md`
- Distribution notices: `NOTICE`
- Third-party dependency notices: `THIRD_PARTY_NOTICES.md`

## License

This repository is licensed under the MIT License. See `LICENSE`.

Third-party binary dependencies (`VLCKit` and `GoogleCast`) are distributed under their own licenses and terms. See `NOTICE` and review upstream license terms before redistribution.
