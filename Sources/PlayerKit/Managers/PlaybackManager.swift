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
    
    func seek(to time: Double, completion: ((Bool) -> Void)? = nil) {
        player.seek(to: time, completion: completion)
    }

    func setPlayer(_ player: PlayerProtocol) {
        self.player = player
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        player.playbackSpeed = speed
    }
}
