import UIKit

public class GestureManager: ObservableObject {
    
    @Published var visualFeedback: String?  // Holds the current visual feedback text (e.g., "+10s", "-20s")
    @Published var showFeedback: Bool = false  // Controls the visibility of the feedback

    var onSeek: ((_ newTime: Double) -> Void)?
    var onToggleControls: (() -> Void)?

    // Handles the double-tap action for fast seeking based on tap count
    func handleDoubleTap(isRightSide: Bool, interval: Double) {
        if let currentPlayer = PlayerManager.shared.currentPlayer {
            let currentTime = currentPlayer.currentTime
            let newTime = isRightSide ? currentTime + interval : currentTime - interval
            PlayerManager.shared.seek(to: newTime)
            showVisualFeedback(isRightSide: isRightSide, interval: interval)
        }
    }

    // Handles the single tap action to toggle the controls
    func handleToggleControls() {
        onToggleControls?()
    }

    func showVisualFeedback(isRightSide: Bool, interval: Double) {
        let feedbackText = isRightSide ? "+\(Int(interval))s" : "-\(Int(interval))s"
        visualFeedback = feedbackText
        showFeedback = true
        
        // Hide the feedback after 1 second with animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.showFeedback = false
        }
    }
}
