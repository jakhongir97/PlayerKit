//
//  PiPManager.swift
//
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import AVKit

class PiPManager {
    private var player: PlayerProtocol

    init(player: PlayerProtocol) {
        self.player = player
        setupPiP()
    }

    /// Sets up Picture-in-Picture for the player if available
    func setupPiP() {
        player.setupPiP()
    }

    /// Starts Picture-in-Picture mode
    func startPiP() {
        player.startPiP()
    }

    /// Stops Picture-in-Picture mode
    func stopPiP() {
        player.stopPiP()
    }

    /// Updates the player in case of player type switching
    func setPlayer(_ player: PlayerProtocol) {
        self.player = player
        setupPiP()
    }
}
