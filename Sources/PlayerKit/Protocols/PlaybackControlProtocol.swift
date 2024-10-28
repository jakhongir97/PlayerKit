//
//  PlaybackControlProtocol.swift
//
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

public protocol PlaybackControlProtocol: AnyObject {
    var isPlaying: Bool { get }
    var playbackSpeed: Float { get set }
    
    func play()
    func pause()
    func stop()
}
