import Foundation
import Combine
#if os(macOS)
import OSLog

private let playbackDiagnosticsLifecycleLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.netco.itv",
    category: "PlaybackHealth"
)
#endif

public enum PlayerEpisodeNavigationDirection: Equatable {
    case previous
    case next
}

/// Titles for the heuristic skip controls. PlayerKit ships no string tables, so a
/// localized host injects its own copy here; the English defaults keep every other
/// host rendering exactly what it rendered before this seam existed.
public struct HeuristicSkipButtonTitles: Equatable {
    public var skipIntro: String
    public var skipOutro: String
    public var nextEpisode: String

    public init(
        skipIntro: String = "Skip Intro",
        skipOutro: String = "Skip Outro",
        nextEpisode: String = "Next Episode"
    ) {
        self.skipIntro = skipIntro
        self.skipOutro = skipOutro
        self.nextEpisode = nextEpisode
    }
}

@MainActor
public class PlayerManager: ObservableObject {
    public static let shared = PlayerManager()

    #if os(macOS)
    public var isPlaybackHealthMonitoringEnabled = false
    public var onPlaybackHealthEvent: ((PlaybackHealthEvent) -> Void)?
    @Published private(set) var recentPlaybackHealthEvents: [PlaybackHealthEvent] = []
    private var playbackDiagnosticsSession = PlaybackDiagnosticsSessionReducer()
    private var playbackDiagnosticsSampleCancellable: AnyCancellable?
    private var playbackDiagnosticsLastSnapshot: PlaybackDiagnosticsSnapshot?
    private var playbackHealthEventsReceivedCount = 0
    private var playbackHealthEventsDroppedCount = 0
    private var playbackHealthEventsClearedCount = 0

    var hasActivePlaybackDiagnosticsItem: Bool {
        playbackDiagnosticsSampleCancellable != nil
    }
    #endif
    
    // State management
    @Published public internal(set) var isPlaying: Bool = false {
        didSet {
            guard oldValue != isPlaying else { return }
            refreshPlaybackWakeLock()
            refreshNowPlayingInfo()
            notifyGesturePlaybackStartedIfNeeded()
        }
    }
    @Published public internal(set) var isBuffering: Bool = false {
        didSet {
            guard oldValue != isBuffering else { return }
            refreshPlaybackWakeLock()
        }
    }
    @Published public private(set) var isPlaybackRequested: Bool = false
    @Published public internal(set) var currentTime: Double = 0
    @Published public internal(set) var duration: Double = 0
    @Published public internal(set) var bufferedDuration: Double = 0
    @Published public private(set) var playbackSpeed: Float = 1.0
    @Published public var suppressesHeuristicSkipButtons: Bool = false
    @Published public var heuristicSkipButtonTitles = HeuristicSkipButtonTitles()
    @Published var isSeeking: Bool = false
    @Published var isCasting: Bool = false
    @Published public internal(set) var isPiPActive: Bool = false
    @Published public internal(set) var isCastingAvailable: Bool = false
    @Published var areControlsVisible: Bool = true
    @Published var isLocked: Bool = false {
        didSet {
            guard oldValue != isLocked else { return }
            NotificationCenter.default.post(name: .PlayerKitLocked, object: isLocked)
            gestureManager.refreshAccessibilityState()
        }
    }
    @Published var userInteracting: Bool = false
    /// Mirrors `GestureManager`'s seek session, flipping only when one opens or
    /// closes.
    ///
    /// The controls read it from here rather than observing the gesture manager
    /// directly: that manager republishes on every tap so the overlay can move
    /// its ripple, and `@ObservedObject` wakes its view for any change, so the
    /// whole controls tree was re-evaluating several times a second for a flag
    /// that changes twice a session.
    @Published private(set) var isDoubleTapSeeking: Bool = false

    // Track identifiers
    @Published public internal(set) var selectedAudio: TrackInfo?
    @Published public internal(set) var selectedSubtitle: TrackInfo?
    @Published public internal(set) var availableAudioTracks: [TrackInfo] = []
    @Published public internal(set) var availableSubtitles: [TrackInfo] = []
    private var savedAudio: TrackInfo?
    private enum SavedSubtitleSelection {
        case unchanged
        case disabled
        case selected(TrackInfo)
    }
    private var savedSubtitleSelection: SavedSubtitleSelection = .unchanged
    
    @Published var selectedPlayerType: PlayerType = PlayerType.resolved(UserDefaults.standard.loadPlayerType()) {
        didSet {
            let resolvedType = PlayerType.resolved(selectedPlayerType)
            if resolvedType != selectedPlayerType {
                selectedPlayerType = resolvedType
                return
            }
            UserDefaults.standard.savePlayerType(selectedPlayerType)
        }
    }
    @Published private(set) var activeBuiltInPlayerType: PlayerType?
    @Published var playerItem: PlayerItem?
    @Published var playerItems: [PlayerItem] = []
    @Published var currentPlayerItemIndex: Int = 0
    @Published public var contentType: PlayerContentType = .movie
    @Published public private(set) var externalEpisodeCanPlayPrevious: Bool = false
    @Published public private(set) var externalEpisodeCanPlayNext: Bool = false
    @Published public private(set) var isExternalEpisodeNavigationInProgress: Bool = false
    @Published var shouldDismiss: Bool = false {
        didSet {
            guard shouldDismiss else {
                refreshPlaybackWakeLock()
                refreshNowPlayingInfo()
                return
            }
            #if os(macOS)
            endPlaybackDiagnosticsSampling(reason: "player dismissed")
            #endif
            playbackManager?.stop()
            cancelPendingPlaybackResume()
            shouldResumePlaybackAfterStall = false
            isPlaying = false
            isBuffering = false
            AudioSessionManager.shared.deactivateAudioSession(for: self)
            refreshPlaybackWakeLock()
            refreshNowPlayingInfo()
        }
    }
    @Published public private(set) var lastError: PlayerKitError?
    @Published public private(set) var isPlaybackErrorTerminal = false
    @Published public private(set) var isRetryingPlayback = false
    @Published public internal(set) var isMediaReady: Bool = false {
        didSet {
            if isMediaReady {
                refreshTrackInfo()
                NotificationCenter.default.post(name: .PlayerKitMediaReady, object: nil)
                notifyGesturePlaybackStartedIfNeeded()
            }
        }
    }
    @Published public internal(set) var isVideoEnded: Bool = false {
        didSet {
            refreshPlaybackWakeLock()
            refreshNowPlayingInfo()
        }
    }
    
    // Managers for different responsibilities
    var playbackManager: PlaybackManager?
    var trackManager: TrackManager?
    lazy var castManager = CastManager.shared
    let gestureManager = GestureManager()
    private var didNotifyGesturePlaybackStart = false
    let orientationManager = OrientationManager()
    
    // Lazy initialization for controlVisibilityManager
    lazy var controlVisibilityManager: ControlVisibilityManager = {
        ControlVisibilityManager(playerManager: self)
    }()
    
    private var currentProvider: PlayerProvider?
    public internal(set) weak var currentPlayer: PlayerProtocol? {
        didSet {
            // Bump *before* the other refreshes so anything they trigger already
            // sees the new generation.
            playerGeneration &+= 1
            gestureManager.refreshCapabilities()
            gestureManager.refreshAccessibilityState()
            refreshPlaybackWakeLock()
            refreshNowPlayingInfo()
        }
    }

    /// Increments every time `currentPlayer` is swapped.
    ///
    /// `PlayerRenderingView` draws `currentPlayer?.getPlayerView()`, but
    /// `currentPlayer` is a plain `weak var` — not `@Published` — so SwiftUI was
    /// never told when the player it is rendering got replaced. The rendering
    /// view had no declared dependency on the one thing it renders, and redrew
    /// only because some *unrelated* property (`currentTime`, `isBuffering`)
    /// happened to publish a moment later. Anything that swapped the player
    /// while those went quiet left the previous backend's view on screen, which
    /// is a black rectangle once its own player has been torn down — with audio
    /// continuing from the new one.
    ///
    /// A counter rather than `ObjectIdentifier(player)`: identifiers are derived
    /// from the address, so a freshly allocated wrapper can be handed the
    /// address of the one just released and compare *equal* to it — the same
    /// trap `PlayerKitWindowCaptureProtectionRegistry` documents. A counter
    /// cannot collide.
    @Published private(set) var playerGeneration: Int = 0
    private var lastPosition: Double = 0
    private var integrationsConfigured = false
    private var lastRuntimeStateDebugSummary: String?
    
    private var stateCancellables = Set<AnyCancellable>()
    private var longLivedCancellables = Set<AnyCancellable>()
    var activeIntegrationSubscriptionCount: Int { longLivedCancellables.count }
    private var isPlaybackWakeLockHeld = false
    private var nowPlayingEnabledStorage = false
    private var nowPlayingArtworkStorage: PKImage?
    private var backgroundPlaybackEnabledStorage = false
    private var isMutedStorage = false
    private var autoplayStorage = true
    private var externalPlaybackEnabledStorage = false
    private var pictureInPictureRestorationHandlerStorage: (((Bool) -> Void) -> Void)?
    private var voiceControlRunningOverrideStorage: Bool?
    private var shouldResumePlaybackAfterStall: Bool {
        get { isPlaybackRequested }
        set { isPlaybackRequested = newValue }
    }
    private var playbackResumeTask: Task<Void, Never>?
    private var playbackResumeProgressReferenceTime: Double?
    private var externalEpisodeNavigationHandler: (@MainActor (PlayerEpisodeNavigationDirection) async -> Bool)?
    /// Lets a host refresh an expired or signed media URL before Retry reloads
    /// the item. Return `nil` (or throw) to leave the current error on screen.
    public var onPlaybackRetryRequested: (@MainActor (PlayerItem) async throws -> PlayerItem?)?
    private var playbackRetryTask: Task<Void, Never>?
    private var playbackRetryGeneration: UInt = 0
    private var externalEpisodeNavigationTask: Task<Void, Never>?
    private var externalEpisodeNavigationGeneration = 0
    private struct ExternalEpisodeNavigationSnapshot {
        let canPlayPrevious: Bool
        let canPlayNext: Bool
        let handler: @MainActor (PlayerEpisodeNavigationDirection) async -> Bool
    }
    private struct PlaybackSwitchSnapshot {
        let currentItem: PlayerItem?
        let queue: [PlayerItem]
        let currentIndex: Int
        let contentType: PlayerContentType
        let shouldResumePlayback: Bool
        let externalEpisodeNavigation: ExternalEpisodeNavigationSnapshot?
    }
    private var seekWindowReporter: PlayerSeekWindowReporting? {
        currentPlayer as? PlayerSeekWindowReporting
    }

