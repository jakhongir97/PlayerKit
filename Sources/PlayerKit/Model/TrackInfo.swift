//
//  TrackInfo.swift
//  PlayerKit
//
//  Created by Jakhongir Nematov on 05/12/24.
//

import Foundation

public struct TrackInfo {
    public let id: String
    public let name: String
    public let languageCode: String?

    public init(id: String, name: String, languageCode: String?) {
        self.id = id
        self.name = name
        self.languageCode = languageCode
    }
}
