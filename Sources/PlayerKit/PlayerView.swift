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
                playerManager.shouldDismiss = false
                closePlayerPresentation()
                NotificationCenter.default.post(name: .PlayerKitDidClose, object: nil)
            }
        }
        .onAppear {
            bootstrapPlayerIfNeeded()
        }
        .animation(.easeInOut(duration: 0.3), value: playerManager.areControlsVisible)
    }
    
    private func bootstrapPlayerIfNeeded() {
        guard !didBootstrapPlayer else { return }
        didBootstrapPlayer = true
        
        playerManager.ensurePlayerConfigured()
        
        switch loadMode {
        case .none:
            return
        case .single(let playerItem):
            guard let playerItem else { return }
            playerManager.load(playerItem: playerItem)
        case .episodes(let items, let index):
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
}

private extension PlayerView {
    enum LoadMode {
        case none
        case single(PlayerItem?)
        case episodes([PlayerItem], Int)
    }
}
