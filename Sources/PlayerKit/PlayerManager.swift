import Foundation
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

    // Seeking-related state
    @Published public var isSeeking: Bool = false
    @Published public var seekTime: Double = 0  // Temporarily hold the seek time while dragging

    public var currentPlayer: PlayerProtocol?
    
    // Reference to ThumbnailManager
    public let thumbnailManager = ThumbnailManager.shared

    private var cancellables = Set<AnyCancellable>()

    // Singleton initializer
    private init() {}

    // MARK: - Player Setup

    /// Set the player type (AVPlayer or VLCPlayer)
    public func setPlayer(type: PlayerType) {
        switch type {
        case .vlcPlayer:
            currentPlayer = VLCPlayerWrapper()  // Assuming VLCPlayerWrapper exists
        case .avPlayer:
            currentPlayer = AVPlayerWrapper()  // Assuming AVPlayerWrapper exists
        }
        
        // Refresh available tracks and observe player state
        refreshTrackInfo()
        observePlayerState()
    }

    // MARK: - Load Media

    /// Load a media URL into the player
    public func load(url: URL) {
        currentPlayer?.load(url: url)
        refreshTrackInfo()
    }

    // MARK: - Play/Pause Controls

    /// Play the media
    public func play() {
        currentPlayer?.play()
        DispatchQueue.main.async {
            self.isPlaying = true
        }
    }

    /// Pause the media
    public func pause() {
        currentPlayer?.pause()
        DispatchQueue.main.async {
            self.isPlaying = false
        }
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

