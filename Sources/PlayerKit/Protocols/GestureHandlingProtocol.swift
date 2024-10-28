//
//  GestureHandlingProtocol.swift
//
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

public protocol GestureHandlingProtocol: AnyObject {
    func handlePinchGesture(scale: CGFloat)
}
