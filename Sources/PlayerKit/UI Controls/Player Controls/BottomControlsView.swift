import SwiftUI

struct BottomControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    
    // Determine if the device is an iPhone
    private var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        VStack() {
            HStack {
                //PlaybackTimeView(playerManager: playerManager)
                MediaOptionsMenu()
                Spacer()
                if playerManager.selectedPlayerType == .avPlayer {
                    PiPButton()
                }
                if isIPhone {
                    RotateButtonView()
                }
            }

            PlaybackSliderView(playerManager: playerManager)
        }
    }
}
