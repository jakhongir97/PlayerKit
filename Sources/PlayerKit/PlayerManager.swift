import Foundation
import Combine

public class PlayerManager: ObservableObject {
    public static let shared = PlayerManager()
    
    @Published public var availableAudioTracks: [String] = []
    @Published public var availableSubtitles: [String] = []
    @Published public var selectedAudioTrackIndex: Int?
    @Published public var selectedSubtitleTrackIndex: Int?
    @Published public var isPlaying: Bool = false
    
    public var currentPlayer: PlayerProtocol?
    
    private init() {}
    
    public func setPlayer(type: PlayerType) {
        switch type {
        case .vlcPlayer:
            currentPlayer = VLCPlayerWrapper()
        case .avPlayer:
            currentPlayer = AVPlayerWrapper()  // Assume AVPlayerWrapper exists similarly
        }
    }
    
    public func load(url: URL) {
        currentPlayer?.load(url: url)
        refreshTrackInfo()
    }
    
    public func play() {
        currentPlayer?.play()
        DispatchQueue.main.async {
            self.isPlaying = true
        }
    }
    
    public func pause() {
        currentPlayer?.pause()
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
    
    public func refreshTrackInfo() {
        guard let player = currentPlayer else {
            print("No current player available.")
            return
        }
        
        // Update audio and subtitle tracks on the main thread
        DispatchQueue.main.async {
            self.availableAudioTracks = player.availableAudioTracks
            self.availableSubtitles = player.availableSubtitles
            print("Track info refreshed. Audio tracks: \(self.availableAudioTracks), Subtitles: \(self.availableSubtitles)")
        }
    }
    
    public func selectAudioTrack(index: Int) {
        currentPlayer?.selectAudioTrack(index: index)
        DispatchQueue.main.async {
            self.selectedAudioTrackIndex = index
            print("Selected audio track index: \(index)")
        }
    }
    
    public func selectSubtitle(index: Int) {
        currentPlayer?.selectSubtitle(index: index)
        DispatchQueue.main.async {
            self.selectedSubtitleTrackIndex = index
            print("Selected subtitle index: \(index)")
        }
    }
    
    // Update track info (audio and subtitle tracks)
    public func updateTrackInfo(audioTracks: [String], subtitles: [String]) {
        DispatchQueue.main.async {
            self.availableAudioTracks = audioTracks
            self.availableSubtitles = subtitles
        }
    }
}