    private init() {
        setupGestureHandling()
        configureOrientationCallbacks()
    }
    
    // MARK: - Player Setup
    
    public func setPlayer(type: PlayerType? = nil) {
        let type = PlayerType.resolved(type ?? UserDefaults.standard.loadPlayerType())
        configurePlayer(type: type, clearMediaContext: true)
    }

    func ensurePlayerConfigured(type: PlayerType? = nil) {
        if let type {
            let resolvedType = PlayerType.resolved(type)
            if activeBuiltInPlayerType != resolvedType {
                if currentPlayer != nil || playerItem != nil || !playerItems.isEmpty {
                    switchPlayer(to: resolvedType)
                } else {
                    setPlayer(type: resolvedType)
                }
            } else if currentPlayer == nil {
                restoreMissingPlayer(type: resolvedType)
            }
            return
        }

        if currentPlayer == nil {
            restoreMissingPlayer(type: selectedPlayerType)
        }
    }

    private func restoreMissingPlayer(type: PlayerType) {
        let retainedItem = playerItem
        configurePlayer(type: type, clearMediaContext: retainedItem == nil)
        if let retainedItem {
            self.playerItem = retainedItem
            load(
                url: retainedItem.url,
                lastPosition: retainedItem.lastPosition,
                itemContext: retainedItem
            )
        }
    }

    private func configurePlayer(type: PlayerType, clearMediaContext: Bool) {
        let resolvedType = PlayerType.resolved(type)
        if resolvedType != type {
            debugLog("Requested unsupported player type=\(type). Falling back to \(resolvedType).")
        }
        // Passive callbacks do not claim process-global resources; keep them
        // available as soon as a backend is configured. Controller handlers,
        // subscriptions, audio activation, and Cast context setup remain lazy.
        configureAudioSessionCallbacks()
        configureCastCallbacks()
        debugLog(
            "Setting player type=\(resolvedType) " +
            "clearMediaContext=\(clearMediaContext)"
        )
        resetPlayer(clearMediaContext: clearMediaContext)
        selectedPlayerType = resolvedType
        let provider = PlayerFactory.getProvider(for: resolvedType)
        setupPlayer(provider: provider)
    }

    private func setupPlayer(provider: PlayerProvider) {
        currentProvider = provider
        activeBuiltInPlayerType = selectedPlayerType
        let player = provider.createPlayer()
        setupPlayer(player)
    }

    private func setupPlayer(_ player: PlayerProtocol) {
        debugLog("Created player instance type=\(String(reflecting: type(of: player)))")
        currentPlayer = player
        applyPlaybackPolicies(to: player)
        bindPlayerCallbacks(player)
        #if os(macOS)
        if let avPlayer = player as? AVPlayerWrapper {
            avPlayer.onPlaybackHealthEvent = { [weak self] event in
                self?.recordPlaybackHealthEvent(event)
            }
        }
        #endif
        
        // Initialize managers with the player instance
        playbackManager = PlaybackManager(player: player, playerManager: self)
        trackManager = TrackManager(player: player)
        
        observePlayerState()
    }

    /// Installs a custom backend while rebuilding every manager binding and
    /// preserving the current media context.
    public func installPlayerBackend(_ player: PlayerProtocol) {
        let resumePosition = Self.nonnegativeFinite(currentPlayer?.currentTime ?? currentTime)
        saveCurrentTracks()
        let snapshot = makePlaybackSwitchSnapshot(resumePosition: resumePosition)
        resetPlayer(clearMediaContext: false)
        currentProvider = nil
        setupPlayer(player)
        restorePlaybackSwitchSnapshot(snapshot)

        guard let currentItem = snapshot.currentItem else { return }
        load(
            url: currentItem.url,
            lastPosition: currentItem.lastPosition,
            itemContext: currentItem,
            shouldAutoplay: snapshot.shouldResumePlayback
        )
        if snapshot.shouldResumePlayback {
            play()
        }
    }
    
    // MARK: - Switch Player at Runtime
    
    public func switchPlayer(to type: PlayerType) {
        let resolvedType = PlayerType.resolved(type)
        guard activeBuiltInPlayerType != resolvedType else { return }
        let resumePosition = Self.nonnegativeFinite(currentPlayer?.currentTime ?? currentTime)
        lastPosition = resumePosition
        saveCurrentTracks()
        let snapshot = makePlaybackSwitchSnapshot(resumePosition: resumePosition)
        configurePlayer(type: resolvedType, clearMediaContext: false)

        restorePlaybackSwitchSnapshot(snapshot)

        if let currentItem = snapshot.currentItem {
            load(
                url: currentItem.url,
                lastPosition: currentItem.lastPosition,
                itemContext: currentItem,
                shouldAutoplay: snapshot.shouldResumePlayback
            )
            if snapshot.shouldResumePlayback {
                play()
            }
        }
    }

    private func makePlaybackSwitchSnapshot(resumePosition: Double) -> PlaybackSwitchSnapshot {
        var restoredQueue = playerItems
        let restoredIndex = restoredQueue.isEmpty
            ? 0
            : min(max(currentPlayerItemIndex, 0), restoredQueue.count - 1)
        let resolvedCurrentItem = playerItem ?? restoredQueue[safe: restoredIndex]
        let currentItem = resolvedCurrentItem.map {
            makePlayerItemCopy(from: $0, resumePosition: resumePosition)
        }

        if let currentItem, !restoredQueue.isEmpty, restoredIndex < restoredQueue.count {
            restoredQueue[restoredIndex] = currentItem
        }

        let externalEpisodeNavigation = externalEpisodeNavigationHandler.map {
            ExternalEpisodeNavigationSnapshot(
                canPlayPrevious: externalEpisodeCanPlayPrevious,
                canPlayNext: externalEpisodeCanPlayNext,
                handler: $0
            )
        }

        return PlaybackSwitchSnapshot(
            currentItem: currentItem,
            queue: restoredQueue,
            currentIndex: restoredIndex,
            contentType: contentType,
            shouldResumePlayback: shouldResumePlaybackAfterStall,
            externalEpisodeNavigation: externalEpisodeNavigation
        )
    }

    private func restorePlaybackSwitchSnapshot(_ snapshot: PlaybackSwitchSnapshot) {
        let restoredIndex = snapshot.queue.isEmpty
            ? 0
            : min(max(snapshot.currentIndex, 0), snapshot.queue.count - 1)

        playerItems = snapshot.queue
        currentPlayerItemIndex = restoredIndex
        contentType = snapshot.contentType
        playerItem = snapshot.currentItem ?? snapshot.queue[safe: restoredIndex]

        if let externalEpisodeNavigation = snapshot.externalEpisodeNavigation {
            configureExternalEpisodeNavigation(
                canPlayPrevious: externalEpisodeNavigation.canPlayPrevious,
                canPlayNext: externalEpisodeNavigation.canPlayNext,
                handler: externalEpisodeNavigation.handler
            )
        }
    }

    func makePlayerItemCopy(from sourceItem: PlayerItem, resumePosition: Double?) -> PlayerItem {
        #if os(macOS)
        return PlayerItem(
            title: sourceItem.title,
            titleImageURL: sourceItem.titleImageURL,
            description: sourceItem.description,
            url: sourceItem.url,
            posterUrl: sourceItem.posterUrl,
            castVideoUrl: sourceItem.castVideoUrl,
            externalPlaybackURL: sourceItem.externalPlaybackURL,
            externalPlaybackContentType: sourceItem.externalPlaybackContentType,
            externalPlaybackDuration: sourceItem.externalPlaybackDuration,
            lastPosition: resumePosition,
            episodeIndex: sourceItem.episodeIndex,
            playbackHealthAssetIdentifier: sourceItem.playbackHealthAssetIdentifier,
            playbackHealthMonitoringEligible: sourceItem.playbackHealthMonitoringEligible
        )
        #else
        PlayerItem(
            title: sourceItem.title,
            titleImageURL: sourceItem.titleImageURL,
            description: sourceItem.description,
            url: sourceItem.url,
            posterUrl: sourceItem.posterUrl,
            castVideoUrl: sourceItem.castVideoUrl,
            externalPlaybackURL: sourceItem.externalPlaybackURL,
            externalPlaybackContentType: sourceItem.externalPlaybackContentType,
            externalPlaybackDuration: sourceItem.externalPlaybackDuration,
            lastPosition: resumePosition,
            episodeIndex: sourceItem.episodeIndex
        )
        #endif
    }
    
    public func load(playerItem: PlayerItem) {
        if currentPlayer == nil {
            configurePlayer(type: selectedPlayerType, clearMediaContext: true)
        }
        // A host normally installs external navigation before the first
        // episode. At that point `contentType` is still `.movie`, so consulting
        // `hasExternalEpisodeNavigation` would erase the freshly installed
        // handler while loading that first episode.
        let preservesExternalNavigation = externalEpisodeNavigationHandler != nil
            && (isExternalEpisodeNavigationInProgress || playerItem.episodeIndex != nil)
        playerItems = []
        currentPlayerItemIndex = 0
        if preservesExternalNavigation {
            contentType = .episode
        } else {
            clearExternalEpisodeNavigation()
            contentType = playerItem.episodeIndex == nil ? .movie : .episode
        }
        loadPlayerItem(playerItem, preservingQueue: preservesExternalNavigation)
    }

