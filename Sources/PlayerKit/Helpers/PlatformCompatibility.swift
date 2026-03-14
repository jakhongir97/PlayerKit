import Foundation

#if canImport(UIKit)
import UIKit
public typealias PKView = UIView
public typealias PKImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PKView = NSView
public typealias PKImage = NSImage
#endif

enum PlayerKitPlatform {
    static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    static var isDesktop: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static var isPortraitInterface: Bool {
        #if os(iOS)
        UIDevice.current.isPortrait
        #else
        false
        #endif
    }
}
