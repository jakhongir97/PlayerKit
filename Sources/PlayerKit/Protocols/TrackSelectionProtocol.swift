//
//  TrackSelectionProtocol.swift
//  
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

public protocol TrackSelectionProtocol: AnyObject {
    var availableAudioTracks: [TrackInfo] { get }
    var availableSubtitles: [TrackInfo] { get }

    var currentAudioTrack: TrackInfo? { get }
    var currentSubtitleTrack: TrackInfo? { get }

    func selectAudioTrack(withID id: String)
    func selectSubtitle(withID id: String?)
}

