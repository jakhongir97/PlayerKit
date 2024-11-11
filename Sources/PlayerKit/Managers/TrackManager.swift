//
//  TrackManager.swift
//  
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

class TrackManager {
    private var player: PlayerProtocol

    init(player: PlayerProtocol) {
        self.player = player
    }

    var availableAudioTracks: [String] { player.availableAudioTracks }
    var availableSubtitles: [String] { player.availableSubtitles }
    var availableVideoTracks: [String] { player.availableVideoTracks }
    
    var currentAudioTrack: String? { player.currentAudioTrack }
    var currentSubtitleTrack: String? { player.currentSubtitleTrack }
    var currentVideoTrack: String? { player.currentVideoTrack }

    func selectAudioTrack(index: Int) {
        player.selectAudioTrack(index: index)
    }

    func selectSubtitle(index: Int?) {
        player.selectSubtitle(index: index)
    }

    func selectVideoTrack(index: Int) {
        player.selectVideoTrack(index: index)
    }

    func setPlayer(_ player: PlayerProtocol) {
        self.player = player
    }
}
