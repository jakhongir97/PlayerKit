import Foundation
import Combine

enum DubSwitchPolicy {
    private static let preparationLeadSeconds = 6.0
    private static let activationHeadroomSeconds = 8.0

    static func shouldSwitchToDubbedMaster(
        isDubPlayable: Bool,
        isFinalized: Bool,
        allowProgressiveSwitching: Bool
    ) -> Bool {
        _ = isFinalized
        _ = allowProgressiveSwitching
        return isDubPlayable
    }

    static func hasPlayableDubData(
        segmentsReady: Int,
        totalSegments: Int,
        chunkCount: Int,
        resumePosition: Double,
        knownDuration: Double,
        isFinalized: Bool = false,
        coverageStart: Double? = nil,
        coverageEnd: Double? = nil
    ) -> Bool {
        guard hasTimelineSignal(
            segmentsReady: segmentsReady,
            totalSegments: totalSegments,
            chunkCount: chunkCount,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd
        ) else { return false }
        guard segmentsReady >= 3 else { return false }
        if isFinalized {
            return true
        }
        if let windowAllowsPlayback = timelineWindowAllowsPlayback(
            resumePosition: resumePosition,
            coverageEnd: coverageEnd
        ) {
            return windowAllowsPlayback
        }

        return fallbackCoverageCheck(
            segmentsReady: segmentsReady,
            totalSegments: totalSegments,
            resumePosition: resumePosition,
            knownDuration: knownDuration,
            requiredLead: activationHeadroomSeconds
        )
    }

    static func shouldPrepareDubMaster(
        segmentsReady: Int,
        totalSegments: Int,
        chunkCount: Int,
        resumePosition: Double,
        knownDuration: Double,
        isFinalized: Bool = false,
        coverageStart: Double? = nil,
        coverageEnd: Double? = nil
    ) -> Bool {
        guard hasTimelineSignal(
            segmentsReady: segmentsReady,
            totalSegments: totalSegments,
            chunkCount: chunkCount,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd
        ) else { return false }
        if isFinalized {
            return true
        }
        if let coverageEnd, coverageEnd.isFinite {
            return coverageEnd >= max(resumePosition, 0) + preparationLeadSeconds
        }

        return fallbackCoverageCheck(
            segmentsReady: segmentsReady,
            totalSegments: totalSegments,
            resumePosition: resumePosition,
            knownDuration: knownDuration,
            requiredLead: preparationLeadSeconds
        )
    }

    static func shouldRetryAfterFailure(
        segmentsReady: Int,
        totalSegments: Int,
        chunkCount: Int,
        resumePosition: Double,
        knownDuration: Double,
        status: String?,
        coverageStart: Double? = nil,
        coverageEnd: Double? = nil
    ) -> Bool {
        let isFinalized = isCompletionStatus(status)
        if shouldPrepareDubMaster(
            segmentsReady: segmentsReady,
            totalSegments: totalSegments,
            chunkCount: chunkCount,
            resumePosition: resumePosition,
            knownDuration: knownDuration,
            isFinalized: isFinalized,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd
        ) {
            return true
        }

        return isFinalized
    }

    private static func hasTimelineSignal(
        segmentsReady: Int,
        totalSegments: Int,
        chunkCount: Int,
        coverageStart: Double?,
        coverageEnd: Double?
    ) -> Bool {
        if chunkCount > 0 {
            return true
        }

        if let coverageEnd,
           coverageEnd.isFinite,
           coverageEnd > 0 {
            return true
        }

        if let coverageStart,
           coverageStart.isFinite,
           coverageStart >= 0 {
            return true
        }

        return segmentsReady > 0 && totalSegments > 0
    }

    private static func timelineWindowAllowsPlayback(
        resumePosition: Double,
        coverageEnd: Double?
    ) -> Bool? {
        // coverageStart/coverageEnd describe translated dialogue chunks, while the HLS
        // master can still provide lead/tail audio outside those chunk boundaries.
        guard let coverageEnd,
              coverageEnd.isFinite,
              coverageEnd > 0 else {
            return nil
        }

        let effectiveResumePosition = max(resumePosition, 0)
        return coverageEnd >= effectiveResumePosition + activationHeadroomSeconds
    }

    private static func isCompletionStatus(_ status: String?) -> Bool {
        let normalizedStatus = (status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedStatus == "complete"
            || normalizedStatus == "completed"
            || normalizedStatus == "ready"
    }

    private static func fallbackCoverageCheck(
        segmentsReady: Int,
        totalSegments: Int,
        resumePosition: Double,
        knownDuration: Double,
        requiredLead: Double
    ) -> Bool {
        guard resumePosition > 0 else { return true }
        guard totalSegments > 0 else { return true }
        guard knownDuration > 0 else { return true }

        let translatedFraction = Double(segmentsReady) / Double(totalSegments)
        let translatedCoverageSeconds = translatedFraction * knownDuration
        return translatedCoverageSeconds >= resumePosition + requiredLead
    }
}

public enum PlayerEpisodeNavigationDirection: Equatable {
    case previous
    case next
}

public class PlayerManager: ObservableObject {
    public static let shared = PlayerManager()
    
    // State management
    @Published var isPlaying: Bool = false {
        didSet {
            refreshPlaybackWakeLock()
        }
    }
    @Published var isBuffering: Bool = false {
        didSet {
            refreshPlaybackWakeLock()
        }
    }
    @Published public private(set) var isPlaybackRequested: Bool = false
    @Published public var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var bufferedDuration: Double = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var isSeeking: Bool = false
    @Published var isCasting: Bool = false
    @Published var isPiPActive: Bool = false
    @Published var isCastingAvailable: Bool = false
    @Published var areControlsVisible: Bool = true
    @Published var isLocked: Bool = false {
        didSet {
            NotificationCenter.default.post(name: .PlayerKitLocked, object: isLocked)
        }
    }
    @Published var userInteracting: Bool = false
    
    // Track identifiers
    @Published var selectedAudio: TrackInfo?
    @Published var selectedSubtitle: TrackInfo?
    @Published var availableAudioTracks: [TrackInfo] = []
    @Published var availableSubtitles: [TrackInfo] = []
    private var savedAudio: TrackInfo?
    private var savedSubtitle: TrackInfo?
    
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
    @Published var playerItem: PlayerItem?
    @Published var playerItems: [PlayerItem] = []
    @Published var currentPlayerItemIndex: Int = 0
    @Published public var contentType: PlayerContentType = .movie
    @Published public private(set) var externalEpisodeCanPlayPrevious: Bool = false
    @Published public private(set) var externalEpisodeCanPlayNext: Bool = false
    @Published public private(set) var isExternalEpisodeNavigationInProgress: Bool = false
    @Published var shouldDismiss: Bool = false {
        didSet {
            playbackManager?.stop()
            refreshPlaybackWakeLock()
        }
    }
    @Published public private(set) var lastError: PlayerKitError?
    @Published public private(set) var isDubLoading: Bool = false
    @Published public private(set) var dubSessionID: String?
    @Published public private(set) var dubStatus: String?
    @Published public private(set) var dubProgressMessage: String?
    @Published public private(set) var dubSegmentsReady: Int = 0
    @Published public private(set) var dubTotalSegments: Int = 0
    @Published public private(set) var dubWarningMessage: String?
    @Published public private(set) var isDubbedPlaybackActive: Bool = false
    @Published public private(set) var availableDubLanguages: [DubberLanguageOption] = []
    @Published public private(set) var availableDubSourceLanguages: [DubberLanguageOption] = []
    @Published public private(set) var selectedDubLanguageCode: String = "uz"
    @Published public private(set) var selectedDubSourceLanguageCode: String = "auto"
    @Published private(set) var dubActivityLog: [DubberActivityLogEntry] = []
    @Published var isDubberEnabled: Bool = false
    @Published var isDubberSheetPinned: Bool = false
    @Published public var isMediaReady: Bool = false {
        didSet {
            if isMediaReady {
                refreshTrackInfo()
                NotificationCenter.default.post(name: .PlayerKitMediaReady, object: nil)
            }
        }
    }
    @Published var isVideoEnded: Bool = false {
        didSet {
            refreshPlaybackWakeLock()
        }
    }
    
    // Managers for different responsibilities
    var playbackManager: PlaybackManager?
    var trackManager: TrackManager?
    lazy var castManager = CastManager.shared
    let gestureManager = GestureManager()
    let orientationManager = OrientationManager()
    
    // Lazy initialization for controlVisibilityManager
    lazy var controlVisibilityManager: ControlVisibilityManager = {
        ControlVisibilityManager(playerManager: self)
    }()
    
    private var currentProvider: PlayerProvider?
    public weak var currentPlayer: PlayerProtocol? {
        didSet {
            refreshPlaybackWakeLock()
        }
    }
    private var lastPosition: Double = 0
    private var integrationsConfigured = false
    private var dubberConfiguration: DubberConfiguration?
    private let dubberClient = DubberClient()
    // Stable mode still avoids the local progressive fallback path, but HLS can switch as soon as it is playable.
    private let allowProgressiveDubSwitching = false
    private var dubberPollTask: Task<Void, Never>?
    private var dubberEventsTask: Task<Void, Never>?
    private var dubberStallWatchdogTask: Task<Void, Never>?
    private var dubberSessionStartedAt: Date?
    private var dubberLastEventAt: Date?
    private var dubberEventCount: Int = 0
    private var hasAutoSelectedDubTrack = false
    private var hasLoadedDubbedMaster = false
    private var hasAppliedSourceAudioFallback = false
    private var dubTargetLanguageCode: String?
    private var activeDubSourceItem: PlayerItem?
    private var dubSwitchAttemptCount = 0
    private var hasDubSwitchFailed = false
    private var dubReadyChunkCount = 0
    private var dubCoverageStartTime: Double?
    private var dubCoverageEndTime: Double?
    private var dubCompletionObservedAt: Date?
    private var dubCompletionResyncTask: Task<Void, Never>?
    private var dubPlaybackRecoveryTask: Task<Void, Never>?
    private var hasScheduledDubCompletionResync = false
    private var dubAudioProbeTask: Task<Void, Never>?
    private var dubFallbackPreparationTask: Task<Void, Never>?
    private let dubFallbackPlayer = DubAudioFallbackPlayer()
    private var isLocalDubFallbackActive = false
    private var isLocalDubFallbackPrepared = false
    private var localDubFallbackCoverageStartTime: Double?
    private var localDubFallbackCoverageEndTime: Double?
    private var lastLocalDubFallbackWaitingSignature: String?
    private var lastDubActivitySignature: String?
    private var lastDubStatusSummary: String?
    private var lastDubProgressSummary: String?
    private var lastDubSegmentSummary: String?
    private var lastRuntimeStateDebugSummary: String?
    
    private var stateCancellables = Set<AnyCancellable>()
    private var longLivedCancellables = Set<AnyCancellable>()
    private var isPlaybackWakeLockHeld = false
    private var shouldResumePlaybackAfterStall: Bool {
        get { isPlaybackRequested }
        set { isPlaybackRequested = newValue }
    }
    private var playbackResumeTask: Task<Void, Never>?
    private var playbackResumeProgressReferenceTime: Double?
    private var externalEpisodeNavigationHandler: (@MainActor (PlayerEpisodeNavigationDirection) async -> Bool)?
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
    private var primaryMuteController: PlayerMuteControlling? {
        currentPlayer as? PlayerMuteControlling
    }
    private var preciseSeekController: PlayerPreciseSeeking? {
        currentPlayer as? PlayerPreciseSeeking
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
        configurePlayer(
            type: type,
            clearMediaContext: true,
            clearDubWorkflow: true
        )
    }

    func ensurePlayerConfigured(type: PlayerType? = nil) {
        if let type {
            let resolvedType = PlayerType.resolved(type)
            if selectedPlayerType != resolvedType {
                if currentPlayer != nil || playerItem != nil || !playerItems.isEmpty || hasActiveDubWorkflow {
                    switchPlayer(to: resolvedType)
                } else {
                    setPlayer(type: resolvedType)
                }
            }
            return
        }

        if currentPlayer == nil {
            setPlayer(type: type)
        }
    }

