import Combine
import GoogleCast

public class PlayerManager: ObservableObject {
    public static let shared = PlayerManager()
    
    // State management
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var currentTime: Double = 0
    @Published var seekTime: Double = 0
    @Published var duration: Double = 0
    @Published var bufferedDuration: Double = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var isSeeking: Bool = false
    @Published var isCasting: Bool = false
    @Published var isPiPActive: Bool = false
    @Published var isCastingAvailable: Bool = false
    @Published var areControlsVisible: Bool = true
    @Published var isLocked: Bool = false
    
    // Track indices
    @Published var selectedAudioTrackIndex: Int?
    @Published var selectedSubtitleTrackIndex: Int?
    @Published var availableAudioTracks: [String] = []
    @Published var availableSubtitles: [String] = []
    
    @Published var selectedPlayerType: PlayerType = .vlcPlayer
    @Published var playerItem: PlayerItem?
    @Published var playerItems: [PlayerItem] = []
    @Published var currentPlayerItemIndex: Int = 0
    @Published var isMovie: Bool = true
    @Published var shouldDissmiss: Bool = false {
        didSet {
            playbackManager?.stop()
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
    public var currentPlayer: PlayerProtocol?
    private var lastPosition: Double = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        AudioSessionManager.shared.configureAudioSession()
        setupGestureHandling()
        observeEpisodes()
    }
    
    // MARK: - Player Setup
    
    public func setPlayer(type: PlayerType = .vlcPlayer) {
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
        shouldDissmiss = false
        isVideoEnded = false
        currentPlayer?.load(url: url, lastPosition: lastPosition)
        userInteracted()
    }
    
    public func videoDidEnd() {
        if isMovie {
            // Dismiss the player immediately for movies
            isVideoEnded = true
            shouldDissmiss = true
        } else {
            // Check if there are more episodes to play
            if currentPlayerItemIndex <= playerItems.count - 1 {
                // Play the next episode
                playNext()
            } else {
                // No more episodes, dismiss the player
                isVideoEnded = true
                shouldDissmiss = true
            }
        }
    }
    
    // MARK: - Player Items Navigation
    public func playNext() {
        guard !playerItems.isEmpty, currentPlayerItemIndex < playerItems.count - 1 else { return }
        currentPlayerItemIndex += 1
        loadPlayerItem(at: currentPlayerItemIndex)
    }
    
    public func playPrevious() {
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
        playbackManager?.seek(to: time) { [weak self] success in
            if success {
                self?.currentTime = time
            }
        }
    }
    
    public func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        playbackManager?.setPlaybackSpeed(speed)
    }
    
    // Start seeking
    func startSeeking() {
        isSeeking = true
        // Pause playback if required while seeking
        playbackManager?.pause()
        userInteracted()
    }
    
    // Stop seeking
    func stopSeeking() {
        isSeeking = false
        // Resume playback or seek to new time
        playbackManager?.seek(to: seekTime) { [weak self] success in
            if success {
                self?.currentTime = self?.seekTime ?? 0
            }
            self?.currentPlayer?.play()
        }
        userInteracted()
    }
}

// MARK: - Track Management
extension PlayerManager {
    public func refreshTrackInfo() {
        availableAudioTracks = trackManager?.availableAudioTracks ?? []
        availableSubtitles = trackManager?.availableSubtitles ?? []

        selectedAudioTrackIndex = indexOfCurrentTrack(
            currentTrack: trackManager?.currentAudioTrack,
            availableTracks: availableAudioTracks
        )
        
        selectedSubtitleTrackIndex = indexOfCurrentTrack(
            currentTrack: trackManager?.currentSubtitleTrack,
            availableTracks: availableSubtitles
        )
    }

    // Helper function to find the index of the current track
    private func indexOfCurrentTrack(currentTrack: String?, availableTracks: [String]) -> Int? {
        guard let currentTrack = currentTrack else { return nil }
        return availableTracks.firstIndex(of: currentTrack)
    }

    
    public func selectAudioTrack(index: Int) {
        selectedAudioTrackIndex = index
        trackManager?.selectAudioTrack(index: index)
        userInteracted()
    }
    
    public func selectSubtitle(index: Int?) {
        selectedSubtitleTrackIndex = index
        trackManager?.selectSubtitle(index: index)
        userInteracted()
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


// MARK: - Player State Observation
extension PlayerManager {
    private func observePlayerState() {
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let player = self.currentPlayer else { return }
                guard !isSeeking else { 
                    userInteracted()
                    return
                }
                
                self.isPlaying = player.isPlaying
                self.isBuffering = player.isBuffering
                self.currentTime = player.currentTime
                self.duration = player.duration
                self.bufferedDuration = player.bufferedDuration
            }
            .store(in: &cancellables)
    }
    
    private func observeEpisodes() {
        $playerItems
            .map { $0.isEmpty } // Map episodes to a boolean for `isMovie`
            .assign(to: &$isMovie)
    }
    
    public func resetPlayer() {
        selectedAudioTrackIndex = nil
        selectedSubtitleTrackIndex = nil
        availableAudioTracks = []
        availableSubtitles = []
        
        ThumbnailManager.shared.thumbnailImage = nil
    }
}

