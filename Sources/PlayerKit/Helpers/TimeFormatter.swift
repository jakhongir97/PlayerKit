import Foundation

class TimeFormatter {
    static let shared = TimeFormatter()

    // Format time in seconds to MM:SS format
    func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