    private func configurePlayer(
        type: PlayerType,
        clearMediaContext: Bool,
        clearDubWorkflow: Bool
    ) {
        let resolvedType = PlayerType.resolved(type)
        if resolvedType != type {
            debugLog("Requested unsupported player type=\(type). Falling back to \(resolvedType).")
        }
        configureIntegrationsIfNeeded()
        debugLog(
            "Setting player type=\(resolvedType) " +
            "clearMediaContext=\(clearMediaContext) " +
            "clearDubWorkflow=\(clearDubWorkflow)"
        )
        resetPlayer(
            clearMediaContext: clearMediaContext,
            clearDubWorkflow: clearDubWorkflow
        )
        selectedPlayerType = resolvedType
        let provider = PlayerFactory.getProvider(for: resolvedType)
        setupPlayer(provider: provider)
    }

    private func prepareDubWorkflowForBackendSwitch() {
        guard hasActiveDubWorkflow else { return }
        debugLog(
            "Preserving dub workflow while switching backend. " +
            "session_id=\(dubSessionID ?? "nil") " +
            "dubbed_master=\(hasLoadedDubbedMaster) " +
            "local_fallback=\(isLocalDubFallbackActive)"
        )
        cancelDubCompletionResync()
        cancelDubPlaybackRecovery()
        if hasLoadedDubbedMaster, !isLocalDubFallbackActive {
            hasAutoSelectedDubTrack = false
            hasAppliedSourceAudioFallback = false
            isDubbedPlaybackActive = false
        }
        if isLocalDubFallbackActive {
            dubFallbackPlayer.pause()
        }
        setPrimaryPlayerMuted(false)
    }
    
    private func setupPlayer(provider: PlayerProvider) {
        currentProvider = provider
        let player = provider.createPlayer()
        debugLog("Created player instance type=\(String(reflecting: type(of: player)))")
        currentPlayer = player
        bindPlayerCallbacks(player)
        
        // Initialize managers with the player instance
        playbackManager = PlaybackManager(player: player, playerManager: self)
        trackManager = TrackManager(player: player)
        
        observePlayerState()
    }
    
    // MARK: - Switch Player at Runtime
    
    public func switchPlayer(to type: PlayerType) {
        let resolvedType = PlayerType.resolved(type)
        guard selectedPlayerType != resolvedType else { return } // No need to switch if already selected
        let resumePosition = max(currentPlayer?.currentTime ?? currentTime, 0)
        lastPosition = resumePosition
        saveCurrentTracks()
        let snapshot = makePlaybackSwitchSnapshot(resumePosition: resumePosition)
        configurePlayer(
            type: resolvedType,
            clearMediaContext: false,
            clearDubWorkflow: false
        )

        restorePlaybackSwitchSnapshot(snapshot)

        if let currentItem = snapshot.currentItem {
            load(url: currentItem.url, lastPosition: currentItem.lastPosition)
            if !snapshot.shouldResumePlayback {
                pause()
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

    private func makePlayerItemCopy(from sourceItem: PlayerItem, resumePosition: Double?) -> PlayerItem {
        PlayerItem(
            title: sourceItem.title,
            description: sourceItem.description,
            dubTitle: sourceItem.dubTitle,
            url: sourceItem.url,
            posterUrl: sourceItem.posterUrl,
            castVideoUrl: sourceItem.castVideoUrl,
            externalPlaybackURL: sourceItem.externalPlaybackURL,
            externalPlaybackContentType: sourceItem.externalPlaybackContentType,
            externalPlaybackDuration: sourceItem.externalPlaybackDuration,
            lastPosition: resumePosition,
            episodeIndex: sourceItem.episodeIndex
        )
    }
    
    public func load(playerItem: PlayerItem) {
        cancelDubWorkflowIfNeededForContentChange(nextURL: playerItem.url)
        self.playerItem = playerItem
        if playerItems.isEmpty {
            contentType = playerItem.episodeIndex == nil ? .movie : .episode
        }
        load(url: playerItem.url, lastPosition: playerItem.lastPosition)
    }

    @MainActor
    public func configureDubber(_ configuration: DubberConfiguration?) {
        dubberConfiguration = configuration
        isDubberEnabled = configuration != nil
        if let configuration {
            availableDubLanguages = configuration.supportedLanguages
            availableDubSourceLanguages = configuration.supportedSourceLanguages
            selectedDubLanguageCode = normalizedDubSelection(
                current: selectedDubLanguageCode,
                options: configuration.supportedLanguages,
                fallback: configuration.defaultLanguage
            )
            selectedDubSourceLanguageCode = normalizedDubSelection(
                current: selectedDubSourceLanguageCode,
                options: configuration.supportedSourceLanguages,
                fallback: configuration.defaultTranslateFrom
            )
            debugLog(
                "Dubber configured. base=\(configuration.baseURL.debugDescription) " +
                "timeout=\(dubDebugInterval(configuration.eventStreamRequestTimeout)) " +
                "reconnect_delay=\(dubDebugInterval(configuration.eventStreamReconnectDelay)) " +
                "max_retries=\(retryBudgetLabel(configuration))"
            )
        } else {
            availableDubLanguages = []
            availableDubSourceLanguages = []
            selectedDubLanguageCode = "uz"
            selectedDubSourceLanguageCode = "auto"
            debugLog("Dubber disabled.")
            cancelDubWorkflow(reason: "Dubber integration disabled.")
        }
    }

    @MainActor
    public func setDubLanguage(code: String) {
        guard availableDubLanguages.contains(where: { $0.code == code }) else { return }
        selectedDubLanguageCode = code
        userInteracted()
    }

    @MainActor
    public func setDubSourceLanguage(code: String) {
        guard availableDubSourceLanguages.contains(where: { $0.code == code }) else { return }
        selectedDubSourceLanguageCode = code
        userInteracted()
    }

    @MainActor
    public func stopDubbingAndReturnToOriginalAudio() {
        stopDubbingAndReturnToOriginalAudio(reason: "User requested to stop dubbing.")
        HapticsManager.shared.triggerImpactFeedback(style: .soft)
    }

    @MainActor
    public func startDubbedPlayback(language: String? = nil, translateFrom: String? = nil) async {
        guard !isDubLoading else {
            debugLog("Ignoring duplicate dubbed playback start while already loading.")
            return
        }
        guard let configuration = dubberConfiguration else {
            reportError(.dubberNotConfigured)
            return
        }
        guard let sourceItem = playerItem else {
            reportError(.dubberSourceMissing)
            return
        }

        let resolvedLanguage = language ?? selectedDubLanguageCode
        let resolvedTranslateFrom = translateFrom ?? selectedDubSourceLanguageCode

        ensurePlayerConfigured()
        cancelDubberPolling()
        cancelDubberEvents()
        cancelDubberStallWatchdog()
        cancelDubCompletionResync()
        cancelDubPlaybackRecovery()
        dubAudioProbeTask?.cancel()
        dubAudioProbeTask = nil
        dubFallbackPreparationTask?.cancel()
        dubFallbackPreparationTask = nil
        dubFallbackPlayer.stop()
        isLocalDubFallbackActive = false
        isLocalDubFallbackPrepared = false
        localDubFallbackCoverageStartTime = nil
        localDubFallbackCoverageEndTime = nil
        lastLocalDubFallbackWaitingSignature = nil
        setPrimaryPlayerMuted(false)
        saveCurrentTracks()
        hasAutoSelectedDubTrack = false
        hasLoadedDubbedMaster = false
        hasAppliedSourceAudioFallback = false
        dubSwitchAttemptCount = 0
        hasDubSwitchFailed = false
        isDubbedPlaybackActive = false
        dubTargetLanguageCode = resolvedLanguage.lowercased()
        activeDubSourceItem = sourceItem
        dubberSessionStartedAt = Date()
        dubberLastEventAt = nil
        dubberEventCount = 0
        isDubLoading = true
        dubStatus = nil
        dubProgressMessage = "Starting..."
        dubSegmentsReady = 0
        dubTotalSegments = 0
        dubWarningMessage = nil
        dubReadyChunkCount = 0
        dubCoverageStartTime = nil
        dubCoverageEndTime = nil
        dubCompletionObservedAt = nil
        resetDubActivityLog()
        clearError()
        userInteracted()
        HapticsManager.shared.triggerSelectionFeedback()
        recordDubActivity(
            "Starting a new dubbed voice track. The original sound stays on until the dub is safe to play.",
            level: .info,
            signature: "dub-start"
        )
        debugLog(
            "Starting dubbed playback. source=\(sourceItem.url.debugDescription) " +
            "language=\(resolvedLanguage) " +
            "translate_from=\(resolvedTranslateFrom)"
        )

        do {
            let sessionID = try await dubberClient.startSession(
                sourceURL: sourceItem.url,
                title: sourceItem.preferredDubSessionTitle,
                configuration: configuration,
                language: resolvedLanguage,
                translateFrom: resolvedTranslateFrom
            )

            dubSessionID = sessionID
            recordDubActivity(
                allowProgressiveDubSwitching
                    ? "Dubber connected. Waiting for the dubbed HLS stream to become playable."
                    : "Dubber connected. Keeping the original audio until the dubbed HLS stream becomes playable.",
                level: .success,
                signature: "dub-session-started"
            )
            debugLog("Dub session started. session_id=\(sessionID)")
            startDubberStallWatchdog(sessionID: sessionID)
            startDubberPolling(
                sessionID: sessionID,
                configuration: configuration,
                sourceItem: sourceItem
            )
            startDubberEvents(
                sessionID: sessionID,
                configuration: configuration,
                sourceItem: sourceItem
            )
        } catch let playerError as PlayerKitError {
            debugLog("Dubbed playback failed with PlayerKitError: \(playerError.localizedDescription)")
            recordDubActivity(
                friendlyDubberErrorMessage(for: playerError),
                level: .error
            )
            reportError(playerError)
            isDubLoading = false
            cancelDubberStallWatchdog()
        } catch {
            debugLog("Dubbed playback failed: \(error.localizedDescription)")
            recordDubActivity(
                "Dubber could not start right now. \(error.localizedDescription)",
                level: .error
            )
            reportError(.dubberRequestFailed(error.localizedDescription))
            isDubLoading = false
            cancelDubberStallWatchdog()
        }
    }
    
    public func loadEpisodes(playerItems: [PlayerItem], currentIndex: Int = 0 ) {
        self.playerItems = playerItems
        contentType = .episode
        currentPlayerItemIndex = currentIndex
        guard let playerItem = playerItems[safe: currentIndex] else { return }
        load(playerItem: playerItem)
    }
    
    // Loads a media URL into the current player
    private func load(url: URL, lastPosition: Double? = nil) {
        debugLog("Loading media. url=\(url.debugDescription) resume=\(lastPosition?.description ?? "nil")")
        cancelPendingPlaybackResume()
        clearError()
        isMediaReady = false
        isVideoEnded = false
        currentTime = max(lastPosition ?? 0, 0)
        bufferedDuration = 0
        isPlaying = true
        isBuffering = true
        shouldResumePlaybackAfterStall = true
        playbackResumeProgressReferenceTime = currentTime
        currentPlayer?.load(url: url, lastPosition: lastPosition)
        userInteracted()
    }

    var canStartDubbedPlayback: Bool {
        isDubberEnabled
            && !isDubLoading
            && playerItem != nil
            && (dubSessionID == nil || hasDubberIssue)
    }

    var dubProgressFraction: Double {
        if dubTotalSegments > 0 {
            return min(max(Double(dubSegmentsReady) / Double(dubTotalSegments), 0), 1)
        }

        if isDubbedPlaybackActive {
            return 1
        }

        if isDubLoading {
            return dubSessionID == nil ? 0.12 : 0.22
        }

        return 0
    }

    var hasDubberIssue: Bool {
        guard let lastError else { return false }

        switch lastError {
        case .dubberNotConfigured, .dubberSourceMissing, .dubberRequestFailed:
            return true
        default:
            return false
        }
    }

    var selectedDubLanguage: DubberLanguageOption? {
        availableDubLanguages.first(where: { $0.code == selectedDubLanguageCode })
    }

    var selectedDubSourceLanguage: DubberLanguageOption? {
        availableDubSourceLanguages.first(where: { $0.code == selectedDubSourceLanguageCode })
    }

    var dubEstimatedRemainingSeconds: TimeInterval? {
        guard isDubLoading else { return nil }
        guard dubTotalSegments > 0, dubSegmentsReady > 0 else { return nil }
        guard let startedAt = dubberSessionStartedAt else { return nil }

        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed >= 3 else { return nil }

        let remainingSegments = max(dubTotalSegments - dubSegmentsReady, 0)
        guard remainingSegments > 0 else { return 0 }

        let averageSecondsPerSegment = elapsed / Double(dubSegmentsReady)
        let estimate = averageSecondsPerSegment * Double(remainingSegments)
        guard estimate.isFinite else { return nil }
        return min(max(estimate, 1), 60 * 60)
    }

    var dubEstimatedRemainingLabel: String? {
        guard let seconds = dubEstimatedRemainingSeconds else { return nil }
        return formattedDubRemainingTime(seconds)
    }
    
    public func videoDidEnd() {
        guard duration != 0, currentTime + 1 > duration else { return }
        cancelPendingPlaybackResume()
        isPlaying = false
        isBuffering = false
        if contentType == .movie {
            // Dismiss the player immediately for movies
            isVideoEnded = true
        } else {
            // Check if there are more episodes to play
            playNext()
        }
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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.configureExternalEpisodeNavigation(
                    canPlayPrevious: canPlayPrevious,
                    canPlayNext: canPlayNext,
                    handler: handler
                )
            }
            return
        }

        externalEpisodeNavigationHandler = handler
        externalEpisodeCanPlayPrevious = canPlayPrevious
        externalEpisodeCanPlayNext = canPlayNext
    }

    public func updateExternalEpisodeNavigationAvailability(
        canPlayPrevious: Bool,
        canPlayNext: Bool
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateExternalEpisodeNavigationAvailability(
                    canPlayPrevious: canPlayPrevious,
                    canPlayNext: canPlayNext
                )
            }
            return
        }

