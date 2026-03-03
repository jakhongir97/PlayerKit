import SwiftUI

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
                presentationMode.wrappedValue.dismiss()
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
}

private extension PlayerView {
    enum LoadMode {
        case none
        case single(PlayerItem?)
        case episodes([PlayerItem], Int)
    }
}