    private func loadPlayerItem(_ playerItem: PlayerItem, preservingQueue: Bool) {
        cancelPlaybackRetry()
        self.playerItem = playerItem
        if !preservingQueue {
            contentType = playerItem.episodeIndex == nil ? .movie : .episode
        }
        // New item means new metadata; the didSet hooks only cover transport
        // state, not identity.
        refreshNowPlayingInfo(force: true)
        load(
            url: playerItem.url,
            lastPosition: playerItem.lastPosition,
            itemContext: playerItem
        )
    }
    
    public func loadEpisodes(playerItems: [PlayerItem], currentIndex: Int = 0 ) {
        guard !playerItems.isEmpty else {
            // An empty playlist is an explicit transition to no media. Keeping
            // the previous backend/item alive would play stale content under an
            // empty episode model.
            resetPlayer()
            self.playerItems = []
            currentPlayerItemIndex = 0
            contentType = .episode
            return
        }
        if currentPlayer == nil {
            configurePlayer(type: selectedPlayerType, clearMediaContext: true)
        }
        self.playerItems = playerItems
        contentType = .episode
        // Clamp rather than store the caller's index verbatim: an out-of-range
        // index used to survive here (the safe subscript below only guarded the
        // *load*), and then playNext()/playPrevious() would step it into a
        // hard array subscript in loadPlayerItem(at:) and trap.
        currentPlayerItemIndex = min(max(currentIndex, 0), playerItems.count - 1)
        guard let playerItem = playerItems[safe: currentPlayerItemIndex] else { return }
        loadPlayerItem(playerItem, preservingQueue: true)
    }
    
    // Loads a media URL into the current player
    private func load(
        url: URL,
        lastPosition: Double? = nil,
        itemContext: PlayerItem,
        shouldAutoplay: Bool? = nil
    ) {
        let startsPlayback = shouldAutoplay ?? autoplayStorage
        configureIntegrationsIfNeeded()
        debugLog(
            "Loading media. source_present=true resume=\(lastPosition?.description ?? "nil")"
        )
        cancelPendingPlaybackResume()
        cancelExternalEpisodeNavigation(clearHandler: false)
        clearError()
        // A seek session that outlives the item it was opened on is anchored to
        // the *previous* playhead, so one further tap would seek the new item
        // to the old item's position plus ten seconds. It also swallows the
        // `userInteracted()` at the end of this method, because that guards on
        // `isDoubleTapSeeking` — which is why a newly loaded episode could come
        // up with the controls already hidden.
        gestureManager.reset()
        didNotifyGesturePlaybackStart = false
        isMediaReady = false
        isVideoEnded = false
        // Track callbacks belong to the item that produced them. Clear the
        // published snapshot before the new backend can report synchronously,
        // so menus never offer tracks from the previous video during loading.
        selectedAudio = nil
        selectedSubtitle = nil
        availableAudioTracks = []
        availableSubtitles = []
        let resumePosition = lastPosition.map(Self.nonnegativeFinite)
        currentTime = resumePosition ?? 0
        bufferedDuration = 0
        isPlaying = startsPlayback
        isBuffering = true
        // This is what the resume ladder consults, so gating it here is what
        // stops AVFoundation starting on its own once the item becomes ready.
        shouldResumePlaybackAfterStall = startsPlayback
        playbackResumeProgressReferenceTime = currentTime
        // Player backends begin preparing by playing, so the shared audio
        // session is acquired at first load rather than when `Player` is merely
        // constructed.
        AudioSessionManager.shared.configureAudioSession(for: self)
        #if os(macOS)
        if let avPlayer = currentPlayer as? AVPlayerWrapper {
            endPlaybackDiagnosticsSampling(reason: "player item replaced")
            resetPlaybackDiagnosticsHistory()
            avPlayer.load(
                url: url,
                lastPosition: resumePosition,
                playbackHealthAssetIdentifier: itemContext.playbackHealthAssetIdentifier,
                playbackHealthMonitoringEnabled: isPlaybackHealthMonitoringEnabled,
                playbackHealthMonitoringEligible: itemContext.playbackHealthMonitoringEligible
            )
            startPlaybackDiagnosticsSampling()
        } else {
            currentPlayer?.load(url: url, lastPosition: resumePosition)
        }
        #else
        currentPlayer?.load(url: url, lastPosition: resumePosition)
        #endif
        if !startsPlayback {
            // Unlike AVFoundation, the iOS VLC backend calls play() inside its
            // own load(), so gating the resume ladder is not enough for it.
            playbackManager?.pause()
        }
        userInteracted()
    }
    
    public func videoDidEnd() {
        // Backends call this only from their authoritative end event. Timeline
        // values can still lag that callback (and live/VOD transitions can
        // report an indefinite duration), so re-validating against duration
        // here used to discard real completions and strand a black screen.
        guard !isVideoEnded else { return }
        cancelPendingPlaybackResume()
        shouldResumePlaybackAfterStall = false
        isPlaying = false
        isBuffering = false
        if contentType == .movie {
            // Keep the finished frame available behind the Replay / Close card.
            presentPlaybackEndedState()
        } else {
            // Check if there are more episodes to play
            if canPlayNextItem {
                if hasExternalEpisodeNavigation {
                    _ = handleExternalEpisodeNavigationIfNeeded(
                        .next,
                        presentsEndStateOnFailure: true
                    )
                } else {
                    playNext()
                }
            } else {
                presentPlaybackEndedState()
            }
        }
    }

    private func presentPlaybackEndedState() {
        isVideoEnded = true
        AudioSessionManager.shared.deactivateAudioSession(for: self)
    }

    /// Reloads the current item from the last known position after a terminal
    /// backend failure. An explicit Retry is also an explicit request to play,
    /// regardless of the host's autoplay-on-load preference.
    public func retryPlayback() {
        guard let playerItem else {
            clearError()
            return
        }
        guard playbackRetryTask == nil else { return }

        guard let onPlaybackRetryRequested else {
            reloadForRetry(playerItem)
            return
        }

        isRetryingPlayback = true
        playbackRetryGeneration &+= 1
        let retryGeneration = playbackRetryGeneration
        playbackRetryTask = Task { @MainActor [weak self] in
            let refreshedItem: PlayerItem?
            do {
                refreshedItem = try await onPlaybackRetryRequested(playerItem)
            } catch {
                refreshedItem = nil
            }

            guard let self,
                  !Task.isCancelled,
                  self.playbackRetryGeneration == retryGeneration else { return }
            self.playbackRetryTask = nil
            self.isRetryingPlayback = false
            guard let refreshedItem else { return }
            self.reloadForRetry(refreshedItem)
        }
    }

    private func reloadForRetry(_ refreshedItem: PlayerItem) {
        let resumePosition = Self.nonnegativeFinite(currentPlayer?.currentTime ?? currentTime)
        playerItem = refreshedItem
        if playerItems.indices.contains(currentPlayerItemIndex) {
            playerItems[currentPlayerItemIndex] = refreshedItem
        }
        refreshNowPlayingInfo(force: true)
        if currentPlayer == nil {
            configurePlayer(type: selectedPlayerType, clearMediaContext: false)
        }
        load(
            url: refreshedItem.url,
            lastPosition: resumePosition,
            itemContext: refreshedItem,
            shouldAutoplay: true
        )
        play()
    }

    /// Starts the finished item again without disturbing its queue position.
    public func replay() {
        guard let playerItem else { return }
        if currentPlayer == nil {
            configurePlayer(type: selectedPlayerType, clearMediaContext: false)
        }
        load(
            url: playerItem.url,
            lastPosition: 0,
            itemContext: playerItem,
            shouldAutoplay: true
        )
        play()
    }
    
    // MARK: - Player Items Navigation
    public var canPlayNextItem: Bool {
        if hasExternalEpisodeNavigation {
            return externalEpisodeCanPlayNext && !isExternalEpisodeNavigationInProgress
        }

        return !playerItems.isEmpty && currentPlayerItemIndex < playerItems.count - 1
    }

    public var canPlayPreviousItem: Bool {
        if hasExternalEpisodeNavigation {
            return externalEpisodeCanPlayPrevious && !isExternalEpisodeNavigationInProgress
        }

        return !playerItems.isEmpty && currentPlayerItemIndex > 0
    }

    public func configureExternalEpisodeNavigation(
        canPlayPrevious: Bool = true,
        canPlayNext: Bool = true,
        handler: @escaping @MainActor (PlayerEpisodeNavigationDirection) async -> Bool
    ) {
        cancelExternalEpisodeNavigation(clearHandler: true)
        externalEpisodeNavigationHandler = handler
        externalEpisodeCanPlayPrevious = canPlayPrevious
        externalEpisodeCanPlayNext = canPlayNext
    }

    public func updateExternalEpisodeNavigationAvailability(
        canPlayPrevious: Bool,
        canPlayNext: Bool
    ) {
        guard hasExternalEpisodeNavigation else { return }
        externalEpisodeCanPlayPrevious = canPlayPrevious
        externalEpisodeCanPlayNext = canPlayNext
    }

    public func clearExternalEpisodeNavigation() {
        cancelExternalEpisodeNavigation(clearHandler: true)
    }

    public func playNext() {
        if handleExternalEpisodeNavigationIfNeeded(.next) {
            return
        }

        NotificationCenter.default.post(name: .PlayerKitNextItem, object: nil)
        saveCurrentTracks()
        guard !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count - 1 else { return }
        currentPlayerItemIndex += 1
        loadPlayerItem(at: currentPlayerItemIndex)
    }
    
    public func playPrevious() {
        if handleExternalEpisodeNavigationIfNeeded(.previous) {
            return
        }

        NotificationCenter.default.post(name: .PlayerKitPrevItem, object: nil)
        saveCurrentTracks()
        guard !playerItems.isEmpty, currentPlayerItemIndex > 0 else { return }
        currentPlayerItemIndex -= 1
        loadPlayerItem(at: currentPlayerItemIndex)
    }
    
    private func loadPlayerItem(at index: Int) {
        // Defence in depth: every caller now clamps, but this used to be the
        // single unguarded subscript reachable from public API.
        guard let playerItem = playerItems[safe: index] else {
            debugLog("Ignoring episode load for out-of-range index=\(index) count=\(playerItems.count)")
            return
        }
        loadPlayerItem(playerItem, preservingQueue: true)
    }