        guard hasExternalEpisodeNavigation else { return }
        externalEpisodeCanPlayPrevious = canPlayPrevious
        externalEpisodeCanPlayNext = canPlayNext
    }

    public func clearExternalEpisodeNavigation() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.clearExternalEpisodeNavigation()
            }
            return
        }

        externalEpisodeNavigationHandler = nil
        externalEpisodeCanPlayPrevious = false
        externalEpisodeCanPlayNext = false
        isExternalEpisodeNavigationInProgress = false
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
        let playerItem = playerItems[index]
        load(playerItem: playerItem)
    }

    private var hasExternalEpisodeNavigation: Bool {
        contentType == .episode && externalEpisodeNavigationHandler != nil
    }

    private func handleExternalEpisodeNavigationIfNeeded(
        _ direction: PlayerEpisodeNavigationDirection
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

        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await handler(direction)
            self.isExternalEpisodeNavigationInProgress = false
        }

        return true
    }
}

// MARK: - Playback Controls
extension PlayerManager {
    public func reportError(_ error: PlayerKitError) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.reportError(error)
            }
            return
        }
        debugLog("Error reported: \(error.localizedDescription)")
        lastError = error
        NotificationCenter.default.post(name: .PlayerKitDidFail, object: error)
    }

    public func clearError() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.clearError()
            }
            return
        }
        lastError = nil
    }

    public func play() {
        debugLog(
            "Play requested current=\(debugInterval(currentTime)) " +
            "mediaReady=\(isMediaReady) playerIsPlaying=\(currentPlayer?.isPlaying ?? false) " +
            "buffering=\(currentPlayer?.isBuffering ?? false)"
        )
        shouldResumePlaybackAfterStall = true
        cancelPendingPlaybackResume()
        playbackResumeProgressReferenceTime = max(currentPlayer?.currentTime ?? currentTime, 0)
        performPlaybackResumeAttempt()
        userInteracted()
    }
    
    public func pause() {
        debugLog(
            "Pause requested current=\(debugInterval(currentTime)) " +
            "mediaReady=\(isMediaReady) playerIsPlaying=\(currentPlayer?.isPlaying ?? false)"
        )
        cancelPendingPlaybackResume()
        playbackManager?.pause()
        if isLocalDubFallbackActive {
            dubFallbackPlayer.pause()
        }
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
        cancelDubWorkflow(reason: "Playback stopped.")
        playbackManager?.stop()
        isPlaying = false
        isBuffering = false
        shouldResumePlaybackAfterStall = false
        userInteracted()
    }
    
    public func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        guard duration != 0 else {
            debugLog("Seek ignored because duration is zero. target=\(debugInterval(time))")
            completion?(false)
            return
        }
        let targetTime = min(max(time, 0), duration)
        debugLog(
            "Seek requested target=\(debugInterval(targetTime)) " +
            "current=\(debugInterval(currentTime)) shouldResume=\(shouldResumePlaybackAfterStall) " +
            "mediaReady=\(isMediaReady) playerIsPlaying=\(currentPlayer?.isPlaying ?? false)"
        )

        if shouldResumeSourcePlaybackDuringDubSeek(to: targetTime) {
            debugLog(
                "Seek moved outside dubbed window, resuming source playback. target=\(debugInterval(targetTime))"
            )
            continueDubWorkflowOnSourcePlayback(
                at: targetTime,
                reason: "Seek moved outside the currently translated dub window."
            )
            completion?(true)
            return
        }

        let shouldResumeAfterSeek = shouldResumePlaybackAfterStall
        let seekAction: (@escaping (Bool) -> Void) -> Void = { [weak self] completion in
            guard let self else {
                completion(false)
                return
            }

            if self.shouldUsePreciseDubSeek,
               let preciseSeekController = self.preciseSeekController {
                preciseSeekController.seekExactly(to: targetTime, completion: completion)
            } else {
                self.playbackManager?.seek(to: targetTime, completion: completion)
            }
        }

        seekAction { [weak self] success in
            guard let self else {
                completion?(false)
                return
            }

            if success {
                self.currentTime = targetTime
                if self.isLocalDubFallbackActive {
                    self.dubFallbackPlayer.seek(to: targetTime)
                }
                if self.dubSessionID != nil, self.hasLoadedDubbedMaster {
                    self.refreshTrackInfo()
                    self.reconcileDubTrackSelection(at: targetTime)
                }
                if shouldResumeAfterSeek {
                    self.debugLog(
                        "Seek succeeded and playback should resume. target=\(debugInterval(targetTime))"
                    )
                    self.playbackResumeProgressReferenceTime = targetTime
                    self.schedulePlaybackResumeIfNeeded(trigger: "seek")
                }
            } else {
                self.debugLog(
                    "Seek failed. target=\(debugInterval(targetTime)) current=\(debugInterval(self.currentTime))"
                )
            }
            completion?(success)
        }
    }
    
    public func scrubForward(by seconds: TimeInterval) {
        playbackManager?.scrubForward(by: seconds)
    }
    
    public func scrubBackward(by seconds: TimeInterval) {
        playbackManager?.scrubBackward(by: seconds)
    }
    
    public func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        playbackManager?.setPlaybackSpeed(speed)
        if isLocalDubFallbackActive {
            dubFallbackPlayer.sync(
                to: currentPlayer?.currentTime ?? currentTime,
                isPlaying: isPlaying,
                isBuffering: isBuffering,
                playbackSpeed: speed,
                forceSeek: false
            )
        }
    }
}

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
            "selected_audio=\(selectedAudio?.name ?? "nil") " +
            "selected_subtitle=\(selectedSubtitle?.name ?? "nil")"
        )

        applySavedTrackIdentifiers()
    }
    
    public func selectAudioTrack(track: TrackInfo) {
        selectedAudio = track
        trackManager?.selectAudioTrack(withID: track.id)
        userInteracted()
    }

    public func selectSubtitle(track: TrackInfo?) {
        selectedSubtitle = track
        trackManager?.selectSubtitle(withID: track?.id)
        userInteracted()
    }
    
    private func saveCurrentTracks() {
        savedAudio = selectedAudio
        savedSubtitle = selectedSubtitle
    }
    
    private func applySavedTrackIdentifiers() {
        if let savedAudio = savedAudio {
            if let matchedAudio = availableAudioTracks.first(where: { $0.id == savedAudio.id }) {
                selectAudioTrack(track: matchedAudio)
                self.savedAudio = nil
            } else if let matchedAudioByLang = availableAudioTracks.first(where: { $0.languageCode == savedAudio.languageCode }) {
                selectAudioTrack(track: matchedAudioByLang)
                self.savedAudio = nil
            }
        }
        
        if let savedSubtitle = savedSubtitle {
            if let matchedSubtitle = availableSubtitles.first(where: { $0.id == savedSubtitle.id }) {
                selectSubtitle(track: matchedSubtitle)
                self.savedSubtitle = nil
            } else if let matchedSubtitleByLang = availableSubtitles.first(where: { $0.languageCode == savedSubtitle.languageCode }) {
                selectSubtitle(track: matchedSubtitleByLang)
                self.savedSubtitle = nil
            }
        }
    }

    fileprivate func startDubberPolling(
        sessionID: String,
        configuration: DubberConfiguration,
        sourceItem: PlayerItem
    ) {
        cancelDubberPolling()
        debugLog("Starting dub poll loop. session_id=\(sessionID)")

        dubberPollTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    let poll = try await self.dubberClient.pollSession(
                        sessionID: sessionID,
                        configuration: configuration
                    )

                    await MainActor.run {
                        guard self.dubSessionID == sessionID else { return }
                        self.handleDubberPoll(
                            poll,
                            sessionID: sessionID,
                            configuration: configuration,
                            sourceItem: sourceItem
                        )
                    }
                } catch {
                    let isCancellation = self.isCancellationError(error) || Task.isCancelled

                    await MainActor.run {
                        guard self.dubSessionID == sessionID else { return }
                        if isCancellation {
                            self.debugLog("Dub poll cancelled. session_id=\(sessionID)")
                            return
                        }

                        self.debugLog(
                            "Dub poll failed. session_id=\(sessionID) " +
                            "error=\(self.networkErrorDebugDetails(error))"
                        )
                        self.recordDubActivity(
                            "Dubber status updates paused for a moment.",
                            level: .warning,
                            signature: "poll-failed"
                        )
                    }

                    if isCancellation {
                        break
                    }
                }

                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    break
                }
            }

            await MainActor.run {
                if self.dubSessionID == sessionID || self.dubSessionID == nil {
                    self.dubberPollTask = nil
                }
            }
        }
    }

    @MainActor
    fileprivate func handleDubberPoll(
        _ poll: DubberClient.PollResponse,
        sessionID: String,
        configuration: DubberConfiguration,
        sourceItem: PlayerItem
    ) {
        if let status = poll.status?.trimmingCharacters(in: .whitespacesAndNewlines),
           !status.isEmpty {
            dubStatus = status
            dubProgressMessage = status
            recordDubStatusIfNeeded(status)
        }

        dubSegmentsReady = poll.segmentsReady
        dubTotalSegments = poll.totalSegments
        dubReadyChunkCount = max(poll.chunks.count, 0)
        updateDubCoverageWindow(from: poll.chunks)
        recordDubSegmentsIfNeeded()

        if let rawError = poll.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawError.isEmpty {
            debugLog("Dub poll error. session_id=\(sessionID) error=\(rawError)")
            recordDubActivity(
                friendlySentence(from: rawError),
                level: .error,
                signature: "poll-error-\(rawError)"
            )
            reportError(.dubberRequestFailed(rawError))
            isDubLoading = false
            cancelDubberPolling()
            return
        }

        let isCompletionStatus = isCompletionState(poll.status)
        if isCompletionStatus {
            dubCompletionObservedAt = dubCompletionObservedAt ?? Date()
        } else {
            dubCompletionObservedAt = nil
        }

        let canRetryFailedDubSwitch = shouldRetryDubbedMasterLoad(poll)
        if allowProgressiveDubSwitching {
            scheduleLocalDubFallbackPreparationIfNeeded(
                sessionID: sessionID,
                poll: poll
            )
            scheduleDubAudioProbeIfNeeded(
                sessionID: sessionID,
                configuration: configuration,
                sourceItem: sourceItem,
                force: isCompletionStatus
            )
        }

        if DubSwitchPolicy.shouldSwitchToDubbedMaster(
            isDubPlayable: poll.playable,
            isFinalized: isCompletionStatus,
            allowProgressiveSwitching: allowProgressiveDubSwitching
        ),
           !hasLoadedDubbedMaster,
           dubSwitchAttemptCount < 3,
           (!hasDubSwitchFailed || canRetryFailedDubSwitch) {
            dubWarningMessage = nil
            dubProgressMessage = "Loading dubbed stream..."
            hasDubSwitchFailed = false
            recordDubActivity(
                "Dubbed HLS stream is playable. Connecting the translated audio.",
                level: .success,
                signature: "poll-playable"
            )
            loadDubbedMaster(
                sessionID: sessionID,
                configuration: configuration,
                sourceItem: sourceItem
            )
        }

        if hasLoadedDubbedMaster, isMediaReady {
            refreshTrackInfo()
            reconcileDubTrackSelection()
        }

        if isCompletionStatus {
            if isDubbedPlaybackActive {
                scheduleDubCompletionResyncIfNeeded(sessionID: sessionID, trigger: "poll-complete")
                recordDubActivity(
                    "Dubbed voice is live.",
                    level: .success,
                    signature: "poll-complete"
                )
                isDubLoading = false
                cancelDubberPolling()
                return
            }

            if !poll.playable && !hasLoadedDubbedMaster {
                let message = "Dubbing.uz finished translating, but the dubbed HLS stream never became playable."
                dubWarningMessage = message
                recordDubActivity(
                    message,
                    level: .warning,
                    signature: "poll-complete-unplayable"
                )
                debugLog(
                    "Dub translation completed without a playable stream. " +
                    "session_id=\(sessionID)"
                )
                isDubLoading = false
            } else {
                dubProgressMessage = "Waiting for dubbed audio track..."
                recordDubActivity(
                    "Dubber finished generating. PlayerKit is waiting for the dubbed audio track to attach.",
                    level: .info,
                    signature: "poll-complete-waiting"
                )
            }

            cancelDubberPolling()
        }
    }

    fileprivate func cancelDubberPolling() {
        dubberPollTask?.cancel()
        dubberPollTask = nil
    }

    fileprivate func updateDubCoverageWindow(from chunks: [DubberClient.PollChunk]) {
        let validStarts = chunks
            .compactMap(\.startTime)
            .filter { $0.isFinite && $0 >= 0 }
        let validEnds = chunks
            .compactMap(\.endTime)
            .filter { $0.isFinite && $0 >= 0 }

        dubCoverageStartTime = validStarts.min()
        dubCoverageEndTime = validEnds.max()
    }

    fileprivate func scheduleLocalDubFallbackPreparationIfNeeded(
        sessionID: String,
        poll: DubberClient.PollResponse
    ) {
        guard dubSessionID == sessionID else { return }
        guard primaryMuteController != nil else { return }
        guard !isLocalDubFallbackActive else { return }
        guard dubFallbackPreparationTask == nil else { return }
        guard !hasAutoSelectedDubTrack else { return }
        guard poll.chunks.contains(where: \.hasEmbeddedAudio) else { return }

        debugLog(
            "Preparing local dub audio fallback. session_id=\(sessionID) " +
            "chunks=\(poll.chunks.count)"
        )

        dubFallbackPreparationTask = Task { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.dubSessionID == sessionID || self.dubSessionID == nil {
                        self.dubFallbackPreparationTask = nil
                    }
                }
            }

            do {
                let preparedAsset = try await DubAudioFallbackBuilder.prepare(from: poll.chunks)
                await MainActor.run {
                    guard self.dubSessionID == sessionID else { return }
                    self.installLocalDubFallback(
                        preparedAsset,
                        sessionID: sessionID
                    )
                }
            } catch {
                await MainActor.run {
                    guard self.dubSessionID == sessionID else { return }
                    self.debugLog(
                        "Local dub audio fallback failed. session_id=\(sessionID) " +
                        "error=\(self.networkErrorDebugDetails(error))"
                    )
                }
            }
        }
    }

    fileprivate func installLocalDubFallback(
        _ preparedAsset: DubAudioFallbackPreparedAsset,
        sessionID: String
    ) {
        dubFallbackPlayer.install(preparedAsset)
        isLocalDubFallbackPrepared = true
        localDubFallbackCoverageStartTime = preparedAsset.coverageStartTime
        localDubFallbackCoverageEndTime = preparedAsset.coverageEndTime
        lastLocalDubFallbackWaitingSignature = nil

        debugLog(
            "Installed local dub audio fallback. session_id=\(sessionID) " +
            "coverage=\(preparedAsset.coverageStartTime)-\(preparedAsset.coverageEndTime) " +
            "chunks=\(preparedAsset.chunkCount)"
        )

        activateLocalDubFallbackIfReady(sessionID: sessionID)
    }

    fileprivate func activateLocalDubFallbackIfReady(
        sessionID: String,
        force: Bool = false
    ) {
        guard dubSessionID == sessionID else { return }
        guard isLocalDubFallbackPrepared else { return }
        guard !isLocalDubFallbackActive else { return }

        let playbackTime = max(currentPlayer?.currentTime ?? currentTime, 0)
        let coverageStart = localDubFallbackCoverageStartTime
        let coverageEnd = localDubFallbackCoverageEndTime

        if !force {
            if let coverageStart, coverageStart.isFinite,
               playbackTime + 0.35 < coverageStart {
                let signature = "before-\(String(format: "%.3f-%.3f", playbackTime, coverageStart))"
                if lastLocalDubFallbackWaitingSignature != signature {
                    lastLocalDubFallbackWaitingSignature = signature
                    debugLog(
                        "Local dub audio fallback ready but waiting for coverage window. " +
                        "session_id=\(sessionID) playback=\(playbackTime) coverage_start=\(coverageStart) " +
                        "coverage_end=\(coverageEnd?.description ?? "nil")"
                    )
                }
                return
            }

            if let coverageEnd, coverageEnd.isFinite,
               playbackTime - 0.35 > coverageEnd {
                let signature = "after-\(String(format: "%.3f-%.3f", playbackTime, coverageEnd))"
                if lastLocalDubFallbackWaitingSignature != signature {
                    lastLocalDubFallbackWaitingSignature = signature
                    debugLog(
                        "Local dub audio fallback is outside the current playback position. " +
                        "session_id=\(sessionID) playback=\(playbackTime) coverage_start=\(coverageStart?.description ?? "nil") " +
                        "coverage_end=\(coverageEnd)"
                    )
                }
                return
            }
        }

        setPrimaryPlayerMuted(true)
        dubFallbackPlayer.activate(
            at: playbackTime,
            isPlaying: isPlaying,
            isBuffering: isBuffering,
            playbackSpeed: playbackSpeed
        )

        isLocalDubFallbackActive = true
        hasAutoSelectedDubTrack = true
        isDubbedPlaybackActive = true
        isDubLoading = false
        dubWarningMessage = nil
        lastLocalDubFallbackWaitingSignature = nil
        recordDubActivity(
            "Dubbed audio is now active.",
            level: .success,
            signature: "dub-fallback-active"
        )
        debugLog(
            "Activated local dub audio fallback. session_id=\(sessionID) " +
            "playback=\(playbackTime) coverage=\(localDubFallbackCoverageStartTime?.description ?? "nil")-" +
            "\(localDubFallbackCoverageEndTime?.description ?? "nil")"
        )
    }

    fileprivate func isCompletionState(_ status: String?) -> Bool {
        let normalizedStatus = (status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedStatus == "complete"
            || normalizedStatus == "completed"
            || normalizedStatus == "ready"
    }

    fileprivate func scheduleDubAudioProbeIfNeeded(
        sessionID: String,
        configuration: DubberConfiguration,
        sourceItem: PlayerItem,
        force: Bool = false
    ) {
        guard dubSessionID == sessionID else { return }
        guard dubAudioProbeTask == nil else { return }
        guard !hasAutoSelectedDubTrack else { return }
        guard dubSwitchAttemptCount < 3 else { return }

        let playbackTime = max(currentPlayer?.currentTime ?? currentTime, 0)
        guard force || shouldProbeDubAudio(at: playbackTime) else { return }

        let targetLanguageCode = (dubTargetLanguageCode ?? selectedDubLanguageCode).lowercased()
        debugLog(
            "Scheduling dub audio probe. session_id=\(sessionID) " +
            "time=\(playbackTime) target=\(targetLanguageCode) " +
            "coverage=\(dubCoverageStartTime?.description ?? "nil")-\(dubCoverageEndTime?.description ?? "nil")"
        )

        dubAudioProbeTask = Task { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.dubSessionID == sessionID || self.dubSessionID == nil {
                        self.dubAudioProbeTask = nil
                    }
                }
            }

            do {
                let readiness = try await self.dubberClient.probeDubAudioReadiness(
                    sessionID: sessionID,
                    configuration: configuration,
                    targetLanguageCode: targetLanguageCode,
                    playbackTime: playbackTime
                )

                await MainActor.run {
                    guard self.dubSessionID == sessionID else { return }
                    self.handleSuccessfulDubAudioProbe(
                        readiness,
                        sessionID: sessionID,
                        configuration: configuration,
                        sourceItem: sourceItem
                    )
                }
            } catch {
                await MainActor.run {
                    guard self.dubSessionID == sessionID else { return }
                    self.debugLog(
                        "Dub audio probe failed. session_id=\(sessionID) " +
                        "error=\(self.networkErrorDebugDetails(error))"
                    )
                }
            }
        }
    }

    @MainActor
    fileprivate func handleSuccessfulDubAudioProbe(
        _ readiness: DubberClient.DubAudioReadiness,
        sessionID: String,
        configuration: DubberConfiguration,
        sourceItem: PlayerItem
    ) {
        debugLog(
            "Dub audio probe succeeded. session_id=\(sessionID) " +
            "window=\(readiness.verifiedWindowStart)-\(readiness.verifiedWindowEnd) " +
            "segments=\(readiness.probedSegmentURLs.count)"
        )

        if let warning = dubWarningMessage,
           warning.localizedCaseInsensitiveContains("unavailable")
            || warning.localizedCaseInsensitiveContains("finalizing") {
            dubWarningMessage = nil
        }

        if !hasLoadedDubbedMaster {
            hasDubSwitchFailed = false
            loadDubbedMaster(
                sessionID: sessionID,
                configuration: configuration,
                sourceItem: sourceItem
            )
            return
        }

        if isMediaReady {
            refreshTrackInfo()
            reconcileDubTrackSelection()
        }

        scheduleDubCompletionResyncIfNeeded(sessionID: sessionID, trigger: "probe")
    }

    fileprivate func shouldProbeDubAudio(at playbackTime: Double) -> Bool {
        guard dubReadyChunkCount > 0 || isCompletionState(dubStatus) else { return false }
        return shouldPrepareDubContent(at: max(playbackTime, 0))
    }

    fileprivate func startDubberEvents(
        sessionID: String,
        configuration: DubberConfiguration,
        sourceItem: PlayerItem
    ) {
        cancelDubberEvents()
        debugLog(
            "Starting dub SSE loop. session_id=\(sessionID) " +
            "timeout=\(dubDebugInterval(configuration.eventStreamRequestTimeout)) " +
            "reconnect_delay=\(dubDebugInterval(configuration.eventStreamReconnectDelay)) " +
            "max_retries=\(retryBudgetLabel(configuration))"
        )

        dubberEventsTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var reconnectAttempt = 0

            while !Task.isCancelled {
                do {
                    let attemptNumber = reconnectAttempt + 1
                    let attemptStart = Date()
                    self.debugLog(
                        "Dub SSE attempt started. session_id=\(sessionID) attempt=\(attemptNumber) " +
                        "base=\(configuration.baseURL.debugDescription)"
                    )
                    try await self.dubberClient.streamSessionEvents(
                        sessionID: sessionID,
                        configuration: configuration
                    ) { event in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            guard self.dubSessionID == sessionID else { return }
                            self.handleDubberEvent(
                                event,
                                sessionID: sessionID,
                                configuration: configuration,
                                sourceItem: sourceItem
                            )
                        }
                    }
                    let elapsed = Date().timeIntervalSince(attemptStart)
                    self.debugLog(
                        "Dub SSE attempt ended without thrown error. session_id=\(sessionID) " +
                        "attempt=\(attemptNumber) elapsed=\(self.dubDebugInterval(elapsed))"
                    )

                    let shouldReconnect = await MainActor.run { () -> Bool in
                        guard self.dubSessionID == sessionID else { return false }
                        if self.isDubLoading {
                            self.debugLog("Dub SSE ended before done. session_id=\(sessionID)")
                            return true
                        }
                        return false
                    }

                    guard shouldReconnect else {
                        break
                    }

                    reconnectAttempt += 1
                    guard self.canRetryDubberEvents(
                        attempt: reconnectAttempt,
                        configuration: configuration
                    ) else {
                        let exhaustedAttempt = reconnectAttempt
                        await MainActor.run {
                            guard self.dubSessionID == sessionID else { return }
                            let elapsedSinceStart = Date().timeIntervalSince(self.dubberSessionStartedAt ?? Date())
                            self.debugLog(
                                "Dub status stream disconnected after retry budget. " +
                                "session_id=\(sessionID) attempts=\(exhaustedAttempt) " +
                                "events_received=\(self.dubberEventCount) " +
                                "elapsed=\(self.dubDebugInterval(elapsedSinceStart))"
                            )
                            self.downgradeDubberEventsFailure(
                                sessionID: sessionID,
                                warning: "Live status stream disconnected. Continuing with direct polling.",
                                activity: "Live status stream disconnected, but direct polling is still tracking dubbing progress.",
                                signature: "sse-disconnected-\(exhaustedAttempt)"
                            )
                        }
                        break
                    }
                    let currentAttempt = reconnectAttempt
                    let backoffNanoseconds = self.dubberReconnectDelayNanoseconds(
                        attempt: reconnectAttempt,
                        baseDelay: configuration.eventStreamReconnectDelay
                    )
                    let backoffSeconds = Double(backoffNanoseconds) / 1_000_000_000

                    await MainActor.run {
                        guard self.dubSessionID == sessionID else { return }
                        let message = "Dub stream disconnected. Reconnecting (\(currentAttempt)/\(self.retryBudgetLabel(configuration)))."
                        self.dubWarningMessage = message
                        self.recordDubActivity(
                            "Connection blinked. Reconnecting to Dubber (\(currentAttempt)/\(self.retryBudgetLabel(configuration))).",
                            level: .warning,
                            signature: "reconnect-disconnect-\(currentAttempt)"
                        )
                        self.debugLog(
                            "Dub SSE reconnect scheduled. session_id=\(sessionID) " +
                            "attempt=\(currentAttempt) backoff=\(self.dubDebugInterval(backoffSeconds))"
                        )
                    }
                    try await Task.sleep(nanoseconds: backoffNanoseconds)
                } catch {
                    let isCancellation = self.isCancellationError(error) || Task.isCancelled
                    if isCancellation {
                        await MainActor.run {
                            guard self.dubSessionID == sessionID else { return }
                            self.debugLog("Dub SSE cancelled. session_id=\(sessionID)")
                        }
                        break
                    }

                    guard self.shouldRetryDubberEvents(after: error) else {
                        await MainActor.run {
                            guard self.dubSessionID == sessionID else { return }
                            self.downgradeDubberEventsFailure(
                                sessionID: sessionID,
                                warning: "Live status stream failed. Continuing with direct polling.",
                                activity: "Live status updates failed, but direct polling is still running.",
                                signature: "sse-failed",
                                error: error
                            )
                        }
                        break
                    }

                    reconnectAttempt += 1
                    guard self.canRetryDubberEvents(
                        attempt: reconnectAttempt,
                        configuration: configuration
                    ) else {
                        await MainActor.run {
                            guard self.dubSessionID == sessionID else { return }
                            self.downgradeDubberEventsFailure(
                                sessionID: sessionID,
                                warning: "Live status stream stopped reconnecting. Continuing with direct polling.",
                                activity: "Live status updates exhausted their retries, but direct polling is still active.",
                                signature: "sse-retries-exhausted",
                                error: error
                            )
                        }
                        break
                    }
                    let currentAttempt = reconnectAttempt
                    let backoffNanoseconds = self.dubberReconnectDelayNanoseconds(
                        attempt: reconnectAttempt,
                        baseDelay: configuration.eventStreamReconnectDelay
                    )
                    let backoffSeconds = Double(backoffNanoseconds) / 1_000_000_000

                    await MainActor.run {
                        guard self.dubSessionID == sessionID else { return }
                        let message = "Dub stream timeout. Reconnecting (\(currentAttempt)/\(self.retryBudgetLabel(configuration)))."
                        self.dubWarningMessage = message
                        self.recordDubActivity(
                            "Dubber went quiet for a moment. Trying again (\(currentAttempt)/\(self.retryBudgetLabel(configuration))).",
                            level: .warning,
                            signature: "reconnect-timeout-\(currentAttempt)"
                        )
                        self.debugLog(
                            "Dub SSE transient failure, retrying. session_id=\(sessionID) " +
                            "attempt=\(currentAttempt) backoff=\(self.dubDebugInterval(backoffSeconds)) " +
                            "error=\(self.networkErrorDebugDetails(error))"
                        )
                    }
                    do {
                        try await Task.sleep(nanoseconds: backoffNanoseconds)
                    } catch {
                        break
                    }
                }
            }

            await MainActor.run {
                guard self.dubSessionID == sessionID || self.dubSessionID == nil else { return }
                if self.dubberEventsTask?.isCancelled == false || self.dubberEventsTask != nil {
                    self.dubberEventsTask = nil
                }
            }
        }
    }

    @MainActor
    fileprivate func downgradeDubberEventsFailure(
        sessionID: String,
        warning: String,
        activity: String,
        signature: String,
        error: Error? = nil
    ) {
        guard dubSessionID == sessionID else { return }
        dubWarningMessage = warning
        recordDubActivity(activity, level: .warning, signature: signature)
        if let error {
            debugLog(
                "Dub SSE downgraded to polling only. session_id=\(sessionID) " +
                "warning=\(warning) error=\(networkErrorDebugDetails(error))"
            )
        } else {
            debugLog(
                "Dub SSE downgraded to polling only. session_id=\(sessionID) " +
                "warning=\(warning)"
            )
        }
    }

    @MainActor
    fileprivate func handleDubberEvent(
        _ event: DubberClient.SessionEvent,
        sessionID: String,
        configuration: DubberConfiguration,
        sourceItem: PlayerItem
    ) {
        dubberLastEventAt = Date()
        dubberEventCount += 1
        switch event {
        case .update(let update):
            if let warning = dubWarningMessage,
               warning.localizedCaseInsensitiveContains("reconnect")
                || warning.localizedCaseInsensitiveContains("timeout")
                || warning.localizedCaseInsensitiveContains("disconnected") {
                dubWarningMessage = nil
            }

            if let status = update.status, !status.isEmpty {
                dubStatus = status
                recordDubStatusIfNeeded(status)
            }
            if let progress = update.progress, !progress.isEmpty {
                dubProgressMessage = progress
                recordDubProgressIfNeeded(progress)
            }
            if let segmentsReady = update.segments_ready {
                dubSegmentsReady = max(segmentsReady, 0)
            }
            if let totalSegments = update.total_segments {
                dubTotalSegments = max(totalSegments, 0)
            }
            recordDubSegmentsIfNeeded()

            debugLog(
                "Dub update. session_id=\(sessionID) status=\(update.status ?? "nil") " +
                "progress=\(update.progress ?? "nil") segments=\(dubSegmentsReady)/\(dubTotalSegments) " +
                "error=\(update.error ?? "nil")"
            )

            if let rawError = update.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawError.isEmpty {
                debugLog("Dub update error. session_id=\(sessionID) error=\(rawError)")
                recordDubActivity(
                    friendlySentence(from: rawError),
                    level: .error,
                    signature: "update-error-\(rawError)"
                )
                reportError(.dubberRequestFailed(rawError))
                isDubLoading = false
                cancelDubberPolling()
                cancelDubberStallWatchdog()
                cancelDubberEvents()
                return
            }

            let normalizedStatus = (update.status ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let isCompletionStatus = normalizedStatus == "complete"
                || normalizedStatus == "completed"
                || normalizedStatus == "ready"

            if isCompletionStatus {
                dubCompletionObservedAt = dubCompletionObservedAt ?? Date()
            } else {
                dubCompletionObservedAt = nil
            }

            if allowProgressiveDubSwitching {
                scheduleDubAudioProbeIfNeeded(
                    sessionID: sessionID,
                    configuration: configuration,
                    sourceItem: sourceItem,
                    force: isCompletionStatus
                )
            }

            if hasLoadedDubbedMaster, isMediaReady {
                refreshTrackInfo()
                reconcileDubTrackSelection()
            }

            if isCompletionStatus {
                debugLog("Dub SSE complete update. session_id=\(sessionID)")
                if isDubbedPlaybackActive {
                    scheduleDubCompletionResyncIfNeeded(sessionID: sessionID, trigger: "status-complete")
                    isDubLoading = false
                    recordDubActivity(
                        "All translated voice pieces are ready.",
                        level: .success,
                        signature: "status-complete"
                    )
                    cancelDubberStallWatchdog()
                } else {
                    dubProgressMessage = "Finalizing playable audio..."
                }
            }

        case .warning(let warning):
            let message = warning.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                dubWarningMessage = message
                recordDubActivity(
                    friendlySentence(from: message),
                    level: .warning,
                    signature: "warning-\(message)"
                )
                debugLog("Dub warning. session_id=\(sessionID) message=\(message)")
            }

        case .done(let done):
            if let status = done.status, !status.isEmpty {
                dubStatus = status
            }

            let normalizedDoneStatus = (done.status ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let isDoneCompletionStatus = normalizedDoneStatus == "complete"
                || normalizedDoneStatus == "completed"
                || normalizedDoneStatus == "ready"

            if isDoneCompletionStatus {
                dubCompletionObservedAt = dubCompletionObservedAt ?? Date()
                if allowProgressiveDubSwitching {
                    scheduleDubAudioProbeIfNeeded(
                        sessionID: sessionID,
                        configuration: configuration,
                        sourceItem: sourceItem,
                        force: true
                    )
                }
                scheduleDubCompletionResyncIfNeeded(sessionID: sessionID, trigger: "done")
            }

            debugLog("Dub SSE done. session_id=\(sessionID) status=\(done.status ?? "unknown")")
            recordDubActivity(
                "Dubber finished sending updates for this session.",
                level: .success,
                signature: "sse-done"
            )
            if isDubbedPlaybackActive {
                isDubLoading = false
                cancelDubberStallWatchdog()
            } else if isDoneCompletionStatus {
                dubProgressMessage = "Finalizing playable audio..."
            }
            cancelDubberEvents()
        }
    }

    fileprivate func cancelDubberEvents() {
        dubberEventsTask?.cancel()
        dubberEventsTask = nil
    }

    fileprivate var hasActiveDubWorkflow: Bool {
        dubSessionID != nil
            || isDubLoading
            || dubberPollTask != nil
            || dubberEventsTask != nil
            || dubberStallWatchdogTask != nil
            || dubFallbackPreparationTask != nil
            || isLocalDubFallbackActive
            || activeDubSourceItem != nil
            || hasLoadedDubbedMaster
    }

    fileprivate func cancelDubWorkflowIfNeededForContentChange(nextURL: URL) {
        guard hasActiveDubWorkflow else { return }
        guard playerItem?.url != nextURL else { return }
        cancelDubWorkflow(
            reason: "Content changed. previous=\(playerItem?.url.debugDescription ?? "nil") next=\(nextURL.debugDescription)"
        )
    }

    fileprivate func cancelDubWorkflow(reason: String) {
        guard hasActiveDubWorkflow else { return }
        debugLog("Cancelling dub workflow. reason=\(reason) session_id=\(dubSessionID ?? "nil")")
        cancelDubberPolling()
        cancelDubberEvents()
        cancelDubberStallWatchdog()
        cancelDubCompletionResync()
        cancelDubPlaybackRecovery()
        dubAudioProbeTask?.cancel()
        dubAudioProbeTask = nil
        dubFallbackPreparationTask?.cancel()
        dubFallbackPreparationTask = nil
        dubFallbackPlayer.stop()
        isLocalDubFallbackActive = false
        isLocalDubFallbackPrepared = false
        localDubFallbackCoverageStartTime = nil
        localDubFallbackCoverageEndTime = nil
        lastLocalDubFallbackWaitingSignature = nil
        setPrimaryPlayerMuted(false)
        isDubLoading = false
        dubSessionID = nil
        dubberSessionStartedAt = nil
        dubberLastEventAt = nil
        dubberEventCount = 0
        dubStatus = nil
        dubProgressMessage = nil
        dubSegmentsReady = 0
        dubTotalSegments = 0
        dubWarningMessage = nil
        dubReadyChunkCount = 0
        dubCoverageStartTime = nil
        dubCoverageEndTime = nil
        dubCompletionObservedAt = nil
        isDubbedPlaybackActive = false
        hasAutoSelectedDubTrack = false
        hasLoadedDubbedMaster = false
        hasAppliedSourceAudioFallback = false
        dubTargetLanguageCode = nil
        activeDubSourceItem = nil
        dubSwitchAttemptCount = 0
        hasDubSwitchFailed = false
        isDubberSheetPinned = false
        resetDubActivityLog()
    }

    private func stopDubbingAndReturnToOriginalAudio(reason: String) {
        guard hasActiveDubWorkflow else { return }

        let sourceItem = activeDubSourceItem
        let shouldRestoreSource = hasLoadedDubbedMaster && sourceItem != nil
        let resumePosition = max(currentPlayer?.currentTime ?? currentTime, 0)

        cancelDubWorkflow(reason: reason)
        clearError()

        if shouldRestoreSource, let sourceItem {
            let restoredItem = PlayerItem(
                title: sourceItem.title,
                description: sourceItem.description,
                dubTitle: sourceItem.dubTitle,
                url: sourceItem.url,
                posterUrl: sourceItem.posterUrl,
                castVideoUrl: sourceItem.castVideoUrl,
                externalPlaybackURL: sourceItem.externalPlaybackURL,
                externalPlaybackContentType: sourceItem.externalPlaybackContentType,
                externalPlaybackDuration: sourceItem.externalPlaybackDuration,
                lastPosition: resumePosition,
                episodeIndex: sourceItem.episodeIndex
            )

            playerItem = restoredItem
            if !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count {
                playerItems[currentPlayerItemIndex] = restoredItem
            }
            load(url: sourceItem.url, lastPosition: resumePosition)
        }
    }

    fileprivate func cancelDubCompletionResync() {
        dubCompletionResyncTask?.cancel()
        dubCompletionResyncTask = nil
        hasScheduledDubCompletionResync = false
    }

    fileprivate func cancelPendingPlaybackResume() {
        if playbackResumeTask != nil {
            debugLog("Cancelling pending playback resume task.")
        }
        playbackResumeTask?.cancel()
        playbackResumeTask = nil
        playbackResumeProgressReferenceTime = nil
    }

    fileprivate func cancelDubPlaybackRecovery() {
        dubPlaybackRecoveryTask?.cancel()
        dubPlaybackRecoveryTask = nil
    }

    fileprivate func scheduleDubCompletionResyncIfNeeded(
        sessionID: String,
        trigger: String
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleDubCompletionResyncIfNeeded(sessionID: sessionID, trigger: trigger)
            }
            return
        }

        guard dubSessionID == sessionID else { return }
        guard shouldUsePreciseDubSeek else { return }
        guard hasLoadedDubbedMaster else { return }
        guard !isLocalDubFallbackActive else { return }
        guard isMediaReady else { return }

        refreshTrackInfo()
        reconcileDubTrackSelection()
        guard isDubbedPlaybackActive else { return }
        guard !hasScheduledDubCompletionResync else { return }

        hasScheduledDubCompletionResync = true
        dubCompletionResyncTask?.cancel()
        dubCompletionResyncTask = Task { [weak self] in
            guard let self else { return }

            let delays: [UInt64] = [180_000_000, 900_000_000]
            for (index, delay) in delays.enumerated() {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }

                await MainActor.run {
                    guard self.dubSessionID == sessionID else { return }
                    guard self.shouldUsePreciseDubSeek else { return }
                    guard self.hasLoadedDubbedMaster else { return }
                    guard !self.isLocalDubFallbackActive else { return }
                    guard self.isMediaReady else { return }

                    self.refreshTrackInfo()
                    self.reconcileDubTrackSelection()
                    guard self.isDubbedPlaybackActive else { return }

                    let targetTime = max(self.currentPlayer?.currentTime ?? self.currentTime, 0)
                    self.debugLog(
                        "Stabilizing completed dub playback. session_id=\(sessionID) " +
                        "pass=\(index + 1) trigger=\(trigger) target=\(targetTime)"
                    )
                    self.performPreciseDubSeek(to: targetTime)
                }
            }

            await MainActor.run {
                guard self.dubSessionID == sessionID || self.dubSessionID == nil else { return }
                self.dubCompletionResyncTask = nil
            }
        }
    }

    private var shouldUsePreciseDubSeek: Bool {
        dubSessionID != nil && isCompletionState(dubStatus)
    }

    private func performPreciseDubSeek(to time: Double) {
        let clampedTime = max(time, 0)
        if let preciseSeekController {
            preciseSeekController.seekExactly(to: clampedTime) { [weak self] success in
                guard let self, success else { return }
                self.currentTime = clampedTime
                if self.isLocalDubFallbackActive {
                    self.dubFallbackPlayer.seek(to: clampedTime)
                }
            }
        } else {
            playbackManager?.seek(to: clampedTime) { [weak self] success in
                guard let self, success else { return }
                self.currentTime = clampedTime
                if self.isLocalDubFallbackActive {
                    self.dubFallbackPlayer.seek(to: clampedTime)
                }
            }
        }
    }

    private var isDubTimelineFinalized: Bool {
        isCompletionState(dubStatus)
    }

    private var isDubTrackCurrentlySelected: Bool {
        if let selectedAudio {
            return isLikelyDubTrack(selectedAudio)
        }

        return hasAutoSelectedDubTrack && isDubbedPlaybackActive
    }

    private func currentDubPlaybackTime(or playbackTime: Double? = nil) -> Double {
        max(playbackTime ?? currentPlayer?.currentTime ?? currentTime, 0)
    }

    private func canActivateDubTrack(at playbackTime: Double) -> Bool {
        let knownDuration = max(duration, playbackTime)
        return DubSwitchPolicy.hasPlayableDubData(
            segmentsReady: dubSegmentsReady,
            totalSegments: dubTotalSegments,
            chunkCount: dubReadyChunkCount,
            resumePosition: playbackTime,
            knownDuration: knownDuration,
            isFinalized: isDubTimelineFinalized,
            coverageStart: dubCoverageStartTime,
            coverageEnd: dubCoverageEndTime
        )
    }

    private func shouldPrepareDubContent(at playbackTime: Double) -> Bool {
        let knownDuration = max(duration, playbackTime)
        return DubSwitchPolicy.shouldPrepareDubMaster(
            segmentsReady: dubSegmentsReady,
            totalSegments: dubTotalSegments,
            chunkCount: dubReadyChunkCount,
            resumePosition: playbackTime,
            knownDuration: knownDuration,
            isFinalized: isDubTimelineFinalized,
            coverageStart: dubCoverageStartTime,
            coverageEnd: dubCoverageEndTime
        )
    }

    private func reconcileDubTrackSelection(
        at playbackTime: Double? = nil,
        forceSourceFallback: Bool = false
    ) {
        guard hasLoadedDubbedMaster else { return }

        let resolvedPlaybackTime = currentDubPlaybackTime(or: playbackTime)
        if forceSourceFallback || !canActivateDubTrack(at: resolvedPlaybackTime) {
            selectSourceAudioFallbackIfNeeded(
                at: resolvedPlaybackTime,
                force: true
            )
            return
        }

        autoSelectDubTrackIfNeeded(at: resolvedPlaybackTime)
        if !hasAutoSelectedDubTrack {
            selectSourceAudioFallbackIfNeeded(at: resolvedPlaybackTime)
        }
    }

    private func shouldResumeSourcePlaybackDuringDubSeek(to targetTime: Double) -> Bool {
        guard dubSessionID != nil else { return false }
        guard hasLoadedDubbedMaster else { return false }
        guard !isLocalDubFallbackActive else { return false }
        guard !shouldUsePreciseDubSeek else { return false }
        guard let seekWindowReporter else { return false }

        return !seekWindowReporter.canSeekWithinCurrentWindow(to: targetTime, tolerance: 0.75)
    }

    private func continueDubWorkflowOnSourcePlayback(
        at resumePosition: Double,
        reason: String
    ) {
        guard let sourceItem = activeDubSourceItem else { return }

        let clampedTime = max(resumePosition, 0)
        let sourcePlaybackItem = PlayerItem(
            title: sourceItem.title,
            description: sourceItem.description,
            dubTitle: sourceItem.dubTitle,
            url: sourceItem.url,
            posterUrl: sourceItem.posterUrl,
            castVideoUrl: sourceItem.castVideoUrl,
            externalPlaybackURL: sourceItem.externalPlaybackURL,
            externalPlaybackContentType: sourceItem.externalPlaybackContentType,
            externalPlaybackDuration: sourceItem.externalPlaybackDuration,
            lastPosition: clampedTime,
            episodeIndex: sourceItem.episodeIndex
        )

        cancelDubPlaybackRecovery()
        hasLoadedDubbedMaster = false
        hasDubSwitchFailed = false
        hasAppliedSourceAudioFallback = false
        isDubbedPlaybackActive = isLocalDubFallbackActive
        hasAutoSelectedDubTrack = isLocalDubFallbackActive
        isDubLoading = !isLocalDubFallbackActive
        savedAudio = nil
        savedSubtitle = nil
        playerItem = sourcePlaybackItem

        if !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count {
            playerItems[currentPlayerItemIndex] = sourcePlaybackItem
        }

        debugLog(
            "Continuing on source playback while dubbing keeps rendering. " +
            "reason=\(reason) resume=\(clampedTime) session_id=\(dubSessionID ?? "nil")"
        )
        recordDubActivity(
            "Dubbed audio is catching up. Continuing on the original stream for a moment.",
            level: .warning,
            signature: "source-fallback-\(Int(clampedTime.rounded()))"
        )
        load(url: sourceItem.url, lastPosition: clampedTime)
    }

    private func recoverDubbedPlaybackStall(sessionID: String, stalledTime: Double) {
        guard dubSessionID == sessionID else { return }
        guard hasLoadedDubbedMaster else { return }

        if shouldUsePreciseDubSeek {
            scheduleDubbedPlaybackRecovery(
                sessionID: sessionID,
                trigger: "stall",
                targetTime: stalledTime
            )
            return
        }

        if !canActivateDubTrack(at: stalledTime) {
            refreshTrackInfo()
            selectSourceAudioFallbackIfNeeded(
                at: stalledTime,
                force: true
            )
            if !isDubTrackCurrentlySelected {
                debugLog(
                    "Dub track reached the live edge, falling back to source audio. " +
                    "session_id=\(sessionID) time=\(stalledTime)"
                )
                playbackResumeProgressReferenceTime = stalledTime
                schedulePlaybackResumeIfNeeded(trigger: "dub-audio-fallback")
                return
            }
        }

        continueDubWorkflowOnSourcePlayback(
            at: stalledTime,
            reason: "Dubbed HLS playback stalled before the translated stream finished rendering."
        )
    }

    private func scheduleDubbedPlaybackRecovery(
        sessionID: String,
        trigger: String,
        targetTime: Double
    ) {
        guard dubPlaybackRecoveryTask == nil else {
            debugLog(
                "Dub stall recovery already pending. session_id=\(sessionID) " +
                "trigger=\(trigger) target=\(targetTime)"
            )
            return
        }

        dubPlaybackRecoveryTask = Task { [weak self] in
            guard let self else { return }
            let delays: [UInt64] = [250_000_000, 1_000_000_000, 2_500_000_000]

            for delay in delays {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }

                await MainActor.run {
                    guard self.dubSessionID == sessionID else { return }
                    guard self.hasLoadedDubbedMaster else { return }
                    guard !self.isLocalDubFallbackActive else { return }

                    if !self.isBuffering && self.isPlaying {
                        self.cancelDubPlaybackRecovery()
                        return
                    }

                    let recoveryTime = max(self.currentPlayer?.currentTime ?? self.currentTime, targetTime, 0)
                    self.debugLog(
                        "Recovering dubbed playback after stall. session_id=\(sessionID) " +
                        "trigger=\(trigger) target=\(recoveryTime)"
                    )
                    self.performPreciseDubSeek(to: recoveryTime)
                    self.performPlaybackResumeAttempt()
                }
            }

            await MainActor.run {
                guard self.dubSessionID == sessionID || self.dubSessionID == nil else { return }
                self.dubPlaybackRecoveryTask = nil
            }
        }
    }

    fileprivate func startDubberStallWatchdog(sessionID: String) {
        cancelDubberStallWatchdog()
        debugLog("Dub watchdog started. session_id=\(sessionID)")

        dubberStallWatchdogTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    break
                }

                await MainActor.run {
                    guard self.dubSessionID == sessionID else { return }
                    guard self.isDubLoading else { return }

                    let now = Date()
                    let sinceStart = now.timeIntervalSince(self.dubberSessionStartedAt ?? now)
                    let sinceLastEvent = self.dubberLastEventAt.map { now.timeIntervalSince($0) }
                    let sinceLastEventLabel = sinceLastEvent.map(self.dubDebugInterval) ?? "none"
                    self.debugLog(
                        "Dub watchdog heartbeat. session_id=\(sessionID) " +
                        "status=\(self.dubStatus ?? "nil") " +
                        "progress=\(self.dubProgressMessage ?? "nil") " +
                        "segments=\(self.dubSegmentsReady)/\(self.dubTotalSegments) " +
                        "events_received=\(self.dubberEventCount) " +
                        "elapsed_since_start=\(self.dubDebugInterval(sinceStart)) " +
                        "elapsed_since_event=\(sinceLastEventLabel)"
                    )
                }
            }
        }
    }

    fileprivate func cancelDubberStallWatchdog() {
        if dubberStallWatchdogTask != nil {
            debugLog("Dub watchdog stopped.")
        }
        dubberStallWatchdogTask?.cancel()
        dubberStallWatchdogTask = nil
    }

    fileprivate func networkErrorDebugDetails(_ error: Error) -> String {
        let nsError = error as NSError
        return
            "domain=\(nsError.domain) " +
            "code=\(nsError.code) " +
            "description=\(nsError.localizedDescription)"
    }

    fileprivate func shouldRetryDubberEvents(after error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }

        switch nsError.code {
        case URLError.timedOut.rawValue,
             URLError.networkConnectionLost.rawValue,
             URLError.notConnectedToInternet.rawValue,
             URLError.cannotConnectToHost.rawValue,
             URLError.cannotFindHost.rawValue,
             URLError.dnsLookupFailed.rawValue,
             URLError.resourceUnavailable.rawValue,
             URLError.internationalRoamingOff.rawValue,
             URLError.callIsActive.rawValue,
             URLError.dataNotAllowed.rawValue:
            return true
        default:
            return false
        }
    }

    fileprivate func canRetryDubberEvents(
        attempt: Int,
        configuration: DubberConfiguration
    ) -> Bool {
        let maxAttempts = configuration.eventStreamMaxReconnectAttempts
        if maxAttempts <= 0 {
            return true
        }
        return attempt <= maxAttempts
    }

    fileprivate func retryBudgetLabel(_ configuration: DubberConfiguration) -> String {
        let maxAttempts = configuration.eventStreamMaxReconnectAttempts
        return maxAttempts <= 0 ? "∞" : "\(maxAttempts)"
    }

    fileprivate func dubberReconnectDelayNanoseconds(
        attempt: Int,
        baseDelay: TimeInterval
    ) -> UInt64 {
        let normalizedBase = max(baseDelay, 0.5)
        let multiplier = min(pow(2.0, Double(max(attempt - 1, 0))), 8.0)
        let seconds = normalizedBase * multiplier
        return UInt64(seconds * 1_000_000_000)
    }

    fileprivate func dubDebugInterval(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }

    @MainActor
    fileprivate func loadDubbedMaster(
        sessionID: String,
        configuration: DubberConfiguration,
        sourceItem: PlayerItem
    ) {
        guard !hasLoadedDubbedMaster else { return }

        let masterURL = dubberClient.masterPlaylistURL(sessionID: sessionID, configuration: configuration)
        let resumePosition = currentPlayer?.currentTime ?? currentTime
        let dubbedItem = PlayerItem(
            title: sourceItem.title,
            description: sourceItem.description,
            dubTitle: sourceItem.dubTitle,
            url: masterURL,
            posterUrl: sourceItem.posterUrl,
            externalPlaybackURL: masterURL,
            externalPlaybackContentType: "application/x-mpegURL",
            externalPlaybackDuration: sourceItem.externalPlaybackDuration,
            lastPosition: resumePosition,
            episodeIndex: sourceItem.episodeIndex
        )

        hasLoadedDubbedMaster = true
        isDubbedPlaybackActive = false
        hasAppliedSourceAudioFallback = false
        dubSwitchAttemptCount += 1
        savedAudio = nil
        savedSubtitle = nil
        playerItem = dubbedItem
        if !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count {
            playerItems[currentPlayerItemIndex] = dubbedItem
        }
        load(url: masterURL, lastPosition: resumePosition)
        HapticsManager.shared.triggerNotificationFeedback(type: .success)
        recordDubActivity(
            "Dubbed stream connected. Waiting for the translated audio track.",
            level: .success,
            signature: "switch-master"
        )
        debugLog(
            "Loaded dubbed master. session_id=\(sessionID) " +
            "master=\(masterURL.debugDescription) resume=\(resumePosition)"
        )
    }

    fileprivate func autoSelectDubTrackIfNeeded(at playbackTime: Double? = nil) {
        guard !isLocalDubFallbackActive else { return }
        guard !hasAutoSelectedDubTrack else { return }
        let resolvedPlaybackTime = currentDubPlaybackTime(or: playbackTime)
        guard canActivateDubTrack(at: resolvedPlaybackTime) else { return }
        guard let dubTrack = availableAudioTracks.first(where: { isLikelyDubTrack($0) }) else { return }

        debugLog("Auto-selecting dub track: \(dubTrack.name) (\(dubTrack.id))")
        selectAudioTrack(track: dubTrack)
        refreshTrackInfo()

        if let selectedAudio, isLikelyDubTrack(selectedAudio) {
            hasAutoSelectedDubTrack = true
            isDubbedPlaybackActive = true
            hasAppliedSourceAudioFallback = false
            dubSwitchAttemptCount = 0
            isDubLoading = false
            dubWarningMessage = nil
            cancelDubPlaybackRecovery()
            playbackManager?.play()
            isPlaying = true
            recordDubActivity(
                "Dubbed audio is now active.",
                level: .success,
                signature: "dub-audio-active"
            )
            if let sessionID = dubSessionID {
                scheduleDubCompletionResyncIfNeeded(sessionID: sessionID, trigger: "track-selected")
            }
            return
        }

        debugLog("Dub track selection did not stick yet; will retry when tracks update again.")
    }

    fileprivate func selectSourceAudioFallbackIfNeeded(
        at playbackTime: Double? = nil,
        force: Bool = false
    ) {
        guard !isLocalDubFallbackActive else { return }
        if !force {
            guard !hasAutoSelectedDubTrack else { return }
            guard !hasAppliedSourceAudioFallback else { return }
        }

        if let selectedAudio, !isLikelyDubTrack(selectedAudio) {
            isDubbedPlaybackActive = false
            hasAutoSelectedDubTrack = false
            hasAppliedSourceAudioFallback = true
            return
        }

        guard let fallbackTrack = availableAudioTracks.first(where: { !isLikelyDubTrack($0) }) else { return }
        let resolvedPlaybackTime = currentDubPlaybackTime(or: playbackTime)
        if selectedAudio?.id != fallbackTrack.id {
            debugLog(
                "Selecting source audio while dubbing is in progress: \(fallbackTrack.name) (\(fallbackTrack.id)) " +
                "playback=\(resolvedPlaybackTime)"
            )
            selectAudioTrack(track: fallbackTrack)
        }
        isDubbedPlaybackActive = false
        hasAutoSelectedDubTrack = false
        hasAppliedSourceAudioFallback = true
    }

    fileprivate func isDubStreamReadyToSwitch(_ update: DubberClient.UpdatePayload) -> Bool {
        isDubStreamReadyToSwitch(
            segmentsReady: max(update.segments_ready ?? 0, 0),
            totalSegments: max(update.total_segments ?? 0, 0),
            chunkCount: dubReadyChunkCount
        )
    }

    fileprivate func isDubStreamReadyToSwitch(
        segmentsReady: Int,
        totalSegments: Int,
        chunkCount: Int
    ) -> Bool {
        guard !hasDubSwitchFailed else { return false }

        let resumePosition = max(currentPlayer?.currentTime ?? currentTime, 0)
        let knownDuration = max(duration, resumePosition)
        return DubSwitchPolicy.hasPlayableDubData(
            segmentsReady: segmentsReady,
            totalSegments: totalSegments,
            chunkCount: chunkCount,
            resumePosition: resumePosition,
            knownDuration: knownDuration,
            isFinalized: isDubTimelineFinalized,
            coverageStart: dubCoverageStartTime,
            coverageEnd: dubCoverageEndTime
        )
    }

    fileprivate func isLikelyDubTrack(_ track: TrackInfo) -> Bool {
        let name = track.name.lowercased()
        let language = track.languageCode?.lowercased()
        let targetLanguage = dubTargetLanguageCode

        if name.contains("dub") || name.contains("dublyaj") || name.contains("dubbing") {
            return true
        }

        if let targetLanguage, let language {
            return language.hasPrefix(targetLanguage)
        }

        return false
    }

    fileprivate func shouldRetryDubbedMasterLoad(_ poll: DubberClient.PollResponse) -> Bool {
        guard hasDubSwitchFailed else { return false }
        guard dubSwitchAttemptCount < 3 else { return false }

        let resumePosition = max(currentPlayer?.currentTime ?? currentTime, 0)
        let knownDuration = max(duration, resumePosition)

        return DubSwitchPolicy.shouldRetryAfterFailure(
            segmentsReady: poll.segmentsReady,
            totalSegments: poll.totalSegments,
            chunkCount: poll.chunks.count,
            resumePosition: resumePosition,
            knownDuration: knownDuration,
            status: poll.status,
            coverageStart: dubCoverageStartTime,
            coverageEnd: dubCoverageEndTime
        )
    }

    fileprivate func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
    }

    fileprivate func recoverFromDubbedMediaFailureIfNeeded(_ error: PlayerKitError) -> Bool {
        guard case .mediaLoadFailed = error else { return false }
        guard hasLoadedDubbedMaster, dubSessionID != nil else { return false }
        guard let sourceItem = activeDubSourceItem else { return false }
        guard !hasDubSwitchFailed else { return false }

        let resumePosition = max(currentTime, 0)
        let keepLocalDubFallback = isLocalDubFallbackActive
        hasDubSwitchFailed = true
        hasLoadedDubbedMaster = false
        hasAppliedSourceAudioFallback = false
        isDubbedPlaybackActive = keepLocalDubFallback
        hasAutoSelectedDubTrack = keepLocalDubFallback
        isDubLoading = !keepLocalDubFallback

        playerItem = sourceItem
        if !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count {
            playerItems[currentPlayerItemIndex] = sourceItem
        }
        debugLog(
            "Dub stream failed to open, reverting to source while translation continues. " +
            "resume=\(resumePosition) attempts=\(dubSwitchAttemptCount)"
        )
        recordDubActivity(
            keepLocalDubFallback
                ? "The dubbed video stream stumbled, so PlayerKit moved back to the original video while keeping the dubbed audio alive."
                : "The dubbed stream stumbled, so PlayerKit moved back to the original sound while dubbing keeps going.",
            level: .warning,
            signature: "switch-recover"
        )
        load(url: sourceItem.url, lastPosition: resumePosition)
        return true
    }

    fileprivate func debugLog(_ message: String) {
        print("[PlayerKit][PlayerManager] \(message)")
    }

    private func debugInterval(_ value: Double) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.3f", value)
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

    fileprivate func recordDubStatusIfNeeded(_ rawStatus: String) {
        let normalized = friendlySentence(from: rawStatus)
        guard !normalized.isEmpty else { return }
        guard lastDubStatusSummary != normalized else { return }
        lastDubStatusSummary = normalized
        recordDubActivity(normalized, level: .info, signature: "status-\(normalized)")
    }

    fileprivate func recordDubProgressIfNeeded(_ rawProgress: String) {
        let normalized = friendlySentence(from: rawProgress)
        guard !normalized.isEmpty else { return }
        guard lastDubProgressSummary != normalized else { return }
        lastDubProgressSummary = normalized
        recordDubActivity(normalized, level: .info, signature: "progress-\(normalized)")
    }

    fileprivate func recordDubSegmentsIfNeeded() {
        guard dubTotalSegments > 0 else { return }

        let summary = "\(dubSegmentsReady)/\(dubTotalSegments)"
        guard lastDubSegmentSummary != summary else { return }
        lastDubSegmentSummary = summary

        let isImportantMilestone =
            dubSegmentsReady <= 2
            || dubSegmentsReady == dubTotalSegments
            || dubSegmentsReady >= max(dubTotalSegments - 1, 0)
            || dubSegmentsReady % 3 == 0

        guard isImportantMilestone else { return }

        recordDubActivity(
            "\(dubSegmentsReady) of \(dubTotalSegments) voice pieces are ready.",
            level: .info,
            signature: "segments-\(summary)"
        )
    }

    fileprivate func recordDubActivity(
        _ message: String,
        level: DubberActivityLogEntry.Level,
        signature: String? = nil
    ) {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMessage.isEmpty else { return }

        let dedupeSignature = signature ?? "\(level.rawValue)-\(normalizedMessage)"
        guard lastDubActivitySignature != dedupeSignature else { return }
        lastDubActivitySignature = dedupeSignature

        dubActivityLog.insert(
            DubberActivityLogEntry(message: normalizedMessage, level: level),
            at: 0
        )

        if dubActivityLog.count > 12 {
            dubActivityLog.removeLast(dubActivityLog.count - 12)
        }
    }

    fileprivate func resetDubActivityLog() {
        dubActivityLog = []
        lastDubActivitySignature = nil
        lastDubStatusSummary = nil
        lastDubProgressSummary = nil
        lastDubSegmentSummary = nil
    }

    fileprivate func friendlySentence(from raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return "" }

        let lowercased = trimmed.lowercased()
        let mapped: String
        switch true {
        case lowercased.contains("queue"):
            mapped = "Waiting in line for Dubber to begin."
        case lowercased.contains("no subtitles"):
            mapped = "No subtitle track was found in this stream. Dubbing needs HLS subtitles."
        case lowercased.contains("reconnect"):
            mapped = "Reconnecting to live dubbing."
        case lowercased.contains("timeout"):
            mapped = "Dubber paused for a moment, then tried again."
        case lowercased.contains("start"), lowercased.contains("prepare"), lowercased.contains("boot"):
            mapped = "Preparing the dubbing session."
        case lowercased.contains("translate"), lowercased.contains("dub"), lowercased.contains("voice"):
            mapped = "Building the translated voice track."
        case lowercased.contains("segment"):
            mapped = trimmed
        case lowercased.contains("complete"), lowercased.contains("done"), lowercased.contains("finish"):
            mapped = "The dubbed voice is fully prepared."
        default:
            mapped = trimmed
        }

        return sentenceCase(mapped)
    }

    fileprivate func friendlyDubberErrorMessage(for error: PlayerKitError) -> String {
        switch error {
        case .dubberNotConfigured:
            return "Dubber is not configured for this player."
        case .dubberSourceMissing:
            return "There is no video loaded yet, so dubbing cannot start."
        case .dubberRequestFailed(let description):
            return "Dubber request failed. \(friendlySentence(from: description))"
        default:
            return error.localizedDescription
        }
    }

    fileprivate func sentenceCase(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return first.uppercased() + trimmed.dropFirst()
    }

    fileprivate func normalizedDubSelection(
        current: String,
        options: [DubberLanguageOption],
        fallback: String
    ) -> String {
        if options.contains(where: { $0.code == current }) {
            return current
        }

        if options.contains(where: { $0.code == fallback }) {
            return fallback
        }

        return options.first?.code ?? fallback
    }

    fileprivate func formattedDubRemainingTime(_ seconds: TimeInterval) -> String {
        let roundedSeconds = Int(seconds.rounded())
        if roundedSeconds < 60 {
            return "About \(roundedSeconds)s left"
        }

        let minutes = roundedSeconds / 60
        let secondsRemainder = roundedSeconds % 60
        if secondsRemainder == 0 {
            return "About \(minutes)m left"
        }

        return "About \(minutes)m \(secondsRemainder)s left"
    }
}

