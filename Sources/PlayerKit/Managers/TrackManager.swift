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

    var availableAudioTracks: [TrackInfo] { player.availableAudioTracks }
    var availableSubtitles: [TrackInfo] { player.availableSubtitles }

    var currentAudioTrack: TrackInfo? { player.currentAudioTrack }
    var currentSubtitleTrack: TrackInfo? { player.currentSubtitleTrack }

    func selectAudioTrack(withID id: String) {
        player.selectAudioTrack(withID: id)
    }

    func selectSubtitle(withID id: String?) {
        player.selectSubtitle(withID: id)
    }

    func setPlayer(_ player: PlayerProtocol) {
        self.player = player
    }
}
