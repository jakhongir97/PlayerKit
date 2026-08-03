import SwiftUI
import Combine

@MainActor
struct StreamingInfoView: View {
    @ObservedObject private var playerManager: PlayerManager
    @State var streamingInfo: StreamingInfo = .placeholder
    @State private var refreshTimer: AnyCancellable?
    
    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(playerManager.strings.bitrate, streamingInfo.videoBitrate)
            infoRow(playerManager.strings.buffer, streamingInfo.bufferDuration)
            infoRow(playerManager.strings.frameRate, streamingInfo.frameRate)
            infoRow(playerManager.strings.resolution, streamingInfo.resolution)
        }
        .padding(12)
        .glassBackgroundCompat(cornerRadius: 16)
        .onAppear {
            playerManager.userInteracted()
            updateStreamingInfo()
            startTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .PlayerKitControlsHidden)) { notification in
            if notification.object as? Bool == true {
                stopTimer()
            } else {
                startTimer()
            }
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