// MARK: - PiP Controls
extension PlayerManager {
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
        
        gestureManager.durationProvider = { [weak self] in
            self?.currentPlayer?.duration ?? self?.duration ?? 0
        }
        
        gestureManager.onControlsVisibilityChange = { [weak self] isVisible in
            self?.areControlsVisible = isVisible
        }
    }
    
    public func setGravityToDefault() {
        currentPlayer?.setGravityToDefault()
    }
}

// MARK: - Control Visibility Management
extension PlayerManager {
    func pinDubberSheet() {
        isDubberSheetPinned = true
    }

    func releaseDubberSheetPin() {
        isDubberSheetPinned = false
    }

    /// Called whenever the user interacts, showing controls and resetting the auto-hide timer
    public func userInteracted() {
        guard !gestureManager.isMultipleTapping else { return }
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
                self.currentTime = player.currentTime
                self.duration = player.duration
                self.bufferedDuration = player.bufferedDuration
            }
            .store(in: &stateCancellables)
    }
    
    public func resetPlayer() {
        resetPlayer(clearMediaContext: true, clearDubWorkflow: true)
    }

    private func resetPlayer(
        clearMediaContext: Bool,
        clearDubWorkflow: Bool
    ) {
        cancelPendingPlaybackResume()
        if clearDubWorkflow {
            cancelDubWorkflow(reason: "Resetting player manager.")
        } else {
            prepareDubWorkflowForBackendSwitch()
        }
        cancelDubPlaybackRecovery()

        if let stateSource = currentPlayer as? PlayerStateSource {
            stateSource.stopRuntimeStateUpdates()
            stateSource.onRuntimeStateChange = nil
        }
        
        if let eventSource = currentPlayer as? PlayerEventSource {
            eventSource.lifecycleReporter = nil
        }
        
        currentPlayer?.stop()
        currentPlayer = nil
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
        isExternalEpisodeNavigationInProgress = false
        shouldResumePlaybackAfterStall = false
        
        userInteracting = false
        isLocked = false
        isMediaReady = false
        isVideoEnded = false
        shouldDismiss = false
        clearError()
        lastRuntimeStateDebugSummary = nil
        
        selectedAudio = nil
        selectedSubtitle = nil
        availableAudioTracks = []
        availableSubtitles = []
        if clearMediaContext {
            playerItem = nil
            playerItems = []
            currentPlayerItemIndex = 0
            contentType = .movie
            clearExternalEpisodeNavigation()
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

        if Thread.isMainThread {
            Task { @MainActor in
                PlaybackWakeLockCoordinator.shared.setPlaybackActive(shouldHoldWakeLock)
            }
        } else {
            DispatchQueue.main.async {
                Task { @MainActor in
                    PlaybackWakeLockCoordinator.shared.setPlaybackActive(shouldHoldWakeLock)
                }
            }
        }
    }
}