    private var hasExternalEpisodeNavigation: Bool {
        contentType == .episode && externalEpisodeNavigationHandler != nil
    }

    private func handleExternalEpisodeNavigationIfNeeded(
        _ direction: PlayerEpisodeNavigationDirection,
        presentsEndStateOnFailure: Bool = false
    ) -> Bool {
        guard hasExternalEpisodeNavigation,
              let handler = externalEpisodeNavigationHandler else {
            return false
        }

        let canNavigate: Bool
        switch direction {
        case .previous:
            canNavigate = externalEpisodeCanPlayPrevious
        case .next:
            canNavigate = externalEpisodeCanPlayNext
        }

        guard canNavigate, !isExternalEpisodeNavigationInProgress else {
            return true
        }

        saveCurrentTracks()
        clearError()
        isExternalEpisodeNavigationInProgress = true

        externalEpisodeNavigationGeneration &+= 1
        let generation = externalEpisodeNavigationGeneration
        externalEpisodeNavigationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let didNavigate = await handler(direction)
            guard !Task.isCancelled,
                  self.externalEpisodeNavigationGeneration == generation else {
                return
            }
            self.isExternalEpisodeNavigationInProgress = false
            self.externalEpisodeNavigationTask = nil
            if presentsEndStateOnFailure && !didNavigate {
                self.presentPlaybackEndedState()
            }
        }

        return true
    }

    private func cancelExternalEpisodeNavigation(clearHandler: Bool) {
        externalEpisodeNavigationGeneration &+= 1
        externalEpisodeNavigationTask?.cancel()
        externalEpisodeNavigationTask = nil
        isExternalEpisodeNavigationInProgress = false
        guard clearHandler else { return }
        externalEpisodeNavigationHandler = nil
        externalEpisodeCanPlayPrevious = false
        externalEpisodeCanPlayNext = false
    }

    private func cancelPlaybackRetry() {
        playbackRetryGeneration &+= 1
        playbackRetryTask?.cancel()
        playbackRetryTask = nil
        isRetryingPlayback = false
    }
}

// MARK: - Playback Controls
extension PlayerManager {
    public func reportError(_ error: PlayerKitError) {
        publishError(error, isTerminal: false)
    }

    private func reportTerminalPlaybackError(_ error: PlayerKitError) {
        publishError(error, isTerminal: true)
    }

    private func publishError(_ error: PlayerKitError, isTerminal: Bool) {
        debugLog("Error reported. \(networkErrorDebugDetails(error))")
        isPlaybackErrorTerminal = isTerminal
        lastError = error
        NotificationCenter.default.post(name: .PlayerKitDidFail, object: error)
    }

    public func clearError() {
        isPlaybackErrorTerminal = false
        lastError = nil
    }

    public func play() {
        if currentPlayer == nil {
            restoreMissingPlayer(type: selectedPlayerType)
        }
        configureIntegrationsIfNeeded()
        debugLog(
            "Play requested current=\(debugInterval(currentTime)) " +
            "mediaReady=\(isMediaReady) playerIsPlaying=\(currentPlayer?.isPlaying ?? false) " +
            "buffering=\(currentPlayer?.isBuffering ?? false)"
        )
        shouldResumePlaybackAfterStall = true
        cancelPendingPlaybackResume()
        playbackResumeProgressReferenceTime = Self.nonnegativeFinite(
            currentPlayer?.currentTime ?? currentTime
        )
        AudioSessionManager.shared.configureAudioSession(for: self)
        performPlaybackResumeAttempt()
        #if os(macOS)
        if let avPlayer = currentPlayer as? AVPlayerWrapper,
           avPlayer.hasLoadedMedia,
           playbackDiagnosticsSampleCancellable == nil,
           avPlayer.restartPlaybackDiagnosticsSession() {
            resetPlaybackDiagnosticsHistory()
            startPlaybackDiagnosticsSampling()
        }
        #endif
        userInteracted()
    }
    
    public func pause() {
        debugLog(
            "Pause requested current=\(debugInterval(currentTime)) " +
            "mediaReady=\(isMediaReady) playerIsPlaying=\(currentPlayer?.isPlaying ?? false)"
        )
        cancelPendingPlaybackResume()
        playbackManager?.pause()
        isPlaying = false
        isBuffering = false
        shouldResumePlaybackAfterStall = false
        userInteracted()
    }
    
    public func stop() {
        debugLog(
            "Stop requested current=\(debugInterval(currentTime)) " +
            "mediaReady=\(isMediaReady) playerIsPlaying=\(currentPlayer?.isPlaying ?? false)"
        )
        cancelPendingPlaybackResume()
        #if os(macOS)
        endPlaybackDiagnosticsSampling(reason: "playback stopped")
        #endif
        playbackManager?.stop()
        isPlaying = false
        isBuffering = false
        currentTime = 0
        shouldResumePlaybackAfterStall = false
        AudioSessionManager.shared.deactivateAudioSession(for: self)
        userInteracted()
    }
    
    /// The range `seek(to:)` will clamp into.
    ///
    /// `duration` is 0 for live/DVR HLS (AVFoundation reports an indefinite
    /// duration), which used to make every seek on a live stream a silent
    /// no-op. Fall back to the backend's seekable window, which is exactly the
    /// DVR buffer the user can actually move within.
    var seekableRange: ClosedRange<Double>? {
        if duration > 0 {
            return 0 ... duration
        }
        guard let window = seekWindowReporter?.seekableTimeWindow,
              window.upperBound > window.lowerBound else {
            return nil
        }
        return window
    }

    public func seek(to time: Double, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard time.isFinite else {
            debugLog("Seek ignored because target is not finite.")
            completion?(false)
            return
        }
        guard let seekableRange else {
            debugLog(
                "Seek ignored: no finite duration and no seekable window. " +
                "target=\(debugInterval(time))"
            )
            completion?(false)
            return
        }
        let targetTime = min(max(time, seekableRange.lowerBound), seekableRange.upperBound)
        debugLog(
            "Seek requested target=\(debugInterval(targetTime)) " +
            "current=\(debugInterval(currentTime)) shouldResume=\(shouldResumePlaybackAfterStall) " +
            "mediaReady=\(isMediaReady) playerIsPlaying=\(currentPlayer?.isPlaying ?? false)"
        )

        let shouldResumeAfterSeek = shouldResumePlaybackAfterStall
        guard let playbackManager else {
            completion?(false)
            return
        }
        playbackManager.seek(to: targetTime) { [weak self] success in
            guard let self else {
                completion?(false)
                return
            }
            self.finishSeek(
                success: success,
                targetTime: targetTime,
                shouldResumeAfterSeek: shouldResumeAfterSeek,
                completion: completion
            )
        }
    }

    /// Applies post-seek state. Always invoked on the main thread.
    private func finishSeek(
        success: Bool,
        targetTime: Double,
        shouldResumeAfterSeek: Bool,
        completion: (@MainActor (Bool) -> Void)?
    ) {
        if success {
            currentTime = targetTime
            refreshNowPlayingInfo(force: true)
            if shouldResumeAfterSeek {
                debugLog(
                    "Seek succeeded and playback should resume. target=\(debugInterval(targetTime))"
                )
                playbackResumeProgressReferenceTime = targetTime
                schedulePlaybackResumeIfNeeded(trigger: "seek")
            }
        } else {
            debugLog(
                "Seek failed. target=\(debugInterval(targetTime)) current=\(debugInterval(currentTime))"
            )
        }
        completion?(success)
    }

    public func scrubForward(by seconds: TimeInterval) {
        seekRelative(by: seconds)
    }

    public func scrubBackward(by seconds: TimeInterval) {
        seekRelative(by: -seconds)
    }

    /// Moves the playhead by `offset` seconds through `seek(to:)`.
    ///
    /// These used to call `playbackManager?.scrub…` straight through to the
    /// backend, which reached `AVPlayerWrapper.seek` without passing any of
    /// `seek(to:)`'s work: the clamp into `seekableRange`, the `currentTime`
    /// write and the resume-after-seek scheduling. On live that meant a skip
    /// was clamped by the backend alone and could land outside the DVR window.
    /// One clamping path is the point.
    private func seekRelative(by offset: TimeInterval) {
        guard offset.isFinite else { return }
        let reference = currentPlayer?.currentTime ?? currentTime
        seek(to: reference + offset)
    }
    
    public func setPlaybackSpeed(_ speed: Float) {
        guard speed.isFinite, speed > 0 else {
            debugLog("Ignoring invalid playback speed.")
            return
        }
        playbackSpeed = speed
        playbackManager?.setPlaybackSpeed(speed)
        refreshNowPlayingInfo(force: true)
    }
}

#if os(macOS)
private extension PlaybackDiagnosticsSnapshot {
    func replacingStoryboard(
        _ storyboard: PlaybackDiagnosticsStoryboard
    ) -> PlaybackDiagnosticsSnapshot {
        PlaybackDiagnosticsSnapshot(
            session: session,
            playback: playback,
            network: network,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            errorLogEventCount: errorLogEventCount,
            recentErrors: recentErrors,
            recentHealthEvents: recentHealthEvents,
            monitor: monitor,
            history: history,
            storyboard: storyboard
        )
    }
}
#endif

// MARK: - Track Management
extension PlayerManager {
    public func refreshTrackInfo() {
        availableAudioTracks = trackManager?.availableAudioTracks ?? []
        availableSubtitles = trackManager?.availableSubtitles ?? []

        selectedAudio = trackManager?.currentAudioTrack
        selectedSubtitle = trackManager?.currentSubtitleTrack

        debugLog(
            "Track refresh. audio_count=\(availableAudioTracks.count) " +
            "subtitle_count=\(availableSubtitles.count) " +
            "selected_audio_present=\(selectedAudio != nil) " +
            "selected_subtitle_present=\(selectedSubtitle != nil)"
        )

        applySavedTrackIdentifiers()
    }
    
