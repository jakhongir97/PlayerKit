import SwiftUI

struct GestureView: View {
    @ObservedObject var gestureManager: GestureManager
    @State private var tapCount = 0
    @State private var tapTimer: Timer?
    let tapDelay = 0.3 // Delay to distinguish taps
    let fastSeekBaseInterval: Double = 10.0 // Base interval for fast seeking, e.g., 10 seconds

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if #available(iOS 17.0, *) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            handleTap(at: location, in: geometry)
                        }
                } else {
                    // Fallback on earlier versions
                }
                
                if gestureManager.showFeedback, let feedback = gestureManager.visualFeedback {
                    // Display the feedback (e.g., "+10s" or "-10s")
                    Text(feedback)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .position(x: feedbackPosition(in: geometry), y: geometry.size.height / 2)
                        .transition(.opacity)
                }
            }
        }
    }

    private func handleTap(at location: CGPoint, in geometry: GeometryProxy) {
        tapCount += 1
        tapTimer?.invalidate() // Cancel any ongoing timer

        // Start a new timer to handle single/double taps
        tapTimer = Timer.scheduledTimer(withTimeInterval: tapDelay, repeats: false) { _ in
            if tapCount == 1 {
                // Single tap, toggle controls
                gestureManager.handleToggleControls()
            } else {
                let tapLocationX = location.x // Get the exact x position of the tap
                let seekInterval = fastSeekBaseInterval * Double(tapCount - 1)

                if tapLocationX < geometry.size.width / 2 {
                    // Left side, rewind
                    gestureManager.handleDoubleTap(isRightSide: false, interval: seekInterval)
                } else {
                    // Right side, fast forward
                    gestureManager.handleDoubleTap(isRightSide: true, interval: seekInterval)
                }
            }
            resetTapState() // Reset the state after processing taps
        }
    }

    // Helper function to reset the tap state
    private func resetTapState() {
        tapCount = 0
        tapTimer?.invalidate()
        tapTimer = nil
    }

    // Adjust the position of the feedback on the screen
    private func feedbackPosition(in geometry: GeometryProxy) -> CGFloat {
        // If feedback is positive (right-side seek), position it on the right, otherwise left
        if gestureManager.visualFeedback?.contains("+") ?? false {
            return geometry.size.width - 100
        } else {
            return 100
        }
    }
}

