//
//  TimeControlProtocol.swift
//  
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

public protocol TimeControlProtocol: AnyObject {
    var currentTime: Double { get }
    var duration: Double { get }
    var bufferedDuration: Double { get }
    var isBuffering: Bool { get }
    
    /// Updated seek method with optional completion handler
    func seek(to time: Double, completion: ((Bool) -> Void)?)
}
