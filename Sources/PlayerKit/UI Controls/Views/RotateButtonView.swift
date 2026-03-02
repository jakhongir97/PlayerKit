import SwiftUI

struct RotateButtonView: View {
    private let playerManager: PlayerManager
    @State private var isLandscape: Bool = false  // Track orientation state
    
    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
    }

    var body: some View {
        Button(action: toggleOrientation) {
            Image(systemName: "rotate.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
        }
        .accessibilityLabel("Rotate player")
        .accessibilityHint("Toggles between portrait and landscape")
        .accessibilityIdentifier("player.rotate")
    }
    
    private func toggleOrientation() {
        isLandscape.toggle()
        
        // Use the extension's method to change orientation
        if isLandscape {
            setDeviceOrientation(.landscapeRight)
        } else {
            setDeviceOrientation(.portrait)
            playerManager.setGravityToDefault()
        }
    }
}
