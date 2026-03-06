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

## Built-in Dub UI Flow

When `DubberConfiguration` is set, PlayerKit displays a dubbing card in top controls:

- Tap `Start Dubbing` => `POST /api/instant-dub/start` with current media URL
- PlayerKit receives `session_id`
- PlayerKit subscribes to `GET /api/instant-dub/{session_id}/events`
- On `update` with enough `segments_ready`, PlayerKit switches to `master.m3u8`
- On `warning`, PlayerKit exposes the message through `PlayerManager.dubWarningMessage`
- On `done`, PlayerKit stops Dub loading state and closes SSE

The built-in UI also shows:

- a 3-step dubbing explainer (`Hear`, `Build Voice`, `Play Dub`)
- target/source language selectors before a dub starts
- animated status while SSE updates are arriving
- ETA hints once segment production is steady enough to estimate time remaining
- segment progress once Dubber reports `segments_ready`
- `Stop Dubbing` while generation is running and `Original Audio` after the dubbed stream is live
- recent activity logs derived from the live SSE stream
- a compact floating status pill when the main player controls are hidden

If Dubber is not configured, the dubbing UI is hidden.

## Optional Control APIs

If you want to drive the same controls yourself, PlayerKit also exposes:

- `setDubLanguage(code:)`
- `setDubSourceLanguage(code:)`
- `stopDubbingAndReturnToOriginalAudio()`

`DubberConfiguration` can also provide custom `supportedLanguages` and `supportedSourceLanguages` lists for the built-in UI.

## Observability Hooks

PlayerKit exposes Dubber runtime state on `PlayerManager`:

- `isDubLoading`
- `dubSessionID`
- `dubStatus`
- `dubProgressMessage`
- `dubSegmentsReady`
- `dubTotalSegments`
- `dubWarningMessage`
- `isDubbedPlaybackActive`

These can be bound directly in SwiftUI for translation progress/warning UI.

## Notes

- Playback starts from the original source stream immediately; dubbed master is applied when SSE progress indicates enough generated segments.
- Audio track availability depends on Dubber producing audio renditions in the generated master playlist.
- PlayerKit automatically retries transient SSE failures (for example, timeout `-1001`) with exponential backoff.
- Sessions are temporary; avoid persisting session IDs long-term.
