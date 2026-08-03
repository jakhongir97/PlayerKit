import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct PlayerPresentationPolicy: Equatable, Sendable {
    public let showsPlaybackSpeedControl: Bool
    public let showsPlaybackQualityControl: Bool
    public let showsPlaybackEndedOverlay: Bool

    public init(
        showsPlaybackSpeedControl: Bool = true,
        showsPlaybackQualityControl: Bool = true,
        showsPlaybackEndedOverlay: Bool = true
    ) {
        self.showsPlaybackSpeedControl = showsPlaybackSpeedControl
        self.showsPlaybackQualityControl = showsPlaybackQualityControl
        self.showsPlaybackEndedOverlay = showsPlaybackEndedOverlay
    }
}

@MainActor
public struct PlayerView: View {
    @ObservedObject var playerManager: PlayerManager
    @Environment(\.presentationMode) var presentationMode
    @State private var loadedInput: LoadIdentity?
    @State private var announcedError: PlayerKitError?
    @State private var announcedErrorWasTerminal = false
    #if os(iOS)
    @StateObject private var thumbnailPreviewController = WebVTTThumbnailPreviewController()
    #endif
    
    private let loadMode: LoadMode
    /// Disable only when the embedding host pauses temporary disappearances and
    /// calls `PlayerManager.tearDown()` when its presentation actually exits.
    let automaticallyTearsDownOnDisappear: Bool
    let presentationPolicy: PlayerPresentationPolicy

