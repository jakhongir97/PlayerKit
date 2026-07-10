import Foundation

/// Centralized, opt-in debug logging for PlayerKit.
///
/// Silent by default in **every** build configuration — PlayerKit no longer
/// prints diagnostics to the console during normal use. To re-enable console
/// output while developing PlayerKit, add the `PLAYERKIT_DEBUG_LOGGING`
/// compilation condition (e.g. via the package's `swiftSettings` or the
/// scheme's "Other Swift Flags: -D PLAYERKIT_DEBUG_LOGGING").
///
/// The message is passed as an `@autoclosure`, so when logging is disabled the
/// string is never built and any interpolation cost is avoided.
enum PlayerKitLog {
    @inline(__always)
    static func debug(
        _ category: String,
        _ message: @autoclosure () -> String
    ) {
        #if PLAYERKIT_DEBUG_LOGGING
        print("[PlayerKit][\(category)] \(message())")
        #endif
    }
}
