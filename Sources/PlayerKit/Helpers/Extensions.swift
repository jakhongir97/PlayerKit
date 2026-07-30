//
//  Extensions.swift
//  PlayerKitDemo
//
//  Created by Jakhongir Nematov on 08/10/24.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Add a safe subscript for collections to avoid index out of range errors
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension BinaryFloatingPoint {
    /// Formats a number of seconds as a playback timestamp.
    ///
    /// Delegates to `PlayerKitTimeFormatter` so hour-long content renders as
    /// `2:02:05` rather than `122:05`, and so the underlying
    /// `DateComponentsFormatter` is not reallocated on every call.
    func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
        PlayerKitTimeFormatter.string(from: Double(self), style: style)
    }
}

extension PKImage {
    static func fromFramework(named name: String) -> PKImage? {
        #if canImport(UIKit)
        UIImage(named: name, in: .module, compatibleWith: nil)
        #else
        Bundle.module.image(forResource: NSImage.Name(name))
        #endif
    }
}

extension Notification.Name {
    public static let PlayerKitDidClose = Notification.Name("PlayerKitDidClose")
    public static let PlayerKitNextItem = Notification.Name("PlayerKitNextItem")
    public static let PlayerKitPrevItem = Notification.Name("PlayerKitPrevItem")
    public static let PlayerKitMediaReady = Notification.Name("PlayerKitMediaReady")
    public static let PlayerKitDidFail = Notification.Name("PlayerKitDidFail")
    public static let PlayerKitControlsHidden = Notification.Name("PlayerKitControlsHidden")
    public static let PlayerKitLocked = Notification.Name("PlayerKitLocked")
}

#if canImport(UIKit)
extension UIDevice {
    var interfaceOrientation: UIInterfaceOrientation? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation
    }

    var isPortrait: Bool {
        guard let orientation = interfaceOrientation else { return false }
        return orientation == .portrait || orientation == .portraitUpsideDown
    }

    var isLandscape: Bool {
        guard let orientation = interfaceOrientation else { return false }
        return orientation == .landscapeLeft || orientation == .landscapeRight
    }
}
#endif
