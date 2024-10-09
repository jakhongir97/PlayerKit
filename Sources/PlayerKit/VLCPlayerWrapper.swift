import Foundation
import VLCKit
import UIKit

public class VLCPlayerWrapper: NSObject, PlayerProtocol {
    public var player: VLCMediaPlayer

    public override init() {
        self.player = VLCMediaPlayer()
        super.init()

        // Register for VLC state and time change notifications
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(mediaPlayerStateChanged(_:)),
                                               name: VLCMediaPlayer.stateChangedNotification,
                                               object: player)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(mediaPlayerTimeChanged(_:)),
                                               name: VLCMediaPlayer.timeChangedNotification,
                                               object: player)

        print("VLCPlayer initialized and notifications set up.")
    }

    deinit {
        // Remove observers when deallocating the instance
        NotificationCenter.default.removeObserver(self)
    }

    // Play a video from a given URL and render it on the provided view
    public func load(url: URL) {
        let media = VLCMedia(url: url)
        player.media = media
        player.play()
        print("VLCPlayer loaded media from URL: \(url.absoluteString)")
    }

    // Play the video
    public func play() {
        player.play()
        print("VLCPlayer is playing.")
    }

    // Pause the video playback
    public func pause() {
        player.pause()
        print("VLCPlayer is paused.")
    }

    // Stop the video
    public func stop() {
        player.stop()
        print("VLCPlayer is stopped.")
    }

    // Check if the player is currently playing
    public var isPlaying: Bool {
        return player.isPlaying
    }

    // Seek to a specific time in the video (in seconds)
    public var currentTime: Double {
        return Double(player.time.intValue) / 1000
    }

    // Get the total duration of the video (in seconds)
    public var duration: Double {
        guard let media = player.media else { return 0.0 }
        return Double(media.length.intValue) / 1000
    }

    // Get available embedded audio tracks
    public var availableAudioTracks: [String] {
        var audioTracks = [String]()
        guard let tracks = player.audioTracks as? [VLCMediaPlayer.Track] else {
            print("No audio tracks found.")
            return audioTracks
        }

        for track in tracks {
            audioTracks.append(track.trackName ?? "Unknown")
            print("Found audio track: \(track.trackName ?? "Unknown")")
        }
        return audioTracks
    }

    // Get available embedded subtitle tracks
    public var availableSubtitles: [String] {
        var subtitleTracks = [String]()
        guard let tracks = player.textTracks as? [VLCMediaPlayer.Track] else {
            print("No subtitle tracks found.")
            return subtitleTracks
        }

        for track in tracks {
            subtitleTracks.append(track.trackName ?? "Unknown")
            print("Found subtitle track: \(track.trackName ?? "Unknown")")
        }
        return subtitleTracks
    }

    // Switch to a specific audio track
    public func selectAudioTrack(index: Int) {
        guard index < player.audioTracks.count else {
            print("Audio track index \(index) out of range.")
            return
        }
        player.audioTracks[index].isSelected = true
        print("Selected audio track at index: \(index)")
    }

    // Switch to a specific subtitle track
    public func selectSubtitle(index: Int) {
        guard index < player.textTracks.count else {
            print("Subtitle track index \(index) out of range.")
            return
        }
        player.textTracks[index].isSelected = true
        print("Selected subtitle track at index: \(index)")
    }

    // Handle VLCMediaPlayerStateChangedNotification
    @objc func mediaPlayerStateChanged(_ notification: Notification) {
        if let player = notification.object as? VLCMediaPlayer {
            print("VLCPlayer state changed: \(player.state)")

            // Refresh track info when the player is playing or buffering
            if player.state == .playing || player.state == .buffering {
                print("VLCPlayer is playing or buffering. Refreshing track info.")
                refreshTrackInfo()
            }
        }
    }

    // Handle VLCMediaPlayerTimeChangedNotification
    @objc func mediaPlayerTimeChanged(_ notification: Notification) {
        if let player = notification.object as? VLCMediaPlayer {
            print("VLCPlayer time changed: \(player.time.intValue / 1000) seconds")
        }
    }

    // Refresh and log audio and subtitle track info
    private func refreshTrackInfo() {
        let audioTracks = availableAudioTracks
        let subtitleTracks = availableSubtitles
        print("Track info refreshed. Audio tracks: \(audioTracks), Subtitles: \(subtitleTracks)")
        
        // Ensure updates are published on the main thread
        DispatchQueue.main.async {
            // Update the relevant properties for SwiftUI
            // Example: If using a PlayerManager that holds this state
            PlayerManager.shared.updateTrackInfo(audioTracks: audioTracks, subtitles: subtitleTracks)
        }
    }

}

