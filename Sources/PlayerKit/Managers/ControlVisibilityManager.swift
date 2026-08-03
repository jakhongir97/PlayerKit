//
//  ControlVisibilityManager.swift
//  
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation
import Combine

@MainActor
class ControlVisibilityManager {
    private var autoHideTimer: AnyCancellable?
    private let visibilityDuration: TimeInterval = 10
    private weak var playerManager: PlayerManager?  // Weak reference to avoid retain cycles
    private let assistiveObserver = AssistiveTechnologyObserver()

    /// Initializes the manager with a reference to PlayerManager
    init(playerManager: PlayerManager) {
        self.playerManager = playerManager
        assistiveObserver.onChange = { [weak self] state in
            self?.assistiveTechnologyDidChange(state)
        }
    }

    /// Shows the controls and starts the auto-hide timer
    func showControls() {
        NotificationCenter.default.post(name: .PlayerKitControlsHidden, object: false)
        playerManager?.areControlsVisible = true
        startAutoHideTimer()
    }

    /// Hides the controls and stops the auto-hide timer
    func hideControls() {
        guard playerManager?.userInteracting == false else { return showControls() }
        NotificationCenter.default.post(name: .PlayerKitControlsHidden, object: true)
        playerManager?.areControlsVisible = false
        stopAutoHideTimer()
    }

    /// Starts the auto-hide timer, which hides controls after the specified duration
    ///
    /// Suppressed entirely under VoiceOver, Switch Control and Guided Access:
    /// chrome that disappears on a timer is unusable when navigating by focus,
    /// because the element you were about to reach stops existing mid-scan.
    private func startAutoHideTimer() {
        stopAutoHideTimer()  // Ensure no existing timer is running

        guard !resolvedAssistiveState.suppressesAutoHide else { return }

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

    /// Re-evaluates timer suppression after a host changes an assistive-state
    /// override that UIKit cannot report itself (currently Voice Control).
    func refreshAssistiveTechnologyState() {
        assistiveTechnologyDidChange(resolvedAssistiveState)
    }

    private func assistiveTechnologyDidChange(_ state: AssistiveTechnologyState) {
        var state = state
        if let override = playerManager?.voiceControlRunningOverride {
            state.isVoiceControlRunning = override
        }

        if state.suppressesAutoHide {
            // Keep focusable chrome present when an assistive technology starts
            // while a timer is already counting down or controls are hidden.
            showControls()
        } else if playerManager?.areControlsVisible == true {
            startAutoHideTimer()
        }
    }

    private var resolvedAssistiveState: AssistiveTechnologyState {
        var state = assistiveObserver.state
        if let override = playerManager?.voiceControlRunningOverride {
            state.isVoiceControlRunning = override
        }
        return state
    }
}
