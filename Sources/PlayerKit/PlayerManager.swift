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
    @Published var playbackSpeed: Float = 0
    @Published var isSeeking: Bool = false
    @Published var isCasting: Bool = false
    @Published var isPiPActive: Bool = false
    @Published var isCastingAvailable: Bool = false
    @Published var areControlsVisible: Bool = true
    
    // Track indices
    @Published var selectedAudioTrackIndex: Int?
    @Published var selectedSubtitleTrackIndex: Int?
    @Published var selectedVideoTrackIndex: Int?
    @Published var availableAudioTracks: [String] = []
    @Published var availableSubtitles: [String] = []
    @Published var availableVideoTracks: [String] = []
    
    @Published var selectedPlayerType: PlayerType = .avPlayer
    @Published var videoURL: URL?
    
    // Managers for different responsibilities
    var playbackManager: PlaybackManager?
    var trackManager: TrackManager?
    let castManager = CastManager.shared
    var pipManager: PiPManager?
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
        setPlayer(type: selectedPlayerType)  // Initialize default player
        setupGestureHandling()
    }
    
    // MARK: - Player Setup
    
    public func setPlayer(type: PlayerType) {
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
        pipManager = PiPManager(player: player)
        
        refreshTrackInfo()
        observePlayerState()
    }
    
    // MARK: - Switch Player at Runtime
    
    public func switchPlayer(to type: PlayerType) {
        guard selectedPlayerType != type else { return } // No need to switch if already selected
        
        // Store the last position before switching players
        lastPosition = currentPlayer?.currentTime ?? 0
        
        setPlayer(type: type)
        
        // Reload the current media if videoURL is already set
        if let url = videoURL {
            load(url: url)
            
            // Seek to the saved position after loading the new player
            currentPlayer?.seek(to: lastPosition) { success in
                if success {
                    self.currentTime = self.lastPosition
                }
            }
        }
    }
    
    // Loads a media URL into the current player
    public func load(url: URL) {
        videoURL = url
        currentPlayer?.load(url: url)
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
    
    // Start seeking
    func startSeeking() {
        isSeeking = true
        // Pause playback if required while seeking
        currentPlayer?.pause()
    }
    
    // Stop seeking
    func stopSeeking() {
        isSeeking = false
        // Resume playback or seek to new time
        currentPlayer?.seek(to: seekTime) { [weak self] success in
            if success {
                self?.currentTime = self?.seekTime ?? 0
            }
            self?.currentPlayer?.play()
        }
    }
}

// MARK: - Track Management
extension PlayerManager {
    public func refreshTrackInfo() {
        availableAudioTracks = trackManager?.availableAudioTracks ?? []
        availableSubtitles = trackManager?.availableSubtitles ?? []
        availableVideoTracks = trackManager?.availableVideoTracks ?? []
    }
    
    public func selectAudioTrack(index: Int) {
        trackManager?.selectAudioTrack(index: index)
    }
    
    public func selectSubtitle(index: Int) {
        trackManager?.selectSubtitle(index: index)
    }
    
    public func selectVideoTrack(index: Int) {
        trackManager?.selectVideoTrack(index: index)
    }
}

// MARK: - PiP Controls
extension PlayerManager {
    public func startPiP() {
        pipManager?.startPiP()
    }
    
    public func stopPiP() {
        pipManager?.stopPiP()
    }
}

// MARK: - Chromecast Controls
extension PlayerManager {
    public func playOnChromecast(url: URL) {
        castManager.playMediaOnCast(url: url)
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
                guard !isSeeking else { return }
                
                self.isPlaying = player.isPlaying
                self.isBuffering = player.isBuffering
                self.currentTime = player.currentTime
                self.duration = player.duration
                self.bufferedDuration = player.bufferedDuration
                self.refreshTrackInfo()
            }
            .store(in: &cancellables)
    }
}

