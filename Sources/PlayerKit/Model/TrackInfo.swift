//
//  TrackInfo.swift
//  PlayerKit
//
//  Created by Jakhongir Nematov on 05/12/24.
//

import Foundation

/// A selectable audio or subtitle track.
///
/// `Identifiable` and `Equatable` are what make the track lists on
/// `PlayerManager` usable from a host: without them a caller cannot write
/// `ForEach(playerManager.availableAudioTracks)` or compare a track against
/// `selectedAudio`. All three stored properties are strings, so every
/// conformance here is synthesised.
public struct TrackInfo: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let languageCode: String?

    public init(id: String, name: String, languageCode: String?) {
        self.id = id
        self.name = name
        self.languageCode = languageCode
    }
}
