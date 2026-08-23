import SwiftUI
import Combine

@MainActor
struct StreamingInfoView: View {
    @ObservedObject private var playerManager: PlayerManager
    @State var streamingInfo: StreamingInfo
    @State private var refreshTimer: AnyCancellable?
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        _streamingInfo = State(initialValue: .placeholder(using: playerManager.strings))
    }

    /// Rows only: the options panel that hosts them draws the surface.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(playerManager.strings.bitrate, streamingInfo.videoBitrate)
            infoRow(playerManager.strings.buffer, streamingInfo.bufferDuration)
            infoRow(playerManager.strings.frameRate, streamingInfo.frameRate)
            infoRow(playerManager.strings.resolution, streamingInfo.resolution)
        }
        .onAppear {
            playerManager.userInteracted()
            updateStreamingInfo()
            startTimer()
        }
        .onDisappear { stopTimer() }
    }

    private func updateStreamingInfo() {
        streamingInfo = playerManager.fetchStreamingInfo()
    }

    private func startTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in updateStreamingInfo() }
    }

    private func stopTimer() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    // MARK: - UI
    @ViewBuilder
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text("\(title):")
                .font(.callout)
                .foregroundColor(.white.opacity(0.82))
            Spacer(minLength: 12)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundColor(.white)
                .monospacedDigitsCompat()
        }
    }
}
