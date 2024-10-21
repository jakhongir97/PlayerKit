import Foundation

class TimeFormatter {
    static let shared = TimeFormatter()

    /// Formats time in seconds into a readable format
    /// - Parameters:
    ///   - time: Time in seconds
    ///   - unitsStyle: Optional units style to specify the desired format (short, positional)
    /// - Returns: A formatted time string
    func formatTime(_ time: Double, unitsStyle: DateComponentsFormatter.UnitsStyle = .positional) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = unitsStyle
        formatter.allowedUnits = time >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        
        return formatter.string(from: time) ?? "00:00"
    }
}

