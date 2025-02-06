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
    @Published var selectedAudioTrackID: String?
    @Published var selectedSubtitleTrackID: String?
    @Published var availableAudioTracks: [TrackInfo] = []
    @Published var availableSubtitles: [TrackInfo] = []
    private var savedAudioTrackID: String?
    private var savedSubtitleTrackID: String?
    
    @Published var selectedPlayerType: PlayerType = .avPlayer
    @Published var playerItem: PlayerItem?
    @Published var playerItems: [PlayerItem] = []
    @Published var currentPlayerItemIndex: Int = 0
    @Published public var contentType: PlayerContentType = .movie
    @Published var shouldDissmiss: Bool = false {
        didSet {
            playbackManager?.stop()
        }
    }
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
    let castManager = CastManager.shared
    let gestureManager = GestureManager()
    
    // Lazy initialization for controlVisibilityManager
    lazy var controlVisibilityManager: ControlVisibilityManager = {
        ControlVisibilityManager(playerManager: self)
    }()
    
    private var currentProvider: PlayerProvider?
    public weak var currentPlayer: PlayerProtocol?
    private var lastPosition: Double = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        AudioSessionManager.shared.configureAudioSession()
        setupGestureHandling()
        subscribeToGameControllerEvents()
    }
    
    // MARK: - Player Setup
    
    public func setPlayer(type: PlayerType = .avPlayer) {
        resetPlayer()
        selectedPlayerType = type
        let provider = PlayerFactory.getProvider(for: type)
        setupPlayer(provider: provider)
    }
    
    private func setupPlayer(provider: PlayerProvider) {
        currentProvider = provider
        let player = provider.createPlayer()
        currentPlayer = player
        
        // Initialize managers with the player instance
        playbackManager = PlaybackManager(player: player, playerManager: self)
        trackManager = TrackManager(player: player)
        
        refreshTrackInfo()
        observePlayerState()
    }
    
    // MARK: - Switch Player at Runtime
    
    public func switchPlayer(to type: PlayerType) {
        guard selectedPlayerType != type else { return } // No need to switch if already selected
        
        // Store the last position before switching players
        lastPosition = currentPlayer?.currentTime ?? 0
        resetPlayer()
        setPlayer(type: type)
        
        // Reload the current media if videoURL is already set
        if let url = playerItem?.url {
            load(url: url, lastPosition: lastPosition)
        }
    }
    
    public func load(playerItem: PlayerItem) {
        self.playerItem = playerItem
        load(url: playerItem.url, lastPosition: playerItem.lastPosition)
    }
    
    public func loadEpisodes(playerItems: [PlayerItem], currentIndex: Int = 0 ) {
        self.playerItems = playerItems
        currentPlayerItemIndex = currentIndex
        guard let playerItem = playerItems[safe: currentIndex] else { return }
        load(playerItem: playerItem)
    }
    
    // Loads a media URL into the current player
    private func load(url: URL, lastPosition: Double? = nil) {
        currentPlayer?.load(url: url, lastPosition: lastPosition)
        userInteracted()
    }
    
    public func videoDidEnd() {
        guard duration != 0, currentTime + 1 > duration else { return }
        if contentType == .movie {
            // Dismiss the player immediately for movies
            isVideoEnded = true
            shouldDissmiss = true
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
        
        selectedAudioTrackID = trackManager?.currentAudioTrack?.id
        selectedSubtitleTrackID = trackManager?.currentSubtitleTrack?.id
        
        applySavedTrackIdentifiers()
    }
    
    public func selectAudioTrack(withID id: String) {
        selectedAudioTrackID = id
        trackManager?.selectAudioTrack(withID: id)
        userInteracted()
    }
    
    public func selectSubtitle(withID id: String?) {
        selectedSubtitleTrackID = id
        trackManager?.selectSubtitle(withID: id)
        userInteracted()
    }
    
    private func saveCurrentTracks() {
        savedAudioTrackID = selectedAudioTrackID
        savedSubtitleTrackID = selectedSubtitleTrackID
    }
    
    private func applySavedTrackIdentifiers() {
        if let audioID = savedAudioTrackID,
           availableAudioTracks.contains(where: { $0.id == audioID }) {
            selectAudioTrack(withID: audioID)
            savedAudioTrackID = nil
        }
        
        if let subtitleID = savedSubtitleTrackID,
           availableSubtitles.contains(where: { $0.id == subtitleID }) {
            selectSubtitle(withID: subtitleID)
            savedSubtitleTrackID = nil
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
        castManager.playMediaOnCast()
    }
    
    public func pauseChromecast() {
        castManager.pauseCast()
    }
    
    public func stopChromecast() {
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
            .store(in: &cancellables)
    }
    
    public func resetPlayer() {
        currentPlayer?.stop()
        currentPlayer = nil
        
        currentTime = 0
        duration = 0
        
        userInteracting = false
        isLocked = false
        isMediaReady = false
        isVideoEnded = false
        shouldDissmiss = false
        
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        availableAudioTracks = []
        availableSubtitles = []
    }
}

extension PlayerManager {
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
                    self.shouldDissmiss = true
                    
                case .focusUp:
                    break
                    
                case .focusDown:
                    break
                    
                case .focusSelect:
                    break
                }
            }
            .store(in: &cancellables)
    }
}
