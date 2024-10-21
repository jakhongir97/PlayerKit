import SwiftUI

struct GestureView: View {
    @ObservedObject var gestureManager: GestureManager

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Double-tap to seek gesture (left or right)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded { _ in
                                let tapLocation = geometry.frame(in: .global).midX  // Get tap location
                                if tapLocation < geometry.size.width / 2 {
                                    gestureManager.handleDoubleTap(isRightSide: false)
                                } else {
                                    gestureManager.handleDoubleTap(isRightSide: true)
                                }
                            }
                    )

                // Single tap to show/hide controls
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        TapGesture(count: 1)
                            .onEnded {
                                gestureManager.handleToggleControls()
                            }
                    )
                    .zIndex(2)
            }
        }
    }
}

