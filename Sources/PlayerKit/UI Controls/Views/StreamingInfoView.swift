import SwiftUI
import Combine

struct StreamingInfoView: View {
    @State var streamingInfo: StreamingInfo = .placeholder
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow("Bitrate", streamingInfo.videoBitrate)
            infoRow("Buffer", streamingInfo.bufferDuration)
            infoRow("Frame Rate", streamingInfo.frameRate)
            infoRow("Resolution", streamingInfo.resolution)
        }
        .padding(12)
        .glassBackgroundCompat(cornerRadius: 16)
        .onAppear {
            PlayerManager.shared.userInteracted()
            updateStreamingInfo()
        }
        .onReceive(timer) { _ in updateStreamingInfo() }
    }

    private func updateStreamingInfo() {
        streamingInfo = PlayerManager.shared.fetchStreamingInfo()
    }

    // MARK: - UI
    @ViewBuilder
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text("\(title):")
                .font(.caption)                 // smaller text
                .foregroundColor(.gray)         // gray label
            Spacer(minLength: 12)
            Text(value)
                .font(.caption)                 // smaller text
                .foregroundColor(.white)        // white value
                .monospacedDigitsCompat()           // stable numerics
        }
    }
}