    public func selectAudioTrack(track: TrackInfo) {
        let shouldResumeAfterTrackSelection = shouldResumePlaybackAfterStall
        let trackSelectionReferenceTime = max(currentPlayer?.currentTime ?? currentTime, 0)

        selectedAudio = track
        trackManager?.selectAudioTrack(withID: track.id)
        if shouldResumeAfterTrackSelection {
            debugLog(
                "Audio track selected while playback should continue. " +
                "track_present=true current=\(debugInterval(trackSelectionReferenceTime))"
            )
            playbackResumeProgressReferenceTime = trackSelectionReferenceTime
            schedulePlaybackResumeIfNeeded(trigger: "audio-track-selection")
        }
        userInteracted()
    }

    public func selectSubtitle(track: TrackInfo?) {
        selectedSubtitle = track
        trackManager?.selectSubtitle(withID: track?.id)
        userInteracted()
    }
    
    private func saveCurrentTracks() {
        savedAudio = selectedAudio
        savedSubtitleSelection = selectedSubtitle.map(SavedSubtitleSelection.selected) ?? .disabled
    }
    
    private func applySavedTrackIdentifiers() {
        if let savedAudio = savedAudio {
            let match = availableAudioTracks.first(where: { $0.id == savedAudio.id })
                ?? availableAudioTracks.first(where: { $0.languageCode == savedAudio.languageCode })
            if let match {
                // Consume before calling the backend: desktop VLC reports track
                // changes synchronously and therefore re-enters this method.
                self.savedAudio = nil
                selectAudioTrack(track: match)
            }
        }
        
        switch savedSubtitleSelection {
        case .unchanged:
            break
        case .disabled:
            savedSubtitleSelection = .unchanged
            selectSubtitle(track: nil)
        case .selected(let savedSubtitle):
            let match = availableSubtitles.first(where: { $0.id == savedSubtitle.id })
                ?? availableSubtitles.first(where: { $0.languageCode == savedSubtitle.languageCode })
            if let match {
                savedSubtitleSelection = .unchanged
                selectSubtitle(track: match)
            }
        }
    }


    fileprivate func cancelPendingPlaybackResume() {
        if playbackResumeTask != nil {
            debugLog("Cancelling pending playback resume task.")
        }
        playbackResumeTask?.cancel()
        playbackResumeTask = nil
        playbackResumeProgressReferenceTime = nil
    }


    fileprivate func networkErrorDebugDetails(_ error: Error) -> String {
        let nsError = error as NSError
        let allowedDomains = [
            NSURLErrorDomain,
            NSCocoaErrorDomain,
            NSOSStatusErrorDomain,
            "AVFoundationErrorDomain",
            "CoreMediaErrorDomain",
            "kCFErrorDomainCFNetwork"
        ]
        let domain = allowedDomains.contains(nsError.domain) ? nsError.domain : "unlisted"
        return "domain=\(domain) code=\(nsError.code)"
    }


    fileprivate func debugLog(_ message: @autoclosure () -> String) {
        PlayerKitLog.debug("PlayerManager", message())
    }

    private func debugInterval(_ value: Double) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.3f", value)
    }

    private static func nonnegativeFinite(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }

    private func logRuntimeStateIfChanged(_ state: PlayerRuntimeState) {
        let summary =
            "playing=\(state.isPlaying) buffering=\(state.isBuffering) " +
            "current=\(debugInterval(state.currentTime)) duration=\(debugInterval(state.duration)) " +
            "buffered=\(debugInterval(state.bufferedDuration)) mediaReady=\(isMediaReady) " +
            "shouldResume=\(shouldResumePlaybackAfterStall)"
        guard lastRuntimeStateDebugSummary != summary else { return }
        lastRuntimeStateDebugSummary = summary
        debugLog("Runtime state updated \(summary)")
    }

}

// MARK: - Now Playing, Remote Commands and Background Playback
extension PlayerManager {
    /// Publishes lock-screen / Control Center metadata and installs the system
    /// transport controls.
    ///
    /// Off by default. `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` are
    /// process-global, so turning this on means PlayerKit takes over controls
    /// the host may already be driving. It restores whatever it found when the
    /// last owner releases, but taking them at all is the host's call — the
    /// same posture `isExternalPlaybackEnabled` takes.
    public var isNowPlayingEnabled: Bool {
        get { nowPlayingEnabledStorage }
        set {
            guard newValue != nowPlayingEnabledStorage else { return }
            nowPlayingEnabledStorage = newValue
            if newValue {
                installNowPlayingIfNeeded()
                refreshNowPlayingInfo(force: true)
            } else {
                NowPlayingCoordinator.shared.releaseCommands(for: self)
            }
            objectWillChange.send()
        }
    }

    /// Artwork for the lock screen.
    ///
    /// PlayerKit does not fetch `PlayerItem.posterUrl` itself: that would mean
    /// owning an image cache and a network policy, which belongs to the host.
    public var nowPlayingArtwork: PKImage? {
        get { nowPlayingArtworkStorage }
        set {
            nowPlayingArtworkStorage = newValue
            NowPlayingCoordinator.shared.setArtwork(newValue)
            refreshNowPlayingInfo(force: true)
        }
    }

    /// Lets audio continue when the app is backgrounded.
    ///
    /// Off by default: PlayerKit configures `AVPlayer` to pause in the
    /// background as part of its capture-protection posture, so continuing is
    /// an explicit relaxation.
    ///
    /// This only removes PlayerKit's objection. Background audio *also* needs
    /// `audio` in the host app's `UIBackgroundModes`, which a package cannot
    /// declare on the host's behalf. The VLC backends are unaffected by this
    /// flag.
    public var isBackgroundPlaybackEnabled: Bool {
        get { backgroundPlaybackEnabledStorage }
        set {
            guard newValue != backgroundPlaybackEnabledStorage else { return }
            backgroundPlaybackEnabledStorage = newValue
            if let player = currentPlayer {
                applyPlaybackPolicies(to: player)
            }
            objectWillChange.send()
        }
    }

    /// Pushes the stored policies into a freshly created backend.
    ///
    /// Applied here rather than read back off `currentPlayer` on demand,
    /// because a host configures these before any media exists — a computed
    /// property proxying to `currentPlayer as? AVPlayerWrapper` would be inert
    /// at exactly the moment it is set.
    func applyPlaybackPolicies(to player: PlayerProtocol) {
        (player as? PlayerMuteControlling)?.setMuted(isMutedStorage)
        player.playbackSpeed = playbackSpeed
        guard let avPlayer = player as? AVPlayerWrapper else { return }
        avPlayer.allowsBackgroundPlayback = backgroundPlaybackEnabledStorage
        avPlayer.allowsExternalPlayback = externalPlaybackEnabledStorage
        avPlayer.onPictureInPictureRestoreRequested = pictureInPictureRestorationHandlerStorage
    }

    func installNowPlayingIfNeeded() {
        guard nowPlayingEnabledStorage else { return }
        let commands = makeNowPlayingCommands()
        let coordinator = NowPlayingCoordinator.shared
        let artwork = nowPlayingArtworkStorage
        coordinator.installCommands(for: self, commands: commands)
        coordinator.setArtwork(artwork)
    }

    func releaseNowPlaying() {
        NowPlayingCoordinator.shared.releaseCommands(for: self)
    }

    private func makeNowPlayingCommands() -> NowPlayingCommands {
        NowPlayingCommands(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in
                guard let self else { return }
                self.isPlaybackRequested ? self.pause() : self.play()
            },
            skipForward: { [weak self] seconds in self?.scrubForward(by: seconds) },
            skipBackward: { [weak self] seconds in self?.scrubBackward(by: seconds) },
            seek: { [weak self] time in self?.seek(to: time) },
            canSeek: { [weak self] in self?.seekableRange != nil },
            next: { [weak self] in self?.playNext() },
            canNext: { [weak self] in self?.canPlayNextItem ?? false },
            previous: { [weak self] in self?.playPrevious() },
            canPrevious: { [weak self] in self?.canPlayPreviousItem ?? false }
        )
    }

    /// The state the lock screen should show, or `nil` when there is nothing
    /// playing to describe.
    func makeNowPlayingSnapshot() -> NowPlayingSnapshot? {
        guard let item = playerItem else { return nil }
        // Live has no meaningful total, and the seekable window is what the
        // rest of PlayerKit already treats as the timeline.
        let isLive = duration <= 0 && seekableRange != nil
        let resolvedDuration: Double? = duration > 0 ? duration : nil
        return NowPlayingSnapshot(
            title: item.title,
            subtitle: item.description,
            duration: resolvedDuration,
            elapsed: Self.nonnegativeFinite(currentPlayer?.currentTime ?? currentTime),
            // playbackSpeed keeps its configured value while paused, so the
            // lock screen would animate a stopped playhead without this.
            rate: isPlaying ? Double(playbackSpeed) : 0,
            isLive: isLive
        )
    }

    /// Publishes now-playing state, if it has changed.
    ///
    /// Deliberately NOT driven from `applyRuntimeState`, which runs at 2 Hz:
    /// `MPNowPlayingInfoCenter` extrapolates elapsed time from the rate and the
    /// moment of the last push, so republishing on every tick would repeatedly
    /// reset that interpolation. This is called from the same state-transition
    /// points as `refreshPlaybackWakeLock`, plus seeks and speed changes.
    func refreshNowPlayingInfo(force: Bool = false) {
        guard nowPlayingEnabledStorage else { return }
        let snapshot = makeNowPlayingSnapshot()
        let canSeek = seekableRange != nil
        let canNext = canPlayNextItem
        let canPrevious = canPlayPreviousItem
        let coordinator = NowPlayingCoordinator.shared
        coordinator.updateAvailability(
            canSeek: canSeek,
            canNext: canNext,
            canPrevious: canPrevious
        )
        guard let snapshot else {
            coordinator.clearNowPlayingItem()
            return
        }
        coordinator.publish(snapshot)
    }
}

// MARK: - Mute and Autoplay
extension PlayerManager {
    /// Silences the backend without changing the system volume.
    ///
    /// Every backend can do this, and none of them exposed it — the capability
    /// existed on all three wrappers with no way for a host to reach it.
    ///
    /// Stored rather than read back off the current backend, so setting it
    /// before any media is loaded still takes effect: the value is pushed into
    /// each player as it is created.
    public var isMuted: Bool {
        get { isMutedStorage }
        set {
            guard newValue != isMutedStorage else { return }
            isMutedStorage = newValue
            (currentPlayer as? PlayerMuteControlling)?.setMuted(newValue)
            objectWillChange.send()
        }
    }

