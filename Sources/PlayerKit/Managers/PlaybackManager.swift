//
//  PlaybackManager.swift
//
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

class PlaybackManager {
    private var player: PlayerProtocol
    private weak var playerManager: PlayerManager?

    init(player: PlayerProtocol, playerManager: PlayerManager) {
        self.player = player
        self.playerManager = playerManager
    }

    func play() { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop() }
    
    // Updated seek method
    func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        playerManager?.isSeeking = true  // Mark that we are seeking
        playerManager?.isBuffering = true  // Show buffering during seeking

        player.seek(to: time) { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if success {
                    self.playerManager?.currentTime = time
                    self.playerManager?.isSeeking = false  // End seeking state
                    self.playerManager?.isBuffering = false  // Hide buffering after seeking completes
                } else {
                    self.playerManager?.isBuffering = false  // Hide buffering if seek fails
                }
                completion?(success)
            }
        }
    }

    func setPlayer(_ player: PlayerProtocol) {
        self.player = player
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        player.playbackSpeed = speed
    }
}
