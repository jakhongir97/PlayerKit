import AVFoundation
import SwiftUI

struct DubberLoopingMediaView: View {
    enum Variant {
        case fullScene
        case heroFocus
    }

    let isPlaying: Bool
    let variant: Variant

    init(isPlaying: Bool, variant: Variant = .fullScene) {
        self.isPlaying = isPlaying
        self.variant = variant
    }

    var body: some View {
        Group {
            if let assetURL {
                PlatformLoopingDubberVideoView(url: assetURL, isPlaying: isPlaying)
            } else {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.02),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var assetURL: URL? {
        Bundle.module.url(
            forResource: resourceName,
            withExtension: "mp4",
            subdirectory: "Dubber"
        )
    }

    private var resourceName: String {
        switch variant {
        case .fullScene:
            return "dubber_waiting_loop"
        case .heroFocus:
            return "dubber_waiting_loop_focus"
        }
    }
}

#if canImport(UIKit)
private struct PlatformLoopingDubberVideoView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        context.coordinator.attach(url: url, isPlaying: isPlaying, to: view)
        return view
    }

    func updateUIView(_ uiView: AVPlayerView, context: Context) {
        context.coordinator.attach(url: url, isPlaying: isPlaying, to: uiView)
    }

    static func dismantleUIView(_ uiView: AVPlayerView, coordinator: Coordinator) {
        coordinator.detach(from: uiView)
    }
}
#else
private struct PlatformLoopingDubberVideoView: NSViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(frame: .zero)
        view.layer?.masksToBounds = true
        context.coordinator.attach(url: url, isPlaying: isPlaying, to: view)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.attach(url: url, isPlaying: isPlaying, to: nsView)
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.detach(from: nsView)
    }
}
#endif

private final class Coordinator {
    private var currentURL: URL?
    private var looper: AVPlayerLooper?
    private var player: AVQueuePlayer?
    private var isPlaying = false

    func attach(url: URL, isPlaying: Bool, to view: AVPlayerView) {
        if currentURL == url, let player {
            configure(view: view, with: player)
            updatePlayback(isPlaying, for: player)
            return
        }

        detach(from: view)

        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none

        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        currentURL = url
        self.player = player
        self.isPlaying = isPlaying

        configure(view: view, with: player)
        updatePlayback(isPlaying, for: player)
    }

    func detach(from view: AVPlayerView) {
        player?.pause()
        player?.removeAllItems()
        view.player = nil
        looper = nil
        player = nil
        currentURL = nil
    }

    private func configure(view: AVPlayerView, with player: AVPlayer) {
        view.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
    }

    private func updatePlayback(_ shouldPlay: Bool, for player: AVQueuePlayer) {
        isPlaying = shouldPlay
        if shouldPlay {
            player.play()
        } else {
            player.pause()
        }
    }
}
