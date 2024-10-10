import Foundation
import Combine

public class PlayerManager: ObservableObject {
    public static let shared = PlayerManager()

    @Published public var availableAudioTracks: [String] = []
    @Published public var availableSubtitles: [String] = []
    @Published public var selectedAudioTrackIndex: Int?
    @Published public var selectedSubtitleTrackIndex: Int?
    @Published public var isPlaying: Bool = false
    @Published public var isBuffering: Bool = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0

    public var currentPlayer: PlayerProtocol?

    private var cancellables = Set<AnyCancellable>()
    
    // Singleton initializer
    private init() {}
    
    // Set the player type (AVPlayer or VLCPlayer)
    public func setPlayer(type: PlayerType) {
        switch type {
        case .vlcPlayer:
            currentPlayer = VLCPlayerWrapper()
        case .avPlayer:
            currentPlayer = AVPlayerWrapper() // Assume AVPlayerWrapper exists similarly
        }
        
        refreshTrackInfo()
        observePlayerState()
    }

    // Load a media URL and refresh track information
    public func load(url: URL) {
        currentPlayer?.load(url: url)
        refreshTrackInfo()
    }
    
    // Play the media
    public func play() {
        currentPlayer?.play()
        DispatchQueue.main.async {
            self.isPlaying = true
        }
    }

    // Pause the media
    public func pause() {
        currentPlayer?.pause()
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }

    // Seek to a specific time in the media
    public func seek(to time: Double) {
        currentPlayer?.seek(to: time)
        DispatchQueue.main.async {
            self.currentTime = time
        }
    }

    // Refresh available audio and subtitle tracks
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

    // Select an audio track by index
    public func selectAudioTrack(index: Int) {
        currentPlayer?.selectAudioTrack(index: index)
        DispatchQueue.main.async {
            self.selectedAudioTrackIndex = index
            print("Selected audio track index: \(index)")
        }
    }

    // Select a subtitle track by index
    public func selectSubtitle(index: Int) {
        currentPlayer?.selectSubtitle(index: index)
        DispatchQueue.main.async {
            self.selectedSubtitleTrackIndex = index
            print("Selected subtitle index: \(index)")
        }
    }

    // Observe player state such as buffering, play/pause state, current time, and duration
    private func observePlayerState() {
        Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let player = self.currentPlayer else { return }
                
                self.isPlaying = player.isPlaying
                self.isBuffering = player.isBuffering
                self.currentTime = player.currentTime
                self.duration = player.duration
            }
            .store(in: &cancellables)
    }

    // Update available audio and subtitle tracks
    public func updateTrackInfo(audioTracks: [String], subtitles: [String]) {
        DispatchQueue.main.async {
            self.availableAudioTracks = audioTracks
            self.availableSubtitles = subtitles
        }
    }
}

