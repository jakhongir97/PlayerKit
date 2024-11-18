import SwiftUI

struct RotateButtonView: View {
    @State private var isLandscape: Bool = false  // Track orientation state

    var body: some View {
        Button(action: toggleOrientation) {
            Image(systemName: "rotate.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    private func toggleOrientation() {
        isLandscape.toggle()
        
        // Use the extension's method to change orientation
        if isLandscape {
            setDeviceOrientation(.landscapeRight)
        } else {
            setDeviceOrientation(.portrait)
        }
    }
}