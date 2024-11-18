import SwiftUI

struct PlaybackSpeedMenu: View {
    @ObservedObject var viewModel = PlaybackSpeedViewModel()

    var body: some View {
        Menu {
            Section(header: Text("Playback Speed")) {
                speedOption(0.25)
                speedOption(0.5)
                speedOption(1.0, label: "1.0x (Normal)")
                speedOption(1.25)
                speedOption(1.5)
            }
        } label: {
            Image(systemName: "gauge.with.needle.fill")
                .resizable()
                .foregroundColor(.white)
                .frame(width: 25, height: 25)
        }
        .onAppear {
            viewModel.userInteracted()
        }
    }

    private func speedOption(_ speed: Float, label: String? = nil) -> some View {
        Button(action: {
            viewModel.setPlaybackSpeed(speed)
        }) {
            HStack {
                Text(label ?? "\(speed)x")
                if viewModel.playbackSpeed == speed {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}
