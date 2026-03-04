import Foundation
import Combine

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
            debugLog(
                "Dubber configured. base=\(configuration.baseURL.debugDescription) " +
                "timeout=\(dubDebugInterval(configuration.eventStreamRequestTimeout)) " +
                "reconnect_delay=\(dubDebugInterval(configuration.eventStreamReconnectDelay)) " +
                "max_retries=\(retryBudgetLabel(configuration))"
            )
        } else {
            debugLog("Dubber disabled.")
        }
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

        ensurePlayerConfigured()
        cancelDubberEvents()
        cancelDubberStallWatchdog()
        saveCurrentTracks()
        hasAutoSelectedDubTrack = false
        hasLoadedDubbedMaster = false
        hasAppliedSourceAudioFallback = false
        dubSwitchAttemptCount = 0
        hasDubSwitchFailed = false
        dubTargetLanguageCode = (language ?? configuration.defaultLanguage).lowercased()
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
        clearError()
        userInteracted()
        debugLog(
            "Starting dubbed playback. source=\(sourceItem.url.debugDescription) " +
            "language=\(language ?? configuration.defaultLanguage) " +
            "translate_from=\(translateFrom ?? configuration.defaultTranslateFrom)"
        )

        do {
            let sessionID = try await dubberClient.startSession(
                sourceURL: sourceItem.url,
                configuration: configuration,
                language: language,
                translateFrom: translateFrom
            )

            dubSessionID = sessionID
            debugLog("Dub session started. session_id=\(sessionID)")
            startDubberStallWatchdog(sessionID: sessionID)
            startDubberEvents(
                sessionID: sessionID,
                configuration: configuration,
                sourceItem: sourceItem
            )
        } catch let playerError as PlayerKitError {
            debugLog("Dubbed playback failed with PlayerKitError: \(playerError.localizedDescription)")
            reportError(playerError)
            isDubLoading = false
            cancelDubberStallWatchdog()
        } catch {
            debugLog("Dubbed playback failed: \(error.localizedDescription)")
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
        isDubberEnabled && !isDubLoading && playerItem != nil
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
        isPlaying = true
        userInteracted()
    }
    
    public func pause() {
        playbackManager?.pause()
        isPlaying = false
        userInteracted()
    }
    
    public func stop() {
        playbackManager?.stop()
        userInteracted()
    }
    
    public func seek(to time: Double) {
        guard duration != 0 else { return }
        playbackManager?.seek(to: time) { [weak self] success in
            if success {
                self?.currentTime = time
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

        dubberEventsTask = Task { [weak self] in
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
            }
            if let progress = update.progress, !progress.isEmpty {
                dubProgressMessage = progress
            }
            if let segmentsReady = update.segments_ready {
                dubSegmentsReady = max(segmentsReady, 0)
            }
            if let totalSegments = update.total_segments {
                dubTotalSegments = max(totalSegments, 0)
            }

            debugLog(
                "Dub update. session_id=\(sessionID) status=\(update.status ?? "nil") " +
                "progress=\(update.progress ?? "nil") segments=\(dubSegmentsReady)/\(dubTotalSegments) " +
                "error=\(update.error ?? "nil")"
            )

            if let rawError = update.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawError.isEmpty {
                debugLog("Dub update error. session_id=\(sessionID) error=\(rawError)")
                reportError(.dubberRequestFailed(rawError))
                isDubLoading = false
                cancelDubberStallWatchdog()
                cancelDubberEvents()
                return
            }

            if !hasLoadedDubbedMaster, isDubStreamReadyToSwitch(update) {
                loadDubbedMaster(
                    sessionID: sessionID,
                    configuration: configuration,
                    sourceItem: sourceItem
                )
            }

            if hasLoadedDubbedMaster, isMediaReady {
                refreshTrackInfo()
                autoSelectDubTrackIfNeeded()
                selectSourceAudioFallbackIfNeeded()
            }

            let normalizedStatus = (update.status ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalizedStatus == "complete" {
                debugLog("Dub SSE complete update. session_id=\(sessionID)")
                isDubLoading = false
                cancelDubberStallWatchdog()
            }

        case .warning(let warning):
            let message = warning.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                dubWarningMessage = message
                debugLog("Dub warning. session_id=\(sessionID) message=\(message)")
            }

        case .done(let done):
            if let status = done.status, !status.isEmpty {
                dubStatus = status
            }
            debugLog("Dub SSE done. session_id=\(sessionID) status=\(done.status ?? "unknown")")
            isDubLoading = false
            cancelDubberStallWatchdog()
            cancelDubberEvents()
        }
    }

    fileprivate func cancelDubberEvents() {
        dubberEventsTask?.cancel()
        dubberEventsTask = nil
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
            castVideoUrl: sourceItem.castVideoUrl,
            lastPosition: resumePosition,
            episodeIndex: sourceItem.episodeIndex
        )

        hasLoadedDubbedMaster = true
        hasAppliedSourceAudioFallback = false
        dubSwitchAttemptCount += 1
        savedAudio = nil
        savedSubtitle = nil
        playerItem = dubbedItem
        if !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count {
            playerItems[currentPlayerItemIndex] = dubbedItem
        }
        load(url: masterURL, lastPosition: resumePosition)
        isDubLoading = false
        debugLog(
            "Dub segments ready. Switching to dubbed master. session_id=\(sessionID) " +
            "master=\(masterURL.debugDescription) resume=\(resumePosition)"
        )
    }

    fileprivate func autoSelectDubTrackIfNeeded() {
        guard !hasAutoSelectedDubTrack else { return }
        guard let dubTrack = availableAudioTracks.first(where: { isLikelyDubTrack($0) }) else { return }

        debugLog("Auto-selecting dub track: \(dubTrack.name) (\(dubTrack.id))")
        selectAudioTrack(track: dubTrack)
        hasAutoSelectedDubTrack = true
    }

    fileprivate func selectSourceAudioFallbackIfNeeded() {
        guard !hasAutoSelectedDubTrack else { return }
        guard !hasAppliedSourceAudioFallback else { return }

        if let selectedAudio, !isLikelyDubTrack(selectedAudio) {
            hasAppliedSourceAudioFallback = true
            return
        }

        guard let fallbackTrack = availableAudioTracks.first(where: { !isLikelyDubTrack($0) }) else { return }
        debugLog("Selecting source audio while dubbing is in progress: \(fallbackTrack.name) (\(fallbackTrack.id))")
        selectAudioTrack(track: fallbackTrack)
        hasAppliedSourceAudioFallback = true
    }

    fileprivate func isDubStreamReadyToSwitch(_ update: DubberClient.UpdatePayload) -> Bool {
        guard !hasDubSwitchFailed else { return false }
        let segmentsReady = max(update.segments_ready ?? 0, 0)
        let totalSegments = max(update.total_segments ?? 0, 0)
        guard segmentsReady >= 3 else { return false }

        let resumePosition = max(currentPlayer?.currentTime ?? currentTime, 0)
        guard resumePosition > 0 else { return true }

        guard totalSegments > 0 else { return true }

        let knownDuration = max(duration, resumePosition)
        guard knownDuration > 0 else { return true }

        // Keep a small margin so playback doesn't immediately hit an untranslated gap.
        let translatedFraction = Double(segmentsReady) / Double(totalSegments)
        let translatedCoverageSeconds = translatedFraction * knownDuration
        return translatedCoverageSeconds >= resumePosition + 3
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
        hasDubSwitchFailed = true
        hasLoadedDubbedMaster = false
        hasAppliedSourceAudioFallback = false
        hasAutoSelectedDubTrack = false
        isDubLoading = true

        playerItem = sourceItem
        if !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count {
            playerItems[currentPlayerItemIndex] = sourceItem
        }
        debugLog(
            "Dub stream failed to open, reverting to source while translation continues. " +
            "resume=\(resumePosition) attempts=\(dubSwitchAttemptCount)"
        )
        load(url: sourceItem.url, lastPosition: resumePosition)
        return true
    }

    fileprivate func debugLog(_ message: String) {
        print("[PlayerKit][PlayerManager] \(message)")
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
        cancelDubberEvents()
        cancelDubberStallWatchdog()

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
        hasAutoSelectedDubTrack = false
        hasLoadedDubbedMaster = false
        hasAppliedSourceAudioFallback = false
        dubTargetLanguageCode = nil
        activeDubSourceItem = nil
        dubSwitchAttemptCount = 0
        hasDubSwitchFailed = false
        
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
    }
    
    func playerDidUpdateTracks() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.playerDidUpdateTracks()
            }
            return
        }
        refreshTrackInfo()
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
