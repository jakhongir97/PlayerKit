import SwiftUI

#if os(macOS)
import AppKit
#endif

@MainActor
struct FullscreenButtonView: View {
    @ObservedObject var playerManager: PlayerManager
    let isGrouped: Bool
    @State private var isFullscreen = false
    #if os(macOS)
    @State private var transitionState = PlayerKitMacFullscreenTransitionState()
    @State private var transitionRecoveryTask: Task<Void, Never>?
    @StateObject private var hostingWindowReference = PlayerKitHostingWindowReference()
    #endif

    init(playerManager: PlayerManager = .shared, isGrouped: Bool = false) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        self.isGrouped = isGrouped
    }

    var body: some View {
        #if os(macOS)
        Button(action: toggleFullscreen) {
            Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .playerBarItem(isGrouped: isGrouped, appearance: playerManager.appearance)
        }
        // Grouped, the glyph carries its own hover wash and lift; a second
        // lift from the style would compound to 1.06², so hover moves to
        // whichever layer owns the visible response.
        .buttonStyle(PlayerControlButtonStyle(hoverEnabled: !isGrouped))
        .accessibilityLabel(isFullscreen ? "Exit Full Screen" : "Enter Full Screen")
        .accessibilityHint("Toggles full screen for the player window")
        .accessibilityIdentifier("player.fullscreen")
        .disabled(transitionState.isInFlight)
        .background(
            PlayerKitHostingWindowReader { window in
                if hostingWindowReference.window !== window {
                    transitionRecoveryTask?.cancel()
                    transitionRecoveryTask = nil
                    hostingWindowReference.window = window
                    transitionState.finish()
                    refreshFullscreenState()
                }
            }
        )
        .onAppear(perform: refreshFullscreenState)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { notification in
            beginFullscreenTransition(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { notification in
            beginFullscreenTransition(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            finishFullscreenTransition(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            finishFullscreenTransition(from: notification)
        }
        .onDisappear {
            transitionRecoveryTask?.cancel()
            transitionRecoveryTask = nil
        }
        #else
        EmptyView()
        #endif
    }
}

#if os(macOS)
private extension FullscreenButtonView {
    var targetWindow: NSWindow? {
        PlayerKitMacWindowOwnership.fullscreenTarget(
            for: hostingWindowReference.window
        )
    }

    func toggleFullscreen() {
        playerManager.userInteracted()

        guard let window = targetWindow else { return }
        guard transitionState.begin() else { return }
        scheduleTransitionRecovery(for: window)
        PlayerKitMacFullscreenSupport.prepareForFullscreen(window)
        window.toggleFullScreen(nil)
    }

    func refreshFullscreenState() {
        isFullscreen = targetWindow?.styleMask.contains(.fullScreen) ?? false
    }

    func beginFullscreenTransition(from notification: Notification) {
        guard PlayerKitMacWindowOwnership.fullscreenNotificationTargets(
            notification,
            hostingWindow: hostingWindowReference.window
        ), let window = targetWindow else { return }
        _ = transitionState.begin()
        scheduleTransitionRecovery(for: window)
    }

    func finishFullscreenTransition(from notification: Notification) {
        guard PlayerKitMacWindowOwnership.fullscreenNotificationTargets(
            notification,
            hostingWindow: hostingWindowReference.window
        ), let window = targetWindow else { return }
        transitionRecoveryTask?.cancel()
        transitionRecoveryTask = nil
        transitionState.finish()
        refreshFullscreenState(window: window)
    }

    func scheduleTransitionRecovery(for window: NSWindow) {
        transitionRecoveryTask?.cancel()
        // ponytail: AppKit publishes completion but not failure notifications.
        // Reconcile after its normal animation window; replace with a delegate
        // bridge only if a future macOS transition can legitimately exceed 5s.
        transitionRecoveryTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, targetWindow === window else { return }
            transitionState.finish()
            refreshFullscreenState(window: window)
            transitionRecoveryTask = nil
        }
    }

    func refreshFullscreenState(window: NSWindow) {
        isFullscreen = window.styleMask.contains(.fullScreen)
    }
}

struct PlayerKitMacFullscreenTransitionState: Equatable {
    private(set) var isInFlight = false

    mutating func begin() -> Bool {
        guard !isInFlight else { return false }
        isInFlight = true
        return true
    }

    mutating func finish() {
        isInFlight = false
    }
}

@MainActor
private enum PlayerKitMacFullscreenSupport {
    static func prepareForFullscreen(_ window: NSWindow) {
        window.collectionBehavior = window.collectionBehavior.union([.fullScreenPrimary])
        window.styleMask = window.styleMask.union([.resizable])
    }
}
#endif