extension PlayerManager {
    private func configureIntegrationsIfNeeded() {
        guard !integrationsConfigured else { return }
        configureAudioSessionCallbacks()
        configureCastCallbacks()
        AudioSessionManager.shared.configureAudioSession()
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
        
        castManager.onError = { [weak self] error in
            self?.reportError(error)
        }
        
        castManager.onDismissRequested = { [weak self] in
            self?.shouldDismiss = true
        }

        castManager.refreshAvailableDevices(force: false)
    }
    
    private func configureAudioSessionCallbacks() {
        AudioSessionManager.shared.onPauseRequested = { [weak self] in
            self?.pause()
        }
        
        AudioSessionManager.shared.onResumeRequested = { [weak self] in
            self?.play()
        }
    }
    
    private func configureOrientationCallbacks() {
        orientationManager.onPortraitOrientation = { [weak self] in
            self?.setGravityToDefault()
        }
    }

    private func setPrimaryPlayerMuted(_ muted: Bool) {
        primaryMuteController?.setMuted(muted)
    }

    private func applyRuntimeState(_ state: PlayerRuntimeState) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applyRuntimeState(state)
            }
            return
        }
        
        isPlaying = state.isPlaying
        isBuffering = state.isBuffering
        currentTime = state.currentTime
        duration = state.duration
        bufferedDuration = state.bufferedDuration
        logRuntimeStateIfChanged(state)

        if hasPlaybackProgressedSinceResumeReference(currentTime: state.currentTime) {
            cancelPendingPlaybackResume()
        }

        if !state.isBuffering {
            cancelDubPlaybackRecovery()
        }

        if let sessionID = dubSessionID {
            activateLocalDubFallbackIfReady(sessionID: sessionID)
        }

        if isLocalDubFallbackActive {
            setPrimaryPlayerMuted(true)
            dubFallbackPlayer.sync(
                to: state.currentTime,
                isPlaying: state.isPlaying,
                isBuffering: state.isBuffering,
                playbackSpeed: playbackSpeed
            )
        }

        if dubSessionID != nil, hasLoadedDubbedMaster {
            reconcileDubTrackSelection(at: state.currentTime)
        }
    }
}

