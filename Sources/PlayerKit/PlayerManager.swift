import Foundation
import Combine

enum DubSwitchPolicy {
    private static let preparationLeadSeconds = 6.0
    private static let activationHeadroomSeconds = 8.0

    static func hasPlayableDubData(
        segmentsReady: Int,
        totalSegments: Int,
        chunkCount: Int,
        resumePosition: Double,
        knownDuration: Double,
        coverageStart: Double? = nil,
        coverageEnd: Double? = nil
    ) -> Bool {
        guard chunkCount > 0 else { return false }
        guard segmentsReady >= 3 else { return false }
        if let windowAllowsPlayback = timelineWindowAllowsPlayback(
            resumePosition: resumePosition,
            coverageStart: coverageStart,
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
        coverageStart: Double? = nil,
        coverageEnd: Double? = nil
    ) -> Bool {
        guard chunkCount > 0 else { return false }
        if let coverageStart, coverageStart.isFinite {
            return resumePosition + preparationLeadSeconds >= coverageStart
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
        if shouldPrepareDubMaster(
            segmentsReady: segmentsReady,
            totalSegments: totalSegments,
            chunkCount: chunkCount,
            resumePosition: resumePosition,
            knownDuration: knownDuration,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd
        ) {
            return true
        }

        let normalizedStatus = (status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedStatus == "complete"
            || normalizedStatus == "completed"
            || normalizedStatus == "ready"
    }

    private static func timelineWindowAllowsPlayback(
        resumePosition: Double,
        coverageStart: Double?,
        coverageEnd: Double?
    ) -> Bool? {
        guard let coverageStart,
              let coverageEnd,
              coverageStart.isFinite,
              coverageEnd.isFinite,
              coverageEnd > coverageStart else {
            return nil
        }

        let effectiveResumePosition = max(resumePosition, 0)
        guard effectiveResumePosition + 0.35 >= coverageStart else { return false }
        return coverageEnd >= effectiveResumePosition + activationHeadroomSeconds
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

public class PlayerManager: ObservableObject {
    public static let shared = PlayerManager()
    
    // State management
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
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
    
    @Published var selectedPlayerType: PlayerType = UserDefaults.standard.loadPlayerType() ?? .avPlayer {
        didSet {
            UserDefaults.standard.savePlayerType(selectedPlayerType)
        }
    }
    @Published var playerItem: PlayerItem?
    @Published var playerItems: [PlayerItem] = []
    @Published var currentPlayerItemIndex: Int = 0
    @Published public var contentType: PlayerContentType = .movie
    @Published var shouldDismiss: Bool = false {
        didSet {
            playbackManager?.stop()
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
    @Published public var isMediaReady: Bool = false {
        didSet {
            if isMediaReady {
                refreshTrackInfo()
                NotificationCenter.default.post(name: .PlayerKitMediaReady, object: nil)
            }
        }
    }
    @Published var isVideoEnded: Bool = false
    
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
    public weak var currentPlayer: PlayerProtocol?
    private var lastPosition: Double = 0
    private var integrationsConfigured = false
    private var dubberConfiguration: DubberConfiguration?
    private let dubberClient = DubberClient()
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
    
    private var stateCancellables = Set<AnyCancellable>()
    private var longLivedCancellables = Set<AnyCancellable>()
    
    private init() {
        setupGestureHandling()
        configureOrientationCallbacks()
    }
    
    // MARK: - Player Setup
    
    public func setPlayer(type: PlayerType? = nil) {
        configureIntegrationsIfNeeded()
        let type = type ?? UserDefaults.standard.loadPlayerType() ?? .avPlayer
        debugLog("Setting player type=\(type)")
        resetPlayer()
        selectedPlayerType = type
        let provider = PlayerFactory.getProvider(for: type)
        setupPlayer(provider: provider)
    }

    func ensurePlayerConfigured(type: PlayerType? = nil) {
        if let type, selectedPlayerType != type {
            setPlayer(type: type)
            return
        }

        if currentPlayer == nil {
            setPlayer(type: type)
        }
    }
    
    private func setupPlayer(provider: PlayerProvider) {
        currentProvider = provider
        let player = provider.createPlayer()
        currentPlayer = player
        bindPlayerCallbacks(player)
        
        // Initialize managers with the player instance
        playbackManager = PlaybackManager(player: player, playerManager: self)
        trackManager = TrackManager(player: player)
        
        observePlayerState()
    }
    
    // MARK: - Switch Player at Runtime
    
    public func switchPlayer(to type: PlayerType) {
        guard selectedPlayerType != type else { return } // No need to switch if already selected
        // Store the last position before switching players
        lastPosition = currentPlayer?.currentTime ?? 0
        saveCurrentTracks()
        setPlayer(type: type)
        
        // Reload the current media if videoURL is already set
        if let url = playerItem?.url {
            load(url: url, lastPosition: lastPosition)
        }
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
        guard hasActiveDubWorkflow else { return }

        let sourceItem = activeDubSourceItem
        let shouldRestoreSource = hasLoadedDubbedMaster && sourceItem != nil
        let resumePosition = max(currentPlayer?.currentTime ?? currentTime, 0)

        cancelDubWorkflow(reason: "User requested to stop dubbing.")
        clearError()

        if shouldRestoreSource, let sourceItem {
            let restoredItem = PlayerItem(
                title: sourceItem.title,
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

            playerItem = restoredItem
            if !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count {
                playerItems[currentPlayerItemIndex] = restoredItem
            }
            load(url: sourceItem.url, lastPosition: resumePosition)
        }

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
                configuration: configuration,
                language: resolvedLanguage,
                translateFrom: resolvedTranslateFrom
            )

            dubSessionID = sessionID
            recordDubActivity(
                "Dubber connected. Waiting for live voice updates.",
                level: .success,
                signature: "dub-session-started"
            )
            debugLog("Dub session started. session_id=\(sessionID)")
            startDubberPolling(
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
        clearError()
        isMediaReady = false
        isVideoEnded = false
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
        if contentType == .movie {
            // Dismiss the player immediately for movies
            isVideoEnded = true
        } else {
            // Check if there are more episodes to play
            playNext()
        }
    }
    
    // MARK: - Player Items Navigation
    public func playNext() {
        NotificationCenter.default.post(name: .PlayerKitNextItem, object: nil)
        saveCurrentTracks()
        guard !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count - 1 else { return }
        currentPlayerItemIndex += 1
        loadPlayerItem(at: currentPlayerItemIndex)
    }
    
    public func playPrevious() {
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
        playbackManager?.play()
        if isLocalDubFallbackActive {
            dubFallbackPlayer.play(rate: playbackSpeed)
        }
        isPlaying = true
        userInteracted()
    }
    
    public func pause() {
        playbackManager?.pause()
        if isLocalDubFallbackActive {
            dubFallbackPlayer.pause()
        }
        isPlaying = false
        userInteracted()
    }
    
    public func stop() {
        cancelDubWorkflow(reason: "Playback stopped.")
        playbackManager?.stop()
        isPlaying = false
        userInteracted()
    }
    
    public func seek(to time: Double) {
        guard duration != 0 else { return }
        playbackManager?.seek(to: time) { [weak self] success in
            if success {
                self?.currentTime = time
                if self?.isLocalDubFallbackActive == true {
                    self?.dubFallbackPlayer.seek(to: time)
                }
            }
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

        if isCompletionStatus {
            scheduleLocalDubFallbackPreparationIfNeeded(
                sessionID: sessionID,
                poll: poll
            )
        }

        scheduleDubAudioProbeIfNeeded(
            sessionID: sessionID,
            configuration: configuration,
            sourceItem: sourceItem,
            force: isCompletionStatus
        )

        if hasLoadedDubbedMaster, isMediaReady {
            refreshTrackInfo()
            autoSelectDubTrackIfNeeded()
            selectSourceAudioFallbackIfNeeded()
        }

        if isCompletionStatus {
            if isDubbedPlaybackActive {
                recordDubActivity(
                    "Dubbed voice is live.",
                    level: .success,
                    signature: "poll-complete"
                )
                isDubLoading = false
                cancelDubberPolling()
                return
            }

            let completionAge = Date().timeIntervalSince(dubCompletionObservedAt ?? Date())
            if completionAge >= 18 {
                let message = "Dubbing.uz finished translating, but the Uzbek audio stream is still unavailable."
                dubWarningMessage = message
                recordDubActivity(
                    message,
                    level: .warning,
                    signature: "poll-complete-unplayable"
                )
                debugLog(
                    "Dub translation completed without a playable audio stream. " +
                    "session_id=\(sessionID) waited=\(dubDebugInterval(completionAge))"
                )
                isDubLoading = false
                cancelDubberPolling()
            } else {
                dubProgressMessage = "Finalizing playable audio..."
                recordDubActivity(
                    "Dubber is finalizing the playable audio stream.",
                    level: .info,
                    signature: "poll-complete-waiting"
                )
            }
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
            autoSelectDubTrackIfNeeded()
            selectSourceAudioFallbackIfNeeded()
        }
    }

    fileprivate func shouldProbeDubAudio(at playbackTime: Double) -> Bool {
        guard dubReadyChunkCount > 0 || isCompletionState(dubStatus) else { return false }

        if let dubCoverageEndTime, dubCoverageEndTime.isFinite,
           playbackTime - 0.35 > dubCoverageEndTime {
            return false
        }

        if let dubCoverageStartTime, dubCoverageStartTime.isFinite {
            return playbackTime + 6 >= dubCoverageStartTime
        }

        return dubReadyChunkCount > 0
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
                            self.reportError(.dubberRequestFailed("Dub status stream disconnected."))
                            self.isDubLoading = false
                            self.cancelDubberStallWatchdog()
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
                            self.debugLog(
                                "Dub SSE failed. session_id=\(sessionID) " +
                                "error=\(self.networkErrorDebugDetails(error))"
                            )
                            self.recordDubActivity(
                                "Live dubbing stopped because the status stream failed.",
                                level: .error,
                                signature: "sse-failed"
                            )
                            self.reportError(.dubberRequestFailed(error.localizedDescription))
                            self.isDubLoading = false
                            self.cancelDubberStallWatchdog()
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
                            self.debugLog(
                                "Dub SSE failed after retries. session_id=\(sessionID) " +
                                "error=\(self.networkErrorDebugDetails(error))"
                            )
                            self.recordDubActivity(
                                "Dubber could not reconnect after several tries.",
                                level: .error,
                                signature: "sse-retries-exhausted"
                            )
                            self.reportError(.dubberRequestFailed(error.localizedDescription))
                            self.isDubLoading = false
                            self.cancelDubberStallWatchdog()
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

            scheduleDubAudioProbeIfNeeded(
                sessionID: sessionID,
                configuration: configuration,
                sourceItem: sourceItem,
                force: isCompletionStatus
            )

            if hasLoadedDubbedMaster, isMediaReady {
                refreshTrackInfo()
                autoSelectDubTrackIfNeeded()
                selectSourceAudioFallbackIfNeeded()
            }

            if isCompletionStatus {
                debugLog("Dub SSE complete update. session_id=\(sessionID)")
                if isDubbedPlaybackActive {
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
                scheduleDubAudioProbeIfNeeded(
                    sessionID: sessionID,
                    configuration: configuration,
                    sourceItem: sourceItem,
                    force: true
                )
            }

            debugLog("Dub SSE done. session_id=\(sessionID) status=\(done.status ?? "unknown")")
            recordDubActivity(
                "Dubber finished sending updates for this session.",
                level: .success,
                signature: "sse-done"
            )
            isDubLoading = false
            cancelDubberStallWatchdog()
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
        resetDubActivityLog()
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

    fileprivate func autoSelectDubTrackIfNeeded() {
        guard !isLocalDubFallbackActive else { return }
        guard !hasAutoSelectedDubTrack else { return }
        guard let dubTrack = availableAudioTracks.first(where: { isLikelyDubTrack($0) }) else { return }

        debugLog("Auto-selecting dub track: \(dubTrack.name) (\(dubTrack.id))")
        selectAudioTrack(track: dubTrack)
        refreshTrackInfo()

        if let selectedAudio, isLikelyDubTrack(selectedAudio) {
            hasAutoSelectedDubTrack = true
            isDubbedPlaybackActive = true
            hasAppliedSourceAudioFallback = false
            isDubLoading = false
            dubWarningMessage = nil
            playbackManager?.play()
            isPlaying = true
            recordDubActivity(
                "Dubbed audio is now active.",
                level: .success,
                signature: "dub-audio-active"
            )
            return
        }

        debugLog("Dub track selection did not stick yet; will retry when tracks update again.")
    }

    fileprivate func selectSourceAudioFallbackIfNeeded() {
        guard !isLocalDubFallbackActive else { return }
        guard !hasAutoSelectedDubTrack else { return }
        guard !hasAppliedSourceAudioFallback else { return }

        if let selectedAudio, !isLikelyDubTrack(selectedAudio) {
            isDubbedPlaybackActive = false
            hasAppliedSourceAudioFallback = true
            return
        }

        guard let fallbackTrack = availableAudioTracks.first(where: { !isLikelyDubTrack($0) }) else { return }
        debugLog("Selecting source audio while dubbing is in progress: \(fallbackTrack.name) (\(fallbackTrack.id))")
        selectAudioTrack(track: fallbackTrack)
        isDubbedPlaybackActive = false
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
        cancelDubWorkflow(reason: "Resetting player manager.")

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
        
        currentTime = 0
        duration = 0
        
        userInteracting = false
        isLocked = false
        isMediaReady = false
        isVideoEnded = false
        shouldDismiss = false
        clearError()
        
        selectedAudio = nil
        selectedSubtitle = nil
        availableAudioTracks = []
        availableSubtitles = []
        playerItem = nil
        playerItems = []
        currentPlayerItemIndex = 0
        contentType = .movie
        
        stateCancellables.removeAll()
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
        (currentPlayer as? AVPlayerWrapper)?.setMuted(muted)
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

        if let sessionID = dubSessionID,
           let configuration = dubberConfiguration,
           let sourceItem = activeDubSourceItem {
            scheduleDubAudioProbeIfNeeded(
                sessionID: sessionID,
                configuration: configuration,
                sourceItem: sourceItem
            )
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
        if let sessionID = dubSessionID {
            activateLocalDubFallbackIfReady(sessionID: sessionID)
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
            autoSelectDubTrackIfNeeded()
            selectSourceAudioFallbackIfNeeded()
        }
    }
    
    func playerDidEndPlayback() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.playerDidEndPlayback()
            }
            return
        }
        videoDidEnd()
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
                    self.isPlaying ? self.pause() : self.play()
                    
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
