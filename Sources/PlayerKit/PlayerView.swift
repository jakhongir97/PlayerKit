import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct PlayerView: View {
    @ObservedObject var playerManager: PlayerManager
    @Environment(\.presentationMode) var presentationMode
    @State private var didBootstrapPlayer = false
    
    private let loadMode: LoadMode

    public init(playerItem: PlayerItem? = nil, playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        loadMode = .single(playerItem)
    }
    
    public init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        loadMode = .none
    }
    
    public init(playerItems: [PlayerItem], currentIndex: Int = 0, playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        loadMode = .episodes(playerItems, currentIndex)
    }

    public var body: some View {
        ZStack {
            // Full-screen PlayerRenderingView
            PlayerRenderingView(playerManager: playerManager)
                .id(playerManager.selectedPlayerType)
                .edgesIgnoringSafeArea(.all)

            // GestureView for handling gestures
            GestureView(gestureManager: playerManager.gestureManager)
                .zIndex(0)
                .edgesIgnoringSafeArea(.all)
            
            // Player controls
            PlayerControlsView(playerManager: playerManager)
                .transition(.opacity)
                .zIndex(1)
        }
        .onReceive(playerManager.$shouldDismiss) { shouldDismiss in
            if shouldDismiss {
                debugLog("Dismiss requested by player manager.")
                playerManager.shouldDismiss = false
                closePlayerPresentation()
                NotificationCenter.default.post(name: .PlayerKitDidClose, object: nil)
            }
        }
        .onAppear {
            debugLog(
                "Player view onAppear didBootstrap=\(didBootstrapPlayer) loadMode=\(loadMode.debugName)"
            )
            bootstrapPlayerIfNeeded()
        }
        .onDisappear {
            debugLog(
                "Player view onDisappear loadMode=\(loadMode.debugName) " +
                "isPlaying=\(playerManager.isPlaying) current=\(playerManager.currentTime)"
            )
        }
        .animation(.easeInOut(duration: 0.3), value: playerManager.areControlsVisible)
    }
    
    private func bootstrapPlayerIfNeeded() {
        guard !didBootstrapPlayer else {
            debugLog("Skipping bootstrap because it already ran for this view instance.")
            return
        }
        didBootstrapPlayer = true
        debugLog("Bootstrapping player view loadMode=\(loadMode.debugName)")
        
        playerManager.ensurePlayerConfigured()
        
        switch loadMode {
        case .none:
            debugLog("No initial player item was provided.")
            return
        case .single(let playerItem):
            guard let playerItem else {
                debugLog("Single-item load mode has no item.")
                return
            }
            debugLog("Loading single item title=\(playerItem.title) url=\(playerItem.url.debugDescription)")
            playerManager.load(playerItem: playerItem)
        case .episodes(let items, let index):
            debugLog("Loading episode list count=\(items.count) currentIndex=\(index)")
            playerManager.loadEpisodes(playerItems: items, currentIndex: index)
        }
    }

    private func closePlayerPresentation() {
#if os(macOS)
        if let keyWindow = NSApp.keyWindow {
            if let sheetParent = keyWindow.sheetParent {
                sheetParent.endSheet(keyWindow)
            } else {
                keyWindow.performClose(nil)
            }
            return
        }
#endif
        presentationMode.wrappedValue.dismiss()
    }

    private func debugLog(_ message: String) {
        print("[PlayerKit][PlayerView] \(message)")
    }
}

private extension PlayerView {
    enum LoadMode {
        case none
        case single(PlayerItem?)
        case episodes([PlayerItem], Int)

        var debugName: String {
            switch self {
            case .none:
                return "none"
            case .single:
                return "single"
            case .episodes:
                return "episodes"
            }
        }
    }
}
