//
//  GestureHandlingProtocol.swift
//
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import Foundation

@MainActor
public protocol GestureHandlingProtocol: AnyObject {
    /// Whether changing fit/fill can affect the current drawable right now.
    ///
    /// This is intentionally dynamic: an iOS backend may support video gravity
    /// in landscape while declining the same gesture in portrait.
    var isZoomSupported: Bool { get }

    func handlePinchGesture(scale: CGFloat)
    func setGravityToDefault()
    func setGravityToFill()
}

public extension GestureHandlingProtocol {
    /// Custom backends opt in explicitly. Advertising an unavailable gesture is
    /// worse than omitting it, so the compatibility default is conservative.
    var isZoomSupported: Bool { false }
}
