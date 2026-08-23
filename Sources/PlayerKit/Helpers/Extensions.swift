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
import SwiftUI

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
        if let catalogImage = UIImage(named: name, in: .module, compatibleWith: nil) {
            return catalogImage
        }
        guard let url = rawSwiftPMAssetURL(named: name),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return image.withRenderingMode(.alwaysTemplate)
        #else
        if let catalogImage = Bundle.module.image(forResource: NSImage.Name(name)) {
            return catalogImage
        }
        guard let url = rawSwiftPMAssetURL(named: name),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
        #endif
    }

    /// `swift build` copies asset catalogs verbatim on macOS instead of
    /// compiling an Assets.car. Xcode builds take the fast catalog path above;
    /// this fallback keeps command-line SwiftPM consumers functional too.
    private static func rawSwiftPMAssetURL(named name: String) -> URL? {
        let directory = Bundle.module.bundleURL
            .appendingPathComponent("Assets.xcassets/Images", isDirectory: true)
            .appendingPathComponent("\(name).imageset", isDirectory: true)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return files.first { url in
            url.pathExtension.lowercased() == "png" && !url.deletingPathExtension().lastPathComponent.contains("@")
        }
    }
}

extension Image {
    /// The first SF Symbol of the two the running OS actually ships.
    ///
    /// `Image(systemName:)` with a name the OS does not know renders nothing
    /// and says nothing: the playback-speed trigger was `gauge.with.needle`,
    /// an SF Symbols 5 glyph, so on iOS 14–16 the options pill carried a blank
    /// 44pt slot where the control should be.
    static func systemSymbol(_ preferred: String, fallback: String) -> Image {
        #if canImport(UIKit)
        let exists = UIImage(systemName: preferred) != nil
        #else
        let exists = NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil
        #endif
        return Image(systemName: exists ? preferred : fallback)
    }

    static func fromFramework(named name: String, fallbackSystemName: String) -> Image {
        guard let image = PKImage.fromFramework(named: name) else {
            return Image(systemName: fallbackSystemName)
        }
        #if canImport(UIKit)
        return Image(uiImage: image)
        #else
        return Image(nsImage: image)
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
