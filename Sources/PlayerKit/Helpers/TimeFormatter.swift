import Foundation

/// Formats playback positions and durations for display.
///
/// Two things this type exists to get right, both of which the previous ad-hoc
/// `DateComponentsFormatter` usage in `Extensions.swift` got wrong:
///
/// 1. **Hours.** A formatter restricted to `[.minute, .second]` renders a 2h02m
///    film as `122:05`, not `2:02:05`. The unit set has to depend on the
///    magnitude of the value being formatted.
/// 2. **Allocation.** `DateComponentsFormatter` is expensive to create, and the
///    playback slider formats twice per timer tick. Formatters are cached per
///    (style, includesHours) pair instead of being rebuilt on every call.
enum PlayerKitTimeFormatter {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [CacheKey: DateComponentsFormatter] = [:]

    private struct CacheKey: Hashable {
        let style: Int
        let includesHours: Bool
    }

    /// Formats `seconds` as a playback timestamp.
    ///
    /// Non-finite and negative inputs collapse to zero rather than rendering
    /// `"nan"` or a negative timestamp in the UI.
    static func string(
        from seconds: Double,
        style: DateComponentsFormatter.UnitsStyle = .positional
    ) -> String {
        let sanitized = seconds.isFinite ? max(seconds, 0) : 0
        let includesHours = sanitized >= 3600
        let formatter = formatter(style: style, includesHours: includesHours)
        return formatter.string(from: sanitized) ?? (includesHours ? "0:00:00" : "00:00")
    }

    private static func formatter(
        style: DateComponentsFormatter.UnitsStyle,
        includesHours: Bool
    ) -> DateComponentsFormatter {
        let key = CacheKey(style: style.rawValue, includesHours: includesHours)

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[key] {
            return cached
        }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = style
        formatter.allowedUnits = includesHours ? [.hour, .minute, .second] : [.minute, .second]
        // Pad minutes/seconds so the label width stays stable while scrubbing,
        // but let the hour component render naturally ("2:02:05", not "02:02:05").
        formatter.zeroFormattingBehavior = includesHours ? [] : [.pad]
        cache[key] = formatter
        return formatter
    }
}

/// Retained for source compatibility with anything that referenced the old
/// shared instance. New code should call `PlayerKitTimeFormatter.string(from:style:)`.
final class TimeFormatter {
    static let shared = TimeFormatter()

    func formatTime(
        _ time: Double,
        unitsStyle: DateComponentsFormatter.UnitsStyle = .positional
    ) -> String {
        PlayerKitTimeFormatter.string(from: time, style: unitsStyle)
    }
}
