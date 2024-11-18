//
//  TrackSelectionProtocol.swift
//  
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

public protocol TrackSelectionProtocol: AnyObject {
    var availableAudioTracks: [String] { get }
    var availableSubtitles: [String] { get }
    
    var currentAudioTrack: String? { get }
    var currentSubtitleTrack: String? { get }

    func selectAudioTrack(index: Int)
    func selectSubtitle(index: Int?)
}

