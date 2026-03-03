import Combine
import GoogleCast

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
    }

    @MainActor
    public func startDubbedPlayback(language: String? = nil, translateFrom: String? = nil) async {
        guard !isDubLoading else { return }
        guard let configuration = dubberConfiguration else {
            reportError(.dubberNotConfigured)
            return
        }
        guard let sourceItem = playerItem else {
            reportError(.dubberSourceMissing)
            return
        }

        ensurePlayerConfigured()
        isDubLoading = true
        clearError()
        userInteracted()

        do {
            let sessionID = try await dubberClient.startSession(
                sourceURL: sourceItem.url,
                configuration: configuration,
                language: language,
                translateFrom: translateFrom
            )

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

            dubSessionID = sessionID
            playerItem = dubbedItem
            if !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count {
                playerItems[currentPlayerItemIndex] = dubbedItem
            }
            load(url: masterURL, lastPosition: resumePosition)
        } catch let playerError as PlayerKitError {
            reportError(playerError)
        } catch {
            reportError(.dubberRequestFailed(error.localizedDescription))
        }

        isDubLoading = false
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