    /// Whether loading an item also starts playing it. `true` by default,
    /// which is the behaviour every existing host already gets.
    ///
    /// With this off, `load` prepares the item and leaves it paused; the host
    /// starts it with `play()`.
    public var autoplay: Bool {
        get { autoplayStorage }
        set {
            guard newValue != autoplayStorage else { return }
            autoplayStorage = newValue
            objectWillChange.send()
        }
    }

    /// Host-supplied Voice Control state, which UIKit does not publicly report.
    /// Leave `nil` when it is unknown; PlayerKit still observes the assistive
    /// technologies UIKit does expose.
    public var voiceControlRunningOverride: Bool? {
        get { voiceControlRunningOverrideStorage }
        set {
            guard newValue != voiceControlRunningOverrideStorage else { return }
            voiceControlRunningOverrideStorage = newValue
            gestureManager.refreshAccessibilityState()
            controlVisibilityManager.refreshAssistiveTechnologyState()
            objectWillChange.send()
        }
    }
}

// MARK: - External Playback (AirPlay)
extension PlayerManager {
    /// Enables AirPlay video routing.
    ///
    /// Off by default: PlayerKit configures `AVPlayer` for capture protection,
    /// and external playback is part of that posture. Hosts that want AirPlay
    /// must opt in explicitly. When this is `false` the AirPlay affordance is
    /// hidden rather than presented as a control that silently does nothing.
    public var isExternalPlaybackEnabled: Bool {
        get { externalPlaybackEnabledStorage }
        set {
            guard newValue != externalPlaybackEnabledStorage else { return }
            externalPlaybackEnabledStorage = newValue
            (currentPlayer as? AVPlayerWrapper)?.allowsExternalPlayback = newValue
            objectWillChange.send()
        }
    }

    /// Whether the active backend can honor the host's AirPlay opt-in.
    public var canUseAirPlay: Bool {
        externalPlaybackEnabledStorage && currentPlayer is AVPlayerWrapper
    }
}

// MARK: - PiP Controls
extension PlayerManager {
    /// Lets the host restore its player presentation when system PiP closes.
    /// Call the supplied completion with `true` only after restoration succeeds.
    public var onPictureInPictureRestoreRequested: (((Bool) -> Void) -> Void)? {
        get { pictureInPictureRestorationHandlerStorage }
        set {
            pictureInPictureRestorationHandlerStorage = newValue
            (currentPlayer as? AVPlayerWrapper)?.onPictureInPictureRestoreRequested = newValue
        }
    }

    public var isPiPSupported: Bool {
        (currentPlayer as? PlayerPictureInPictureSupporting)?.isPictureInPictureSupported ?? false
    }

    public var canTogglePiP: Bool {
        guard let pipSupport = currentPlayer as? PlayerPictureInPictureSupporting else { return false }
        return pipSupport.isPictureInPictureSupported && (pipSupport.isPictureInPicturePossible || isPiPActive)
    }

    public func startPiP() {
        currentPlayer?.startPiP()
    }
    
    public func stopPiP() {
        currentPlayer?.stopPiP()
    }
}

// MARK: - Chromecast Controls
extension PlayerManager {
    /// Selects the Cast receiver application before the first Cast interaction.
    /// Returns `false` for an empty identifier or after Cast is initialized.
    @discardableResult
    public func configureChromecast(receiverApplicationID: String) -> Bool {
        castManager.configure(receiverApplicationID: receiverApplicationID)
    }

    /// Creates Cast's process-global context before Google's official button.
    /// The SDK still defers device discovery until that button is tapped.
    @discardableResult
    func prepareChromecastButton() -> Bool {
        configureCastCallbacks()
        return castManager.prepareForUserInteraction()
    }

    /// Initializes Cast after user intent and presents the device picker.
    @discardableResult
    public func presentChromecastDevicePicker() -> Bool {
        configureIntegrationsIfNeeded()
        return castManager.presentCastDialog()
    }

    public func playOnChromecast() {
        configureIntegrationsIfNeeded()
        castManager.playMediaOnCast()
    }
    
    public func pauseChromecast() {
        configureIntegrationsIfNeeded()
        castManager.pauseCast()
    }
    
    public func stopChromecast() {
        configureIntegrationsIfNeeded()
        castManager.stopCast()
    }
}

// MARK: - Gesture Handling
extension PlayerManager {
    private func setupGestureHandling() {
        gestureManager.onSeek = { [weak self] newTime in
            self?.seek(to: newTime)
        }
        
        gestureManager.onToggleControls = { [weak self] in
            self?.toggleControlsVisibility()
        }
        
        gestureManager.onZoom = { [weak self] scale in
            self?.currentPlayer?.handlePinchGesture(scale: scale)
        }
        
        gestureManager.isLockedProvider = { [weak self] in
            self?.isLocked ?? false
        }
        
        gestureManager.currentTimeProvider = { [weak self] in
            self?.currentPlayer?.currentTime ?? self?.currentTime ?? 0
        }
        
        gestureManager.seekableRangeProvider = { [weak self] in
            self?.seekableRange
        }
        
        // Routed through the visibility manager rather than writing
        // `areControlsVisible` directly, so a gesture-driven hide also cancels
        // the auto-hide timer and posts `.PlayerKitControlsHidden` like every
        // other path that puts the controls away.
        gestureManager.onControlsVisibilityChange = { [weak self] isVisible in
            guard let self else { return }
            if isVisible {
                self.controlVisibilityManager.showControls()
            } else {
                self.controlVisibilityManager.hideControls()
            }
        }

        gestureManager.onSeekSessionChange = { [weak self] isSeeking in
            self?.isDoubleTapSeeking = isSeeking
        }

        // Feeds the deferred-toggle decision: only a tap that arrives while the
        // chrome is *hidden* has its show held back, because that is the one
        // that would otherwise wash the whole interface in and out behind a
        // skip.
        gestureManager.areControlsVisibleProvider = { [weak self] in
            self?.areControlsVisible ?? true
        }

        // The volume rail writes the backend's own level rather than the
        // device's. Resolved through `currentPlayer` on every read so switching
        // backends mid-session cannot leave the rail driving a dead object.
        gestureManager.volumeControl.backendProvider = { [weak self] in
            self?.currentPlayer as? PlayerVolumeControlling
        }

        gestureManager.isPlayingProvider = { [weak self] in
            self?.isPlaying ?? false
        }
        gestureManager.isPlaybackRequestedProvider = { [weak self] in
            self?.isPlaybackRequested ?? false
        }
        gestureManager.isZoomAvailableProvider = { [weak self] in
            self?.isZoomGestureAvailable ?? false
        }
        gestureManager.voiceControlRunningProvider = { [weak self] in
            self?.voiceControlRunningOverride
        }
        gestureManager.speedProvider = { [weak self] in
            self?.playbackSpeed ?? 1
        }
        gestureManager.onSetSpeed = { [weak self] speed in
            self?.setPlaybackSpeed(speed)
        }
        gestureManager.onTogglePlayback = { [weak self] in
            guard let self else { return }
            self.isPlaybackRequested ? self.pause() : self.play()
        }
    }

    private var isZoomGestureAvailable: Bool {
        currentPlayer?.isZoomSupported == true
    }

    /// Fires once per presentation, on the first frame of real playback.
    ///
    /// Deliberately gated on `isPlaying && isMediaReady` rather than on view
    /// appearance: the coached walkthrough teaches gestures over the picture, so
    /// the first thing the user should see is video, not a lesson over a
    /// spinner.
    private func notifyGesturePlaybackStartedIfNeeded() {
        guard !didNotifyGesturePlaybackStart, isPlaying, isMediaReady else { return }
        didNotifyGesturePlaybackStart = true
        gestureManager.playbackDidStart()
    }
    
    public func setGravityToDefault() {
        currentPlayer?.setGravityToDefault()
    }
}

// MARK: - Control Visibility Management
extension PlayerManager {
    /// Called whenever the user interacts, showing controls and resetting the auto-hide timer
    public func userInteracted() {
        guard !gestureManager.isDoubleTapSeeking else { return }
        controlVisibilityManager.showControls()
    }
    
    /// Toggles the visibility of controls and manages the auto-hide timer
    public func toggleControlsVisibility() {
        if areControlsVisible {
            controlVisibilityManager.hideControls()
        } else {
            controlVisibilityManager.showControls()
        }
    }
}

// MARK: - Streaming Info Updates
extension PlayerManager {
    func fetchStreamingInfo() -> StreamingInfo {
        return currentPlayer?.fetchStreamingInfo() ?? .placeholder
    }

    #if os(macOS)
    func fetchPlaybackDiagnostics() -> PlaybackDiagnosticsSnapshot {
        if playbackDiagnosticsSampleCancellable == nil,
           let playbackDiagnosticsLastSnapshot {
            return playbackDiagnosticsLastSnapshot
        }
        guard let currentPlayer else {
            return .unavailable(.noPlayerItem)
        }
        guard let avPlayer = currentPlayer as? AVPlayerWrapper else {
            return .unavailable(.unsupportedBackend)
        }
        return avPlayer.fetchPlaybackDiagnostics(
            monitoringEnabled: isPlaybackHealthMonitoringEnabled,
            recentHealthEvents: recentPlaybackHealthEvents,
            history: playbackDiagnosticsHistory,
            storyboard: playbackDiagnosticsSession.storyboard
        )
    }

    @discardableResult
    func capturePlaybackDiagnosticsBookmark() -> PlaybackDiagnosticsBookmark? {
        guard hasActivePlaybackDiagnosticsItem,
              currentPlayer is AVPlayerWrapper else {
            return nil
        }
        let snapshot = currentPlaybackDiagnosticsSnapshot()
        guard let bookmark = playbackDiagnosticsSession.captureBookmark(
            from: snapshot
        ) else {
            return nil
        }
        playbackDiagnosticsLastSnapshot = snapshot.replacingStoryboard(
            playbackDiagnosticsSession.storyboard
        )
        playbackDiagnosticsLifecycleLogger.info(
            "diagnostics bookmark created id=\(bookmark.id.uuidString, privacy: .private(mask: .hash))"
        )
        return bookmark
    }