    public init(
        playerItem: PlayerItem? = nil,
        playerManager: PlayerManager = .shared,
        automaticallyTearsDownOnDisappear: Bool = true,
        presentationPolicy: PlayerPresentationPolicy = .init()
    ) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        loadMode = .single(playerItem)
        self.automaticallyTearsDownOnDisappear = automaticallyTearsDownOnDisappear
        self.presentationPolicy = presentationPolicy
    }
    
    public init(
        playerManager: PlayerManager = .shared,
        automaticallyTearsDownOnDisappear: Bool = true,
        presentationPolicy: PlayerPresentationPolicy = .init()
    ) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        loadMode = .none
        self.automaticallyTearsDownOnDisappear = automaticallyTearsDownOnDisappear
        self.presentationPolicy = presentationPolicy
    }
    
    public init(
        playerItems: [PlayerItem],
        currentIndex: Int = 0,
        playerManager: PlayerManager = .shared,
        automaticallyTearsDownOnDisappear: Bool = true,
        presentationPolicy: PlayerPresentationPolicy = .init()
    ) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        loadMode = .episodes(playerItems, currentIndex)
        self.automaticallyTearsDownOnDisappear = automaticallyTearsDownOnDisappear
        self.presentationPolicy = presentationPolicy
    }

    public var body: some View {
        ZStack {
            // Full-screen PlayerRenderingView
            // Keyed on the player *instance*, not on its type. A new wrapper —
            // and so a new player view — is built by every `resetPlayer` +
            // `setupPlayer` pair, including ones that keep the same backend
            // (`setPlayer()` with the current type, `ensurePlayerConfigured`).
            // Keying on the type meant SwiftUI held the previous backend's view
            // through those, and only picked the new one up if an unrelated
            // publish happened to drive `updateUIView` afterwards.
            PlayerRenderingView(playerManager: playerManager)
                .id(playerManager.playerGeneration)
                .edgesIgnoringSafeArea(.all)

            #if os(iOS)
            WebVTTThumbnailPreviewOverlay(controller: thumbnailPreviewController)
            #endif

            // The gesture surface: touch host, HUD, affordances and coaching.
            GestureSurface(manager: playerManager.gestureManager)
                .zIndex(0)
                .edgesIgnoringSafeArea(.all)
                .accessibilityHidden(hasBlockingStatus)
            
            // Player controls
            playerControls
                .transition(.opacity)
                .zIndex(1)
                .accessibilityHidden(hasBlockingStatus)

            // Buffering is transport state, not chrome. It must remain visible
            // after controls auto-hide or while the player is locked.
            if playerManager.isBuffering && !hasBlockingStatus {
                VStack {
                    BufferingIndicatorView(playerManager: playerManager)
                        .padding(.top, 52)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .zIndex(2)
            }

            if playerManager.isVideoEnded && presentationPolicy.showsPlaybackEndedOverlay {
                PlaybackEndedOverlayView(playerManager: playerManager)
                    .zIndex(3)
            }

            if let error = playerManager.lastError {
                PlaybackRecoveryOverlayView(playerManager: playerManager, error: error)
                    .zIndex(4)
            }
        }
        .onReceive(playerManager.$shouldDismiss) { shouldDismiss in
            if shouldDismiss {
                debugLog("Dismiss requested by player manager.")
                playerManager.shouldDismiss = false
                closePlayerPresentation()
                NotificationCenter.default.post(name: .PlayerKitDidClose, object: nil)
            }
        }
        #if os(iOS)
        .onReceive(playerManager.$playerItem) { item in
            // Treat every publication as a new owner, even when a signed VTT
            // URL happens to be reused across two item generations.
            thumbnailPreviewController.replaceOwner(sourceURL: item?.thumbnailVTTURL)
        }
        #endif
        .onAppear {
            #if os(iOS)
            thumbnailPreviewController.resumeIfNeeded(
                sourceURL: playerManager.playerItem?.thumbnailVTTURL
            )
            #endif
            debugLog(
                "Player view onAppear loadedInput=\(loadedInput != nil) loadMode=\(loadMode.debugName)"
            )
            bootstrapPlayerIfNeeded()
        }
        .onReceive(playerManager.$lastError) { error in
            guard let error else {
                announcedError = nil
                announcedErrorWasTerminal = false
                return
            }
            guard announcedError != error
                    || announcedErrorWasTerminal != playerManager.isPlaybackErrorTerminal else { return }
            announcedError = error
            announcedErrorWasTerminal = playerManager.isPlaybackErrorTerminal
            let presentation = PlaybackErrorPresentation(
                error,
                terminalPlaybackFailure: playerManager.isPlaybackErrorTerminal,
                strings: playerManager.strings
            )
            GestureAnnouncer.announce(
                "\(presentation.title). \(presentation.message)",
                state: playerManager.gestureManager.assistiveState
            )
        }
        .compatOnChange(of: loadMode.identity) { _ in
            // SwiftUI preserves @State while replacing a value-type view at the
            // same identity. Follow the input rather than the view instance so a
            // mounted player cannot keep showing the previous item or queue.
            bootstrapPlayerIfNeeded()
        }
        .onDisappear {
            #if os(iOS)
            thumbnailPreviewController.suspend()
            #endif
            debugLog(
                "Player view onDisappear loadMode=\(loadMode.debugName) " +
                "isPlaying=\(playerManager.isPlaying) current=\(playerManager.currentTime)"
            )
            guard automaticallyTearsDownOnDisappear else {
                debugLog("Host owns player teardown; preserving the active session.")
                return
            }
            // Dismissing the player used to leave playback running, the
            // periodic time observer firing, the diagnostics sampler ticking,
            // and the idle timer / audio session / brightness / controller
            // handlers all still held.
            playerManager.tearDown()
            loadedInput = nil
        }
        .animation(.easeInOut(duration: 0.3), value: playerManager.areControlsVisible)
    }

    var hasBlockingStatus: Bool {
        if playerManager.isVideoEnded && presentationPolicy.showsPlaybackEndedOverlay { return true }
        guard let error = playerManager.lastError else { return false }
        return PlaybackErrorPresentation(
            error,
            terminalPlaybackFailure: playerManager.isPlaybackErrorTerminal,
            strings: playerManager.strings
        ).blocksPlayback
    }

    @ViewBuilder
    private var playerControls: some View {
        #if os(iOS)
        PlayerControlsView(
            playerManager: playerManager,
            thumbnailPreviewController: thumbnailPreviewController,
            presentationPolicy: presentationPolicy
        )
        #else
        PlayerControlsView(
            playerManager: playerManager,
            presentationPolicy: presentationPolicy
        )
        #endif
    }
    
    private func bootstrapPlayerIfNeeded() {
        let input = loadMode.identity
        guard loadedInput != input else {
            debugLog("Skipping bootstrap because this input is already loaded.")
            return
        }
        loadedInput = input
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
            debugLog(
                "Loading single item title_present=\(!playerItem.title.isEmpty) source_present=true"
            )
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

    private func debugLog(_ message: @autoclosure () -> String) {
        PlayerKitLog.debug("PlayerView", message())
    }
}

extension PlayerView {
    enum LoadMode {
        case none
        case single(PlayerItem?)
        case episodes([PlayerItem], Int)

        var identity: LoadIdentity {
            switch self {
            case .none:
                return .none
            case .single(let item):
                return .single(item.map(ItemIdentity.init))
            case .episodes(let items, let index):
                return .episodes(items.map(ItemIdentity.init), index)
            }
        }

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

    enum LoadIdentity: Hashable {
        case none
        case single(ItemIdentity?)
        case episodes([ItemIdentity], Int)
    }

    /// Value identity for every input that affects a load. URLs alone are not
    /// sufficient: hosts commonly reuse one URL while changing resume position,
    /// external-playback metadata, or the episode represented by it.
    struct ItemIdentity: Hashable {
        let title: String
        let titleImageURL: URL?
        let description: String?
        let url: URL
        let urlAssetIdentifier: ObjectIdentifier?
        let posterURL: URL?
        let thumbnailVTTURL: URL?
        let castVideoURL: URL?
        let externalPlaybackURL: URL?
        let externalPlaybackContentType: String?
        let externalPlaybackDurationBits: UInt64?
        let lastPositionBits: UInt64?
        let episodeIndex: Int?
        #if os(macOS)
        let playbackHealthAssetIdentifier: String?
        let playbackHealthMonitoringEligible: Bool
        #endif

        init(_ item: PlayerItem) {
            title = item.title
            titleImageURL = item.titleImageURL
            description = item.description
            url = item.url
            urlAssetIdentifier = item.urlAsset.map { ObjectIdentifier($0) }
            posterURL = item.posterUrl
            thumbnailVTTURL = item.thumbnailVTTURL
            castVideoURL = item.castVideoUrl
            externalPlaybackURL = item.externalPlaybackURL
            externalPlaybackContentType = item.externalPlaybackContentType
            externalPlaybackDurationBits = item.externalPlaybackDuration?.bitPattern
            lastPositionBits = item.lastPosition?.bitPattern
            episodeIndex = item.episodeIndex
            #if os(macOS)
            playbackHealthAssetIdentifier = item.playbackHealthAssetIdentifier
            playbackHealthMonitoringEligible = item.playbackHealthMonitoringEligible
            #endif
        }
    }
}
