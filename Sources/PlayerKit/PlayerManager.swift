import Foundation
import MediaPlayer
import UIKit
import Combine

public class PlayerManager: ObservableObject {
    public static let shared = PlayerManager()

    // Published properties to reflect the state of the player
    @Published public var availableAudioTracks: [String] = []
    @Published public var availableSubtitles: [String] = []
    @Published public var availableVideoTracks: [String] = []
    @Published public var selectedAudioTrackIndex: Int?
    @Published public var selectedSubtitleTrackIndex: Int?
    @Published public var selectedVideoTrackIndex: Int?
    @Published public var isPlaying: Bool = false
    @Published public var isBuffering: Bool = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var bufferedDuration: Double = 0
    @Published public var isFullscreen: Bool = false  // Track fullscreen state
    @Published public var isMinimized: Bool = false  // Track minimized state
    @Published public var areControlsVisible: Bool = true
    
    @Published public var selectedPlayerType: PlayerType = .vlcPlayer  // Player type moved here
    @Published public var videoURL: URL?  // Video URL moved here

    // Seeking-related state
    @Published public var isSeeking: Bool = false
    @Published public var seekTime: Double = 0  // Temporarily hold the seek time while dragging
    
    @Published public var isPiPActive: Bool = false

    public var currentPlayer: PlayerProtocol?
    
    // Reference to ThumbnailManager
    public let thumbnailManager = ThumbnailManager.shared
    public let gestureManager = GestureManager()

    private var cancellables = Set<AnyCancellable>()
    private var autoHideTimer: AnyCancellable?

    // Singleton initializer
    private init() {
    }

    // MARK: - Player Setup

    /// Set the player type (AVPlayer or VLCPlayer)
    public func setPlayer(type: PlayerType) {
        selectedPlayerType = type
        switch type {
        case .vlcPlayer:
            currentPlayer = VLCPlayerWrapper()  // Assuming VLCPlayerWrapper exists
        case .avPlayer:
            currentPlayer = AVPlayerWrapper()  // Assuming AVPlayerWrapper exists
        }
        
        // Refresh available tracks and observe player state
        refreshTrackInfo()
        observePlayerState()
        setupGestureHandling()
    }
    
    public func switchPlayer(to type: PlayerType) {
        let lastPosition = currentTime  // Save the current time before switching
        setPlayer(type: type)  // Switch player
        if let url = videoURL {
            load(url: url)  // Reload the video with the new player
            seek(to: lastPosition)  // Seek to the saved position after loading
        }
    }

    // MARK: - Load Media

    /// Load a media URL into the player
    public func load(url: URL) {
        videoURL = url
        currentPlayer?.load(url: url)
        refreshTrackInfo()
        userInteracted()
        setupPiP()
    }

    // MARK: - Play/Pause Controls

    /// Play the media
    public func play() {
        currentPlayer?.play()
        DispatchQueue.main.async {
            self.isPlaying = true
        }
       userInteracted()
    }

    /// Pause the media
    public func pause() {
        currentPlayer?.pause()
        DispatchQueue.main.async {
            self.isPlaying = false
        }
        userInteracted()
    }

    // MARK: - Seeking Controls

    /// Seek to a specific time in the media
    public func seek(to time: Double) {
        isSeeking = true  // Mark that we are seeking
        isBuffering = true  // Start showing buffering during seeking
        currentPlayer?.seek(to: time) { [weak self] success in
            guard let self = self else { return }
            if success {
                DispatchQueue.main.async {
                    self.currentTime = time
                    self.isSeeking = false  // Update after seek completes
                    self.isBuffering = false  // Hide buffering after seek completes and playback resumes
                }
            } else {
                DispatchQueue.main.async {
                    self.isBuffering = false  // Hide buffering if seek fails
                }
            }
        }
        userInteracted()
    }

    /// Handle the start of seeking interaction (user starts dragging the slider)
    public func startSeeking() {
        isSeeking = true
    }

    /// Handle the end of seeking interaction (user stops dragging the slider)
    public func stopSeeking() {
        isSeeking = false
        seek(to: seekTime)  // Seek to the selected seek time
    }

    // MARK: - Track Management

    /// Refresh the available audio and subtitle tracks
    public func refreshTrackInfo() {
        guard let player = currentPlayer else {
            print("No current player available.")
            return
        }

        DispatchQueue.main.async {
            self.availableAudioTracks = player.availableAudioTracks
            self.availableSubtitles = player.availableSubtitles
        }
    }

