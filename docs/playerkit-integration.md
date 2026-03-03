# PlayerKit Integration (Dubber HLS)

This guide shows how to use PlayerKit with Dubber's HLS proxy flow documented at:
[AzimjonNajmiddinov/dubber/docs/playerkit-integration.md](https://github.com/AzimjonNajmiddinov/dubber/blob/main/docs/playerkit-integration.md).

## Flow

1. Start a dub session (`POST /api/instant-dub/start`)
2. Build the master playlist URL (`/api/instant-dub/{sessionId}/master.m3u8`)
3. Load that URL into `PlayerKit.Player`
4. Let users switch to dubbed audio from PlayerKit's audio menu

## Minimal Example

```swift
import PlayerKit

func playDubbedHLS(sourceURL: URL) async throws {
    let sessionId = try await DubAPI.startSession(videoURL: sourceURL, language: "uz")
    let masterURL = DubAPI.masterPlaylistURL(sessionId: sessionId)

    let player = PlayerKit.Player()
    player.load(url: masterURL)
    player.play()
}
```

## SwiftUI Example

```swift
import PlayerKit
import SwiftUI

@MainActor
final class DubPlayerViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var status = "Starting..."

    let player = PlayerKit.Player()
    private var sessionId: String?

    func start(sourceURL: URL) {
        Task {
            do {
                let sid = try await DubAPI.startSession(videoURL: sourceURL)
                sessionId = sid

                let masterURL = DubAPI.masterPlaylistURL(sessionId: sid)
                player.load(url: masterURL)
                player.play()

                isLoading = false
                status = "Playing"
            } catch {
                status = "Failed: \(error.localizedDescription)"
            }
        }
    }

    func stopSessionIfNeeded() {
        guard let sessionId else { return }
        Task { try? await DubAPI.stop(sessionId: sessionId) }
    }
}

struct DubPlayerScreen: View {
    @StateObject private var viewModel = DubPlayerViewModel()

    var body: some View {
        ZStack {
            viewModel.player.makeView()
                .ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView(viewModel.status)
            }
        }
        .onAppear {
            let url = URL(string: "https://example.com/master.m3u8")!
            viewModel.start(sourceURL: url)
        }
        .onDisappear {
            viewModel.stopSessionIfNeeded()
        }
    }
}
```

## DubAPI Helper

```swift
import Foundation

enum DubAPI {
    static let baseURL = "https://dubbing.uz/api/instant-dub"

    struct StartResponse: Decodable {
        let session_id: String
    }

    struct PollResponse: Decodable {
        let status: String
        let segments_ready: Int
        let total_segments: Int
        let error: String?
    }

    static func startSession(
        videoURL: URL,
        language: String = "uz",
        translateFrom: String = "auto"
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/start")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "video_url": videoURL.absoluteString,
            "language": language,
            "translate_from": translateFrom
        ]

        request.httpBody = try JSONEncoder().encode(payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(StartResponse.self, from: data).session_id
    }

    static func masterPlaylistURL(sessionId: String) -> URL {
        URL(string: "\(baseURL)/\(sessionId)/master.m3u8")!
    }

    static func poll(sessionId: String) async throws -> PollResponse {
        let url = URL(string: "\(baseURL)/\(sessionId)/poll")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(PollResponse.self, from: data)
    }

    static func stop(sessionId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(sessionId)/stop")!)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }
}
```

## Notes

- Audio track availability depends on Dubber producing the first audio segments.
- Use `poll` only for progress UI; playback does not require polling.
- Call `stop` when users leave playback to release server-side session resources.
- Sessions are temporary; avoid persisting session IDs long-term.
