//
//  PlaybackManager.swift
//
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

class PlaybackManager {
    private var player: PlayerProtocol

    init(player: PlayerProtocol) {
        self.player = player
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
}
