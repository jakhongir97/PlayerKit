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
                Text("Resolution: \(streamingInfo.resolution)")
                Text("Frame Rate: \(streamingInfo.frameRate)")
            }
        }
        .padding()
        .foregroundColor(.white)
        .cornerRadius(16)
        .onAppear {
            PlayerManager.shared.userInteracting = true
            updateStreamingInfo()
        }
        .onReceive(timer) { _ in
            updateStreamingInfo()
        }
        .onDisappear {
            PlayerManager.shared.userInteracting = false
        }
    }
    
    private func updateStreamingInfo() {
        streamingInfo = PlayerManager.shared.fetchStreamingInfo()
    }
}
