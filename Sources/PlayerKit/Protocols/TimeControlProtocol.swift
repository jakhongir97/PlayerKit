//
//  TimeControlProtocol.swift
//  
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

@MainActor
public protocol TimeControlProtocol: AnyObject {
    var currentTime: Double { get }
    var duration: Double { get }
    var bufferedDuration: Double { get }
    var isBuffering: Bool { get }
    
    /// Updated seek method with optional completion handler
    func seek(to time: Double, completion: (@MainActor (Bool) -> Void)?)
    
    func scrubForward(by seconds: TimeInterval)
    func scrubBackward(by seconds: TimeInterval)
}
