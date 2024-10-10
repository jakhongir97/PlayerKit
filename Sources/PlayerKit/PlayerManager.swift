import Foundation
import Combine

public class PlayerManager: ObservableObject {
    public static let shared = PlayerManager()

    // Published properties to reflect the state of the player
    @Published public var availableAudioTracks: [String] = []
    @Published public var availableSubtitles: [String] = []
    @Published public var selectedAudioTrackIndex: Int?
    @Published public var selectedSubtitleTrackIndex: Int?
    @Published public var isPlaying: Bool = false
    @Published public var isBuffering: Bool = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0

    // Seeking-related state
    @Published public var isSeeking: Bool = false
    @Published public var seekTime: Double = 0  // Temporarily hold the seek time while dragging

    public var currentPlayer: PlayerProtocol?

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
        currentPlayer?.seek(to: time)
        DispatchQueue.main.async {
            self.currentTime = time
        }
    }

    /// Handle the start of seeking interaction
    public func startSeeking() {
        isSeeking = true
    }

    /// Handle the end of seeking interaction
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
            print("Track info refreshed. Audio tracks: \(self.availableAudioTracks), Subtitles: \(self.availableSubtitles)")
        }
    }

    /// Select an audio track by index
    public func selectAudioTrack(index: Int) {
        currentPlayer?.selectAudioTrack(index: index)
        DispatchQueue.main.async {
            self.selectedAudioTrackIndex = index
            print("Selected audio track index: \(index)")
        }
    }

    /// Select a subtitle track by index
    public func selectSubtitle(index: Int) {
        currentPlayer?.selectSubtitle(index: index)
        DispatchQueue.main.async {
            self.selectedSubtitleTrackIndex = index
            print("Selected subtitle index: \(index)")
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
                
                // Update the published properties
                self.isPlaying = player.isPlaying
                self.isBuffering = player.isBuffering
                self.currentTime = player.currentTime
                self.duration = player.duration
            }
            .store(in: &cancellables)
    }

    // MARK: - Helper Methods

    /// Update available audio and subtitle tracks
    public func updateTrackInfo(audioTracks: [String], subtitles: [String]) {
        DispatchQueue.main.async {
            self.availableAudioTracks = audioTracks
            self.availableSubtitles = subtitles
        }
    }
}

