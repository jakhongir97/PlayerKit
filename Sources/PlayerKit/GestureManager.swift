import Foundation
import SwiftUI

public class GestureManager: ObservableObject {
    
    var onSeek: ((Double) -> Void)?  // Closure to handle seeking
    var onToggleControls: (() -> Void)?  // Closure to handle control visibility toggle

    init() {}

    // Double tap gesture handler for seeking
    func handleDoubleTap(isRightSide: Bool) {
        let skipTime: Double = 10
        let playerManager = PlayerManager.shared
        let currentTime = playerManager.currentTime
        let duration = playerManager.duration
        
        let newTime = isRightSide ? min(currentTime + skipTime, duration) : max(currentTime - skipTime, 0)
        onSeek?(newTime)  // Trigger seek closure
    }

    // Handle control visibility toggle
    func handleToggleControls() {
        onToggleControls?()  // Trigger control visibility toggle closure
    }
}