    func clearPlaybackDiagnosticsEvents() {
        playbackHealthEventsClearedCount += recentPlaybackHealthEvents.count
        recentPlaybackHealthEvents.removeAll(keepingCapacity: true)
        playbackDiagnosticsSession.clearEvidence()
        playbackDiagnosticsLastSnapshot = playbackDiagnosticsLastSnapshot?
            .replacingStoryboard(playbackDiagnosticsSession.storyboard)
    }

    private func recordPlaybackHealthEvent(_ event: PlaybackHealthEvent) {
        guard hasActivePlaybackDiagnosticsItem else {
            // Preserve the existing observer contract while keeping stopped
            // sessions immutable; real monitor callbacks are already session-gated.
            onPlaybackHealthEvent?(event)
            return
        }

        if let currentSessionID = recentPlaybackHealthEvents.last?.healthSessionID,
           currentSessionID != event.healthSessionID {
            resetPlaybackDiagnosticsHistory()
        }

        playbackHealthEventsReceivedCount += 1
        recentPlaybackHealthEvents.append(event)
        // ponytail: the dashboard keeps only 50 sanitized signals; add aggregate
        // persistence if a later calibration needs longer per-session history.
        if recentPlaybackHealthEvents.count > 50 {
            let droppedCount = recentPlaybackHealthEvents.count - 50
            recentPlaybackHealthEvents.removeFirst(droppedCount)
            playbackHealthEventsDroppedCount += droppedCount
        }
        onPlaybackHealthEvent?(event)
    }

    private var playbackDiagnosticsHistory: PlaybackDiagnosticsHistory {
        PlaybackDiagnosticsHistory(
            receivedCount: playbackHealthEventsReceivedCount,
            retainedCount: recentPlaybackHealthEvents.count,
            droppedCount: playbackHealthEventsDroppedCount,
            clearedCount: playbackHealthEventsClearedCount
        )
    }

    private func resetPlaybackDiagnosticsHistory() {
        let hadSession = playbackDiagnosticsLastSnapshot != nil
            || !playbackDiagnosticsSession.storyboard.samples.isEmpty
        recentPlaybackHealthEvents.removeAll(keepingCapacity: true)
        playbackDiagnosticsSession.reset()
        playbackDiagnosticsLastSnapshot = nil
        playbackHealthEventsReceivedCount = 0
        playbackHealthEventsDroppedCount = 0
        playbackHealthEventsClearedCount = 0
        if hadSession {
            playbackDiagnosticsLifecycleLogger.info("diagnostics session reset")
        }
    }

    private func startPlaybackDiagnosticsSampling() {
        playbackDiagnosticsSampleCancellable?.cancel()
        playbackDiagnosticsSampleCancellable = nil
        recordPlaybackDiagnosticsSample()
        playbackDiagnosticsSampleCancellable = Timer.publish(
            every: 1,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.recordPlaybackDiagnosticsSample()
        }
        playbackDiagnosticsLifecycleLogger.info(
            "diagnostics session started session=\(self.playbackDiagnosticsLastSnapshot?.session.sessionID?.uuidString ?? "not-measured", privacy: .private(mask: .hash))"
        )
    }

    private func recordPlaybackDiagnosticsSample() {
        guard currentPlayer is AVPlayerWrapper else { return }
        let snapshot = currentPlaybackDiagnosticsSnapshot()
        let previousIncidents = playbackDiagnosticsSession.storyboard.incidents
        playbackDiagnosticsSession.ingest(snapshot)
        playbackDiagnosticsLastSnapshot = snapshot.replacingStoryboard(
            playbackDiagnosticsSession.storyboard
        )
        logPlaybackDiagnosticsIncidentTransitions(
            from: previousIncidents,
            to: playbackDiagnosticsSession.storyboard.incidents
        )
    }

    private func currentPlaybackDiagnosticsSnapshot() -> PlaybackDiagnosticsSnapshot {
        guard let avPlayer = currentPlayer as? AVPlayerWrapper else {
            return .unavailable(.unsupportedBackend)
        }
        return avPlayer.fetchPlaybackDiagnostics(
            monitoringEnabled: isPlaybackHealthMonitoringEnabled,
            recentHealthEvents: recentPlaybackHealthEvents,
            history: playbackDiagnosticsHistory,
            storyboard: playbackDiagnosticsSession.storyboard
        )
    }

    private func endPlaybackDiagnosticsSampling(reason: String) {
        guard playbackDiagnosticsSampleCancellable != nil else { return }
        recordPlaybackDiagnosticsSample()
        playbackDiagnosticsSession.end(at: Date())
        playbackDiagnosticsLastSnapshot = playbackDiagnosticsLastSnapshot?
            .replacingStoryboard(playbackDiagnosticsSession.storyboard)
        playbackDiagnosticsSampleCancellable?.cancel()
        playbackDiagnosticsSampleCancellable = nil
        playbackDiagnosticsLifecycleLogger.info(
            "diagnostics session ended reason=\(reason, privacy: .public)"
        )
    }

    private func logPlaybackDiagnosticsIncidentTransitions(
        from previous: [PlaybackDiagnosticsAutomaticIncident],
        to current: [PlaybackDiagnosticsAutomaticIncident]
    ) {
        let priorByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        for incident in current {
            guard let prior = priorByID[incident.id] else {
                playbackDiagnosticsLifecycleLogger.notice(
                    "diagnostics incident opened kind=\(incident.kind.rawValue, privacy: .public) id=\(incident.id.uuidString, privacy: .private(mask: .hash))"
                )
                continue
            }
            if prior.state != incident.state {
                playbackDiagnosticsLifecycleLogger.info(
                    "diagnostics incident closed kind=\(incident.kind.rawValue, privacy: .public) id=\(incident.id.uuidString, privacy: .private(mask: .hash))"
                )
            } else if prior.evidenceIDs.count != incident.evidenceIDs.count {
                playbackDiagnosticsLifecycleLogger.info(
                    "diagnostics incident updated kind=\(incident.kind.rawValue, privacy: .public) id=\(incident.id.uuidString, privacy: .private(mask: .hash))"
                )
            }
        }
    }
    #endif
}

// MARK: - Player State Observation
extension PlayerManager {
    private func observePlayerState() {
        stateCancellables.removeAll()
        
        if let stateSource = currentPlayer as? PlayerStateSource {
            stateSource.onRuntimeStateChange = { [weak self] state in
                self?.applyRuntimeState(state)
            }
            stateSource.startRuntimeStateUpdates()
            return
        }

        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let player = self.currentPlayer else { return }
                
                self.isPlaying = player.isPlaying
                self.isBuffering = player.isBuffering
                self.currentTime = Self.nonnegativeFinite(player.currentTime)
                self.duration = Self.nonnegativeFinite(player.duration)
                self.bufferedDuration = Self.nonnegativeFinite(player.bufferedDuration)
            }
            .store(in: &stateCancellables)
    }
    
    public func resetPlayer() {
        resetPlayer(clearMediaContext: true)
        AudioSessionManager.shared.deactivateAudioSession(for: self)
    }

    private func resetPlayer(clearMediaContext: Bool) {
        cancelPendingPlaybackResume()
        cancelPlaybackRetry()
        cancelExternalEpisodeNavigation(clearHandler: clearMediaContext)
        gestureManager.reset()
        #if os(macOS)
        endPlaybackDiagnosticsSampling(reason: "player reset")
        resetPlaybackDiagnosticsHistory()
        #endif

        if let stateSource = currentPlayer as? PlayerStateSource {
            stateSource.stopRuntimeStateUpdates()
            stateSource.onRuntimeStateChange = nil
        }
        
        if let eventSource = currentPlayer as? PlayerEventSource {
            eventSource.lifecycleReporter = nil
        }
        
        currentPlayer?.stop()
        currentPlayer = nil
        currentProvider = nil
        activeBuiltInPlayerType = nil
        trackManager = nil
        playbackManager = nil
        
        isPlaying = false
        isBuffering = false
        isPiPActive = false
        if clearMediaContext {
            currentTime = 0
        }
        duration = 0
        bufferedDuration = 0
        shouldResumePlaybackAfterStall = false
        
        userInteracting = false
        isLocked = false
        isMediaReady = false
        isVideoEnded = false
        shouldDismiss = false
        clearError()
        lastRuntimeStateDebugSummary = nil
        #if os(macOS)
        resetPlaybackDiagnosticsHistory()
        #endif
        
        selectedAudio = nil
        selectedSubtitle = nil
        availableAudioTracks = []
        availableSubtitles = []
        if clearMediaContext {
            playerItem = nil
            playerItems = []
            currentPlayerItemIndex = 0
            contentType = .movie
        }
        
        stateCancellables.removeAll()
    }

    private var shouldHoldPlaybackWakeLock: Bool {
        guard !shouldDismiss, !isVideoEnded else { return false }
        guard currentPlayer != nil || playerItem != nil else { return false }
        return isPlaying || isBuffering
    }

    private func refreshPlaybackWakeLock() {
        let shouldHoldWakeLock = shouldHoldPlaybackWakeLock
        guard shouldHoldWakeLock != isPlaybackWakeLockHeld else { return }
        isPlaybackWakeLockHeld = shouldHoldWakeLock

        PlaybackWakeLockCoordinator.shared.setPlaybackActive(shouldHoldWakeLock, for: self)
    }
}

extension PlayerManager {
    private func configureIntegrationsIfNeeded() {
        guard !integrationsConfigured else { return }
        longLivedCancellables.removeAll()
        configureAudioSessionCallbacks()
        configureCastCallbacks()
        GameControllerManager.shared.attachControllerHandlers(for: self)
        installNowPlayingIfNeeded()
        subscribeToCastState()
        subscribeToGameControllerEvents()
        integrationsConfigured = true
    }
    
    private func bindPlayerCallbacks(_ player: PlayerProtocol) {
        if let eventSource = player as? PlayerEventSource {
            eventSource.lifecycleReporter = self
        }
    }
    
