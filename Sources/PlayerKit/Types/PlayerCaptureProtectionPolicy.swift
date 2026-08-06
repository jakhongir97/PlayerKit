import Foundation

/// How PlayerKit protects rendered video from screen capture.
///
/// The two platforms can enforce very different things, and that difference is
/// the whole reason this policy exists.
///
/// * iOS can exclude an individual view from a capture. Content hosted inside a
///   secure-text canvas is composited for the display but not for a screenshot
///   or a recording, so the surrounding UI still captures normally. `UIScreen`
///   also reports `isCaptured` and posts `capturedDidChangeNotification`, so a
///   recording or mirroring session can be reacted to while it runs.
/// * macOS, **on the render path PlayerKit uses**, has neither. `AVPlayerLayer`
///   carries no capture-protection flag, which leaves `NSWindow.sharingType` as
///   the only control — and that is all-or-nothing for a whole window. Setting
///   it to `.none` therefore removes the app chrome around the video from every
///   capture too, and `screencapture -l <windowID>` on such a window does not
///   return a black image, it fails outright with "could not create image from
///   window". There is no general capture-detection API either:
///   `NSWindow.hasActiveWindowSharingSession` (macOS 13.3+) reports only an
///   active SharePlay window-sharing session, not a screenshot, a `screencapture`
///   run, or a third-party recorder.
///
/// ``blackOutVideo`` is the escape hatch for that. It stops trying to hide the
/// picture from the person at the keyboard and blanks the video surface
/// instead, which lets the window stay capturable: a screenshot then contains
/// the full player UI with only the picture blacked out.
///
/// - Note: There *is* a per-layer mechanism on macOS —
///   `AVSampleBufferDisplayLayer.preventsCapture` (macOS 10.15+) blanks just
///   that layer in a capture while the rest of the window composites normally,
///   which is how Chromium protects video. It cannot wrap an existing layer, so
///   reaching it means moving macOS rendering off `AVPlayerLayer` onto
///   `AVPlayerVideoOutput` (macOS 14.2+) feeding an
///   `AVSampleBufferDisplayLayer`. That would upgrade this policy from "black on
///   screen *and* in captures" to "visible on screen, black in captures", and is
///   deliberately left as a separate change to the playback path.
public enum PlayerCaptureProtectionPolicy: String, Sendable, CaseIterable {
    /// Protect the video as strongly as the platform allows.
    ///
    /// * iOS — the player view renders inside a secure-text canvas, and an
    ///   opaque shield covers it while `UIScreen.isCaptured` is true.
    /// * macOS — the hosting `NSWindow` is set to `.none`, which removes the
    ///   entire window, app chrome included, from every capture.
    case automatic

    /// Keep the window capturable and blank the video surface instead.
    ///
    /// The capture shield replaces the picture on screen as well as in the
    /// capture; audio, the transport timeline and every control keep running.
    /// This is the mode that makes "screenshot the player UI, but not the
    /// content" possible on macOS.
    case blackOutVideo

    /// No capture protection at all. The video is visible on screen and in
    /// captures, and the hosting window is never taken out of screen sharing.
    case allowCapture
}

extension PlayerCaptureProtectionPolicy {
    /// Read by ``resolvedDefault(defaults:environment:)``.
    ///
    /// `UserDefaults` resolves the argument domain first, so this key doubles as
    /// a launch argument: `itv.app --args -PlayerKitCaptureProtectionPolicy
    /// blackOutVideo` needs no persisted value.
    public static let userDefaultsKey = "PlayerKitCaptureProtectionPolicy"

    /// Read by ``resolvedDefault(defaults:environment:)`` when no default and no
    /// launch argument is set. Useful for `xcodebuild test` and for CI, which
    /// can set an environment variable but not a user default.
    public static let environmentKey = "PLAYERKIT_CAPTURE_PROTECTION_POLICY"

    /// The policy a freshly created ``PlayerManager`` starts with.
    ///
    /// Hosts that want to decide in code can simply assign
    /// ``PlayerManager/captureProtectionPolicy`` afterwards; this resolution
    /// exists so screenshot tooling and QA builds can select a policy from
    /// outside the app without a code change.
    public static func resolvedDefault(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        if let raw = defaults.string(forKey: userDefaultsKey),
           let policy = Self(lenient: raw) {
            return policy
        }

        if let raw = environment[environmentKey],
           let policy = Self(lenient: raw) {
            return policy
        }

        return .automatic
    }

    /// Accepts the case name plus the spellings a shell script or a person is
    /// likely to type, so a typo-tolerant flag does not silently fall back to
    /// full protection and look like the feature is broken.
    ///
    /// Public because hosts parse the same kinds of external input — a URL
    /// query item, a CLI flag — before handing a policy to
    /// ``PlayerManager/captureProtectionPolicy``.
    public init?(lenient raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        switch normalized {
        case "automatic", "auto", "default", "protect", "protectwindow":
            self = .automatic
        case "blackoutvideo", "blackout", "black", "capturesafe", "hidevideo":
            self = .blackOutVideo
        case "allowcapture", "allow", "off", "none", "disabled", "unprotected":
            self = .allowCapture
        default:
            return nil
        }
    }
}
