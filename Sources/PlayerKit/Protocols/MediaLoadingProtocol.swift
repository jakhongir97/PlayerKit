//
//  MediaLoadingProtocol.swift
//  
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

@MainActor
public protocol MediaLoadingProtocol: AnyObject {
    func load(url: URL, lastPosition: Double?)
}
