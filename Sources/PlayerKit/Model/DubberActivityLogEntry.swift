import Foundation

struct DubberActivityLogEntry: Identifiable, Equatable {
    enum Level: String {
        case info
        case success
        case warning
        case error
    }

    let id: UUID
    let timestamp: Date
    let message: String
    let level: Level

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        message: String,
        level: Level
    ) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.level = level
    }
}