    private func configureCastCallbacks() {
        castManager.currentPlayerItemProvider = { [weak self] in
            self?.playerItem
        }

        castManager.currentPlaybackPositionProvider = { [weak self] in
            guard let self else { return nil }
            return Self.nonnegativeFinite(self.currentPlayer?.currentTime ?? self.currentTime)
        }
        
        castManager.onError = { [weak self] error in
            self?.reportError(error)
        }
        
        castManager.onDismissRequested = { [weak self] in
            self?.shouldDismiss = true
        }

    }
    
    private func configureAudioSessionCallbacks() {
        AudioSessionManager.shared.onPauseRequested = { [weak self] in
            self?.pause()
        }

        AudioSessionManager.shared.onResumeRequested = { [weak self] in
            self?.play()
        }

        AudioSessionManager.shared.isPlayingProvider = { [weak self] in
            self?.isPlaybackRequested ?? false
        }
    }

    /// Releases every app-global resource PlayerKit acquired, and stops playback.
    ///
    /// PlayerKit reaches outside its own object graph in several places — the
    /// shared `AVAudioSession`, screen brightness, the idle-timer override, and
    /// process-wide `GCController` handlers. `PlayerManager` is a singleton and
    /// therefore never deinits, so without an explicit teardown all of those
    /// stayed acquired for the remaining lifetime of the host process once the
    /// player had been shown even once.
    ///
    /// Call this when the player UI goes away. `PlayerView` does it from
    /// `onDisappear`; hosts driving `PlayerManager` directly should call it
    /// themselves. It is idempotent.
    public func tearDown() {
        debugLog("Tearing down player manager.")

        resetPlayer(clearMediaContext: true)

        gestureManager.reset()
        gestureManager.restoreSystemBrightness()
        GameControllerManager.shared.releaseControllerHandlers(for: self)
        releaseNowPlaying()
        isPlaybackWakeLockHeld = false
        PlaybackWakeLockCoordinator.shared.setPlaybackActive(false, for: self)
        AudioSessionManager.shared.deactivateAudioSession(for: self)
        longLivedCancellables.removeAll()
        castManager.detachPlayerSession()
        castManager.currentPlayerItemProvider = nil
        castManager.currentPlaybackPositionProvider = nil
        castManager.onError = nil
        castManager.onDismissRequested = nil
        AudioSessionManager.shared.onPauseRequested = nil
        AudioSessionManager.shared.onResumeRequested = nil
        AudioSessionManager.shared.isPlayingProvider = nil

        // Let the integrations rebuild on the next play so a torn-down manager
        // can be reused rather than being permanently inert.
        integrationsConfigured = false
    }
    
    private func configureOrientationCallbacks() {
        orientationManager.onPortraitOrientation = { [weak self] in
            self?.setGravityToDefault()
            self?.gestureManager.refreshAccessibilityState()
        }
    }

    private func applyRuntimeState(_ state: PlayerRuntimeState) {
        if isPlaying != state.isPlaying {
            isPlaying = state.isPlaying
        }
        if isBuffering != state.isBuffering {
            isBuffering = state.isBuffering
        }
        currentTime = Self.nonnegativeFinite(state.currentTime)
        duration = Self.nonnegativeFinite(state.duration)
        bufferedDuration = Self.nonnegativeFinite(state.bufferedDuration)
        logRuntimeStateIfChanged(state)

        if hasPlaybackProgressedSinceResumeReference(currentTime: state.currentTime) {
            cancelPendingPlaybackResume()
        }
    }
}

extension PlayerManager: PlayerLifecycleReporting {
    public func playerDidBecomeReady() {
        isMediaReady = true
        debugLog(
            "Player became ready current=\(debugInterval(currentTime)) " +
            "duration=\(debugInterval(duration)) shouldResume=\(shouldResumePlaybackAfterStall)"
        )
        schedulePlaybackResumeIfNeeded(trigger: "media-ready")
        refreshNowPlayingInfo(force: true)
    }

    private func performPlaybackResumeAttempt() {
        debugLog(
            "Performing playback resume attempt current=\(debugInterval(currentTime)) " +
            "mediaReady=\(isMediaReady) playerIsPlaying=\(currentPlayer?.isPlaying ?? false) " +
            "buffering=\(currentPlayer?.isBuffering ?? false)"
        )
        guard currentPlayer != nil, let playbackManager else {
            shouldResumePlaybackAfterStall = false
            isPlaying = false
            isBuffering = false
            return
        }
        if let mediaReporter = currentPlayer as? PlayerMediaAvailabilityReporting,
           !mediaReporter.hasLoadedMedia {
            shouldResumePlaybackAfterStall = false
            isPlaying = false
            isBuffering = false
            AudioSessionManager.shared.deactivateAudioSession(for: self)
            return
        }
        if playbackResumeProgressReferenceTime == nil {
            playbackResumeProgressReferenceTime = Self.nonnegativeFinite(
                currentPlayer?.currentTime ?? currentTime
            )
        }
        playbackManager.play()
        isPlaying = true
        isBuffering = currentPlayer?.isBuffering ?? true
    }

    private func schedulePlaybackResumeIfNeeded(trigger: String) {
        guard shouldResumePlaybackAfterStall else {
            debugLog("Playback resume skipped because shouldResumePlaybackAfterStall is false. trigger=\(trigger)")
            cancelPendingPlaybackResume()
            return
        }

        debugLog(
            "Scheduling playback resume. trigger=\(trigger) current=\(debugInterval(currentTime)) " +
            "mediaReady=\(isMediaReady) playerIsPlaying=\(currentPlayer?.isPlaying ?? false) " +
            "buffering=\(currentPlayer?.isBuffering ?? false)"
        )
        let resumeProgressReferenceTime = playbackResumeProgressReferenceTime
            ?? Self.nonnegativeFinite(currentPlayer?.currentTime ?? currentTime)
        cancelPendingPlaybackResume()
        playbackResumeProgressReferenceTime = resumeProgressReferenceTime
        playbackResumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.playbackResumeTask = nil }

            let retryDelays: [UInt64] = [
                0,
                150_000_000,
                350_000_000,
                750_000_000,
                1_500_000_000,
            ]
            for delay in retryDelays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }

                guard !Task.isCancelled else { return }
                guard self.shouldResumePlaybackAfterStall, self.isMediaReady else { return }

                if self.hasPlaybackProgressedSinceResumeReference(
                    currentTime: self.currentPlayer?.currentTime ?? self.currentTime
                ) {
                    self.debugLog("Playback resume completed after progress advanced. trigger=\(trigger)")
                    return
                }

                self.debugLog("Retrying playback resume. trigger=\(trigger)")
                self.performPlaybackResumeAttempt()
            }
        }
    }

    private func hasPlaybackProgressedSinceResumeReference(currentTime: Double) -> Bool {
        guard let playbackResumeProgressReferenceTime else { return false }
        guard currentTime.isFinite else { return false }
        return currentTime > playbackResumeProgressReferenceTime + 0.15
    }
    
    public func playerDidUpdateTracks() {
        refreshTrackInfo()
    }
    
    public func playerDidEndPlayback() {
        shouldResumePlaybackAfterStall = false
        #if os(macOS)
        endPlaybackDiagnosticsSampling(reason: "playback ended")
        #endif
        videoDidEnd()
    }

    public func playerDidStall() {
        isBuffering = true
        let stalledTime = Self.nonnegativeFinite(currentPlayer?.currentTime ?? currentTime)
        debugLog(
            "Player stalled current=\(debugInterval(stalledTime)) " +
            "buffered=\(debugInterval(bufferedDuration)) shouldResume=\(shouldResumePlaybackAfterStall)"
        )

        guard shouldResumePlaybackAfterStall else {
            debugLog("Ignoring stall recovery because playback is paused. time=\(stalledTime)")
            return
        }

        schedulePlaybackResumeIfNeeded(trigger: "stall")
    }
    
    public func playerDidChangePiPState(isActive: Bool) {
        isPiPActive = isActive
        if isActive,
           let lastError,
           case .pictureInPictureFailed = lastError {
            clearError()
        }
    }

    public func playerDidEncounterNonfatalError(_ error: PlayerKitError) {
        reportError(error)
    }

    public func playerDidFail(with error: PlayerKitError) {
        cancelPendingPlaybackResume()
        shouldResumePlaybackAfterStall = false
        isPlaying = false
        isBuffering = false
        isMediaReady = false
        AudioSessionManager.shared.deactivateAudioSession(for: self)

        #if os(macOS)
        endPlaybackDiagnosticsSampling(reason: "playback failed")
        #endif
        reportTerminalPlaybackError(error)
    }
}

extension PlayerManager {
    private func subscribeToCastState() {
        isCasting = castManager.isCasting
        isCastingAvailable = castManager.isCastingAvailable

        castManager.$isCasting
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.isCasting = value
            }
            .store(in: &longLivedCancellables)

        castManager.$isCastingAvailable
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.isCastingAvailable = value
            }
            .store(in: &longLivedCancellables)
    }

    private func subscribeToGameControllerEvents() {
        GameControllerManager.shared.controllerEventPublisher
            .sink { [weak self] event in
                guard let self = self else { return }
                
                switch event {
                case .playPause:
                    self.isPlaybackRequested ? self.pause() : self.play()
                    
                case .rewind:
                    self.scrubBackward(by: 10)
                    
                case .fastForward:
                    self.scrubForward(by: 10)
                    
                case .previousVideo:
                    self.playPrevious()
                    
                case .nextVideo:
                    self.playNext()
            
                case .scrubStarted:
                    self.isSeeking = true
                    
                case .scrubEnded:
                    self.isSeeking = false
                    
                case .fastForwardAmount(let amount):
                    self.scrubForward(by: amount)
                    
                case .rewindAmount(let amount):
                    self.scrubBackward(by: amount)
                    
                case .closePlayer:
                    self.shouldDismiss = true
                    
                case .focusUp:
                    break
                    
                case .focusDown:
                    break
                    
                case .focusSelect:
                    break
                }
            }
            .store(in: &longLivedCancellables)
    }
}
