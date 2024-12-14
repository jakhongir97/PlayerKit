import SwiftUI
import Combine

struct StreamingInfoView: View {
    @State var streamingInfo: StreamingInfo = .placeholder
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                Text("Server: \(streamingInfo.server)")
                Text("Bitrates: \(streamingInfo.bitrates.joined(separator: ", "))")
                Text("Loading Speed: \(streamingInfo.loadingSpeed)")
                Text("Buffer: \(streamingInfo.bufferDuration) sec")
            }
            Divider()
            Group {
                Text("Video Codec: \(streamingInfo.videoCodec)")
                Text("Resolution: \(streamingInfo.resolution)")
                Text("Video Bitrate: \(streamingInfo.videoBitrate)")
            }
            Divider()
            Group {
                Text("Audio Codec: \(streamingInfo.audioCodec)")
                Text("Track Name: \(streamingInfo.trackName)")
                Text("Channels: \(streamingInfo.channels)")
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
        .onDisappear() {
            PlayerManager.shared.userInteracting = false
        }
    }
    
    private func updateStreamingInfo() {
        streamingInfo = PlayerManager.shared.fetchStreamingInfo()
    }
}
