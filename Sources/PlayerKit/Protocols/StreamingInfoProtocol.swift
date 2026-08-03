//
//  StreamingInfoProtocol.swift
//  PlayerKit
//
//  Created by Jakhongir Nematov on 14/12/24.
//

import Foundation

@MainActor
public protocol StreamingInfoProtocol: AnyObject {
    func fetchStreamingInfo() -> StreamingInfo
    func fetchStreamingInfo(using strings: PlayerStrings) -> StreamingInfo
}

public extension StreamingInfoProtocol {
    func fetchStreamingInfo(using strings: PlayerStrings) -> StreamingInfo {
        fetchStreamingInfo()
    }
}
