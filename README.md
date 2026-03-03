# PlayerKit

PlayerKit is an iOS Swift Package for media playback with a ready-to-use SwiftUI player UI.

It supports:
- AVPlayer and VLCKit backends
- SwiftUI full-screen player controls
- Picture in Picture
- AirPlay and Google Cast integration
- Audio/subtitle track selection
- Gesture-based seeking, brightness, and volume controls
- Accessibility labels/hints on core playback controls

## Requirements

- iOS 14.0+
- Xcode 15+
- Swift 5

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

## Dubber Integration

- Integration guide: [`docs/playerkit-integration.md`](docs/playerkit-integration.md)
- Upstream reference: [dubber/docs/playerkit-integration.md](https://github.com/AzimjonNajmiddinov/dubber/blob/main/docs/playerkit-integration.md)

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
- reduced singleton coupling in cast/audio/gesture/orientation managers
- dependency injection support for player views and menu viewmodels

Playback errors are surfaced through:
- `PlayerManager.shared.lastError`
- `Notification.Name.PlayerKitDidFail`

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
