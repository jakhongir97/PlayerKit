//
//  Extensions.swift
//  PlayerKitDemo
//
//  Created by Jakhongir Nematov on 08/10/24.
//

import UIKit

// Add a safe subscript for collections to avoid index out of range errors
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Double {
    func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = style
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: self) ?? ""
    }
}

extension BinaryFloatingPoint {
    func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = style
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: TimeInterval(self)) ?? "" //formatter.string(from: self) ?? ""
    }
}

extension UIImage {
    static func fromFramework(named name: String) -> UIImage? {
        return UIImage(named: name, in: .module, compatibleWith: nil)
    }
}

extension Notification.Name {
    public static let PlayerKitDidClose = Notification.Name("PlayerKitDidClose")
    public static let PlayerKitNextItem = Notification.Name("PlayerKitNextItem")
    public static let PlayerKitPrevItem = Notification.Name("PlayerKitPrevItem")
    public static let PlayerKitMediaReady = Notification.Name("PlayerKitMediaReady")
    public static let PlayerKitControlsHidden = Notification.Name("PlayerKitControlsHidden")
    public static let PlayerKitLocked = Notification.Name("PlayerKitLocked")
}
