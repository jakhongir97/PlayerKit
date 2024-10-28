//
//  ControlVisibilityManager.swift
//  
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation
import Combine

class ControlVisibilityManager {
    private var autoHideTimer: AnyCancellable?
    private let visibilityDuration: TimeInterval = 10
    private weak var playerManager: PlayerManager?  // Weak reference to avoid retain cycles

    /// Initializes the manager with a reference to PlayerManager
    init(playerManager: PlayerManager) {
        self.playerManager = playerManager
    }

    /// Shows the controls and starts the auto-hide timer
    func showControls() {
        playerManager?.areControlsVisible = true
        startAutoHideTimer()
    }

    /// Hides the controls and stops the auto-hide timer
    func hideControls() {
        playerManager?.areControlsVisible = false
        stopAutoHideTimer()
    }

    /// Starts the auto-hide timer, which hides controls after the specified duration
    private func startAutoHideTimer() {
        stopAutoHideTimer()  // Ensure no existing timer is running

        autoHideTimer = Timer.publish(every: visibilityDuration, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.hideControls()
            }
    }

    /// Stops the auto-hide timer
    private func stopAutoHideTimer() {
        autoHideTimer?.cancel()
        autoHideTimer = nil
    }

    /// Resets visibility by showing the controls, useful for user interactions
    func userInteracted() {
        showControls()
    }
}
