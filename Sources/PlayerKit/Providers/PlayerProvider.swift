//
//  PlayerProvider.swift
//
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

protocol PlayerProvider {
    func createPlayer() -> PlayerProtocol
}

class AVPlayerProvider: PlayerProvider {
    func createPlayer() -> PlayerProtocol {
        return AVPlayerWrapper()
    }
}

class VLCPlayerProvider: PlayerProvider {
    func createPlayer() -> PlayerProtocol {
        return VLCPlayerWrapper()
    }
}

class PlayerFactory {
    static func getProvider(for type: PlayerType) -> PlayerProvider {
        switch type {
        case .avPlayer:
            return AVPlayerProvider()
        case .vlcPlayer:
            return VLCPlayerProvider()
        }
    }
}