    /// Select an audio track by index
    public func selectAudioTrack(index: Int) {
        currentPlayer?.selectAudioTrack(index: index)
        DispatchQueue.main.async {
            self.selectedAudioTrackIndex = index
        }
    }

    /// Select a subtitle track by index
    public func selectSubtitle(index: Int) {
        currentPlayer?.selectSubtitle(index: index)
        DispatchQueue.main.async {
            self.selectedSubtitleTrackIndex = index
        }
    }

    // Switch video track on the active player
    public func selectVideoTrack(index: Int) {
        currentPlayer?.selectVideoTrack(index: index)
        DispatchQueue.main.async {
            self.selectedVideoTrackIndex = index
        }
    }
    
    // Playback speed control
    public var playbackSpeed: Float {
        get {
            return currentPlayer?.playbackSpeed ?? 1.0
        }
        set {
            currentPlayer?.playbackSpeed = newValue
        }
    }

    // MARK: - Player State Observation

    /// Observe player state (e.g., buffering, play/pause, current time, and duration)
    private func observePlayerState() {
        // Regularly poll the player's state every 0.5 seconds
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let player = self.currentPlayer else { return }

                // Do not update currentTime while seeking
                if !self.isSeeking {
                    self.isPlaying = player.isPlaying
                    self.isBuffering = player.isBuffering
                    self.currentTime = player.currentTime
                    self.duration = player.duration
                    self.bufferedDuration = player.bufferedDuration
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Helper Methods

    /// Update available audio and subtitle tracks
    public func updateTrackInfo(audioTracks: [String], subtitles: [String], videoTracks: [String]) {
        DispatchQueue.main.async {
            self.availableAudioTracks = audioTracks
            self.availableSubtitles = subtitles
            self.availableVideoTracks = videoTracks
        }
    }
    
    // MARK: - Thumbnail Management
    /// Requests a thumbnail at the specified time
    public func requestThumbnail(at time: Double) {
        if let player = currentPlayer {
            thumbnailManager.requestThumbnail(for: player, at: time)
            print("PlayerManager: Requested thumbnail at \(time) seconds.")
        } else {
            print("PlayerManager: No current player available for thumbnail request.")
        }
    }
}

extension PlayerManager {
    private func setupGestureHandling() {
        // Handle seek gesture
        gestureManager.onSeek = { [weak self] newTime in
            print("Seek gesture triggered: \(newTime)")
            self?.currentPlayer?.seek(to: newTime, completion: nil)
        }
        
        // Handle control toggle (tap gesture)
        gestureManager.onToggleControls = { [weak self] in
            guard let self = self else { return }
            
            if self.areControlsVisible {
                // Controls are visible, restart the auto-hide timer
                self.hideControls()
            } else {
                // Show controls immediately and start the auto-hide timer
                self.showControls()  // This will display the controls and start the auto-hide timer
            }
        }

    }
}

extension PlayerManager {
    
    // MARK: - Setup Auto-Hide for Controls
    
    /// Start the timer to auto-hide controls after a delay
    private func startAutoHideTimer() {
        stopAutoHideTimer()  // Ensure no existing timer is running
        
        autoHideTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.hideControls()
            }
    }
    
    /// Stop the auto-hide timer
    private func stopAutoHideTimer() {
        autoHideTimer?.cancel()
        autoHideTimer = nil
    }
    
    /// Show the controls and restart the auto-hide timer
    public func showControls() {
        areControlsVisible = true
        startAutoHideTimer()  // Restart the auto-hide timer
    }
    
    /// Hide the controls
    private func hideControls() {
        areControlsVisible = false
        stopAutoHideTimer()  // Stop the timer after hiding controls
    }

    // Call this in each interaction method like play, pause, seek, etc.
    public func userInteracted() {
        showControls()  // Show controls and restart the auto-hide timer
    }
}

extension PlayerManager {
    // Start PiP using the current player
    public func startPiP() {
        currentPlayer?.startPiP()
    }
    
    // Stop PiP using the current player
    public func stopPiP() {
        currentPlayer?.stopPiP()
    }
    
    // Setup PiP for the current player
    public func setupPiP() {
        currentPlayer?.setupPiP()
    }
}
