//
//  StreamingInfoProtocol.swift
//  PlayerKit
//
//  Created by Jakhongir Nematov on 14/12/24.
//

import Foundation

public protocol StreamingInfoProtocol: AnyObject {
    func fetchStreamingInfo() -> StreamingInfo
}
