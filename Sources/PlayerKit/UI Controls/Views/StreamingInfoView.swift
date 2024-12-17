import SwiftUI
import Combine

struct StreamingInfoView: View {
    @State var streamingInfo: StreamingInfo = .placeholder
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                Text("Video Bitrate: \(streamingInfo.videoBitrate)")
                Text("Buffer: \(streamingInfo.bufferDuration)")
                Text("Frame Rate: \(streamingInfo.frameRate)")
                Text("Resolution: \(streamingInfo.resolution)")
            }
        }
        .padding()
        .foregroundColor(.white)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
        .onAppear {
            PlayerManager.shared.userInteracted()
            updateStreamingInfo()
        }
        .onReceive(timer) { _ in
            updateStreamingInfo()
        }
    }
    
    private func updateStreamingInfo() {
        streamingInfo = PlayerManager.shared.fetchStreamingInfo()
    }
}
