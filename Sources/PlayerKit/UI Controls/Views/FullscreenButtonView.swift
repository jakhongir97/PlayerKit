import SwiftUI

#if os(macOS)
import AppKit
#endif

struct FullscreenButtonView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var isFullscreen = false

    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        #if os(macOS)
        Button(action: toggleFullscreen) {
            Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .circularGlassIcon()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFullscreen ? "Exit Full Screen" : "Enter Full Screen")
        .accessibilityHint("Toggles full screen for the player window")
        .accessibilityIdentifier("player.fullscreen")
        .onAppear(perform: refreshFullscreenState)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            refreshFullscreenState(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            refreshFullscreenState(from: notification)
        }
        #else
        EmptyView()
        #endif
    }
}

#if os(macOS)
private extension FullscreenButtonView {
    var targetWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    func toggleFullscreen() {
        playerManager.userInteracted()

        guard let window = targetWindow else { return }
        PlayerKitMacFullscreenSupport.prepareForFullscreen(window)
        window.toggleFullScreen(nil)
        refreshFullscreenState(window: window)
    }

    func refreshFullscreenState() {
        isFullscreen = targetWindow?.styleMask.contains(.fullScreen) ?? false
    }

    func refreshFullscreenState(from notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == targetWindow else { return }
        refreshFullscreenState(window: window)
    }

    func refreshFullscreenState(window: NSWindow) {
        isFullscreen = window.styleMask.contains(.fullScreen)
    }
}

private enum PlayerKitMacFullscreenSupport {
    static func prepareForFullscreen(_ window: NSWindow) {
        window.collectionBehavior = window.collectionBehavior.union([.fullScreenPrimary])
        window.styleMask = window.styleMask.union([.resizable])
    }
}
#endif
