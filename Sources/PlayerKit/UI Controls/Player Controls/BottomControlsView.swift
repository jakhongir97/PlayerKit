import SwiftUI

struct BottomControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    
    // Determine if the device is an iPhone
    private var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        HStack() {
            MediaOptionsMenu()
            BufferingIndicatorView(playerManager: playerManager)
            Spacer()
            PiPButton()
            if isIPhone {
                RotateButtonView()
            }
        }
    }
}
