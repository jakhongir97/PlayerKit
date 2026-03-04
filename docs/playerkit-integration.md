# PlayerKit Integration (Dubber HLS + SSE)

This guide shows how to use PlayerKit with Dubber's updated backend flow:

1. `POST /api/instant-dub/start`
2. `GET /api/instant-dub/{sessionId}/events` (SSE)
3. Wait for `update` events with enough `segments_ready`
4. Switch playback to `/api/instant-dub/{sessionId}/master.m3u8`
5. Close the SSE stream on `done`

## Minimal Example

```swift
import PlayerKit

func playDubbedHLS(sourceURL: URL) {
    let player = PlayerKit.Player()
    player.configureDubber(DubberConfiguration())
    player.load(url: sourceURL)
    player.play()

    // User taps the Dub button in PlayerKit controls.
    // PlayerKit:
    // 1) starts a dub session,
    // 2) listens to SSE updates,
    // 3) swaps to master.m3u8 when dubbed segments are ready.
}
```

## Built-in Dub Button Flow

When `DubberConfiguration` is set, PlayerKit displays a Dub button in top controls:

- Tap button => `POST /api/instant-dub/start` with current media URL
- PlayerKit receives `session_id`
- PlayerKit subscribes to `GET /api/instant-dub/{session_id}/events`
- On `update` with enough `segments_ready`, PlayerKit switches to `master.m3u8`
- On `warning`, PlayerKit exposes the message through `PlayerManager.dubWarningMessage`
- On `done`, PlayerKit stops Dub loading state and closes SSE

If Dubber is not configured, the button is hidden.

## Observability Hooks

PlayerKit exposes Dubber runtime state on `PlayerManager`:

- `isDubLoading`
- `dubSessionID`
- `dubStatus`
- `dubProgressMessage`
- `dubSegmentsReady`
- `dubTotalSegments`
- `dubWarningMessage`

These can be bound directly in SwiftUI for translation progress/warning UI.

## Notes

- Playback starts from the original source stream immediately; dubbed master is applied when SSE progress indicates enough generated segments.
- Audio track availability depends on Dubber producing audio renditions in the generated master playlist.
- PlayerKit automatically retries transient SSE failures (for example, timeout `-1001`) with exponential backoff.
- Sessions are temporary; avoid persisting session IDs long-term.
