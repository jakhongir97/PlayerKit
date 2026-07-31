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
- Gesture-based seeking, brightness, and volume controls
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
