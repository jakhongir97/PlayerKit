# PlayerKit Integration (Dubber Instant Dub Polling)

This guide shows how to use PlayerKit with Dubber's updated backend flow:

1. `POST /api/instant-dub/start`
2. Poll `GET /api/instant-dub/{sessionId}/poll?after=-1` every 2 seconds
3. When the poll response returns `playable == true`, switch playback to `/api/instant-dub/{sessionId}/master.m3u8`
4. Let AVPlayer continue reloading `dub-audio.m3u8` as the HLS EVENT playlist grows
5. Stop polling when the poll response status becomes `complete`

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
    // 2) polls for Dubber state updates,
    // 3) swaps to master.m3u8 when the stream becomes playable.
}
```

## Built-in Dub UI Flow

When `DubberConfiguration` is set, PlayerKit displays a dubbing card in top controls:

- Tap `Start Dubbing` => `POST /api/instant-dub/start` with current media URL
- PlayerKit receives `session_id`
- PlayerKit polls `GET /api/instant-dub/{session_id}/poll?after=-1` every 2 seconds
- When `playable` becomes `true`, PlayerKit switches to `master.m3u8`
- While the session is still generating, the dubbed HLS EVENT playlist keeps growing and AVPlayer reloads it automatically
- When `status == "complete"`, PlayerKit stops polling
- Poll errors are exposed through `PlayerManager.dubWarningMessage` and `PlayerManager.lastError`

The built-in UI also shows:

- a 3-step dubbing explainer (`Hear`, `Build Voice`, `Play Dub`)
- target/source language selectors before a dub starts
- animated status while poll updates are arriving
- ETA hints once segment production is steady enough to estimate time remaining
- segment progress once Dubber reports `segments_ready`
- `Stop Dubbing` while generation is running and `Original Audio` after the dubbed stream is live
- recent activity logs derived from the polling state changes
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

- Playback starts from the original source stream immediately; dubbed master is applied once the poll response reports `playable == true`.
- Audio track availability depends on Dubber producing audio renditions in the generated master playlist.
- Once the dubbed master is loaded, AVPlayer handles reloading the growing `dub-audio.m3u8` EVENT playlist.
- Sessions are temporary; avoid persisting session IDs long-term.