extension PlayerManager: PlayerLifecycleReporting {
    func playerDidBecomeReady() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.playerDidBecomeReady()
            }
            return
        }
        isMediaReady = true
        debugLog(
            "Player became ready current=\(debugInterval(currentTime)) " +
            "duration=\(debugInterval(duration)) shouldResume=\(shouldResumePlaybackAfterStall)"
        )
        cancelDubPlaybackRecovery()
        schedulePlaybackResumeIfNeeded(trigger: "media-ready")
        if let sessionID = dubSessionID {
            activateLocalDubFallbackIfReady(sessionID: sessionID)
            scheduleDubCompletionResyncIfNeeded(sessionID: sessionID, trigger: "media-ready")
        }
        if isLocalDubFallbackActive {
            setPrimaryPlayerMuted(true)
            dubFallbackPlayer.sync(
                to: currentPlayer?.currentTime ?? currentTime,
                isPlaying: isPlaying,
                isBuffering: isBuffering,
                playbackSpeed: playbackSpeed,
                forceSeek: true
            )
        }
    }

    private func performPlaybackResumeAttempt() {
        debugLog(
            "Performing playback resume attempt current=\(debugInterval(currentTime)) " +
            "mediaReady=\(isMediaReady) playerIsPlaying=\(currentPlayer?.isPlaying ?? false) " +
            "buffering=\(currentPlayer?.isBuffering ?? false)"
        )
        if playbackResumeProgressReferenceTime == nil {
            playbackResumeProgressReferenceTime = max(currentPlayer?.currentTime ?? currentTime, 0)
        }
        playbackManager?.play()
        if isLocalDubFallbackActive {
            dubFallbackPlayer.play(rate: playbackSpeed)
        }
        isPlaying = true
        isBuffering = currentPlayer?.isBuffering ?? true
    }

    private func schedulePlaybackResumeIfNeeded(trigger: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.schedulePlaybackResumeIfNeeded(trigger: trigger)
            }
            return
        }

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
            ?? max(currentPlayer?.currentTime ?? currentTime, 0)
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
    
    func playerDidUpdateTracks() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.playerDidUpdateTracks()
            }
            return
        }
        refreshTrackInfo()
        if let sessionID = dubSessionID {
            activateLocalDubFallbackIfReady(sessionID: sessionID)
            scheduleDubCompletionResyncIfNeeded(sessionID: sessionID, trigger: "tracks-updated")
        }
        if isLocalDubFallbackActive {
            setPrimaryPlayerMuted(true)
            dubFallbackPlayer.sync(
                to: currentPlayer?.currentTime ?? currentTime,
                isPlaying: isPlaying,
                isBuffering: isBuffering,
                playbackSpeed: playbackSpeed
            )
            return
        }
        if hasLoadedDubbedMaster {
            reconcileDubTrackSelection()
        }
    }
    
    func playerDidEndPlayback() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.playerDidEndPlayback()
            }
            return
        }
        shouldResumePlaybackAfterStall = false
        videoDidEnd()
    }

    func playerDidStall() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.playerDidStall()
            }
            return
        }

        isBuffering = true
        let stalledTime = max(currentPlayer?.currentTime ?? currentTime, 0)
        debugLog(
            "Player stalled current=\(debugInterval(stalledTime)) " +
            "buffered=\(debugInterval(bufferedDuration)) shouldResume=\(shouldResumePlaybackAfterStall)"
        )

        guard shouldResumePlaybackAfterStall else {
            debugLog("Ignoring stall recovery because playback is paused. time=\(stalledTime)")
            return
        }

        if let sessionID = dubSessionID,
           hasLoadedDubbedMaster,
           !allowProgressiveDubSwitching {
            debugLog(
                "Dubbed stream stalled in stable mode. Restoring original playback. " +
                "session_id=\(sessionID) time=\(stalledTime) buffered=\(bufferedDuration)"
            )
            stopDubbingAndReturnToOriginalAudio(reason: "Dubbed stream stalled in stable mode.")
            return
        }

        if let sessionID = dubSessionID,
           hasLoadedDubbedMaster,
           !isLocalDubFallbackActive,
           isDubTrackCurrentlySelected {
            debugLog(
                "Player stalled during dubbed playback. session_id=\(sessionID) " +
                "time=\(stalledTime) buffered=\(bufferedDuration)"
            )
            recoverDubbedPlaybackStall(sessionID: sessionID, stalledTime: stalledTime)
            return
        }

        schedulePlaybackResumeIfNeeded(trigger: "stall")
    }
    
    func playerDidChangePiPState(isActive: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.playerDidChangePiPState(isActive: isActive)
            }
            return
        }
        isPiPActive = isActive
    }
    
    func playerDidFail(with error: PlayerKitError) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.playerDidFail(with: error)
            }
            return
        }

        cancelPendingPlaybackResume()

        if recoverFromDubbedMediaFailureIfNeeded(error) {
            return
        }

        reportError(error)
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
