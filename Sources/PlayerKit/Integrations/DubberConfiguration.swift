import Foundation

public struct DubberConfiguration: Equatable {
    public let baseURL: URL
    public let defaultLanguage: String
    public let defaultTranslateFrom: String
    public let eventStreamRequestTimeout: TimeInterval
    public let eventStreamReconnectDelay: TimeInterval
    public let eventStreamMaxReconnectAttempts: Int

    public init(
        baseURL: URL = URL(string: "https://dubbing.uz/api/instant-dub")!,
        defaultLanguage: String = "uz",
        defaultTranslateFrom: String = "auto",
        eventStreamRequestTimeout: TimeInterval = 15 * 60,
        eventStreamReconnectDelay: TimeInterval = 1.5,
        eventStreamMaxReconnectAttempts: Int = 8
    ) {
        self.baseURL = baseURL
        self.defaultLanguage = defaultLanguage
        self.defaultTranslateFrom = defaultTranslateFrom
        self.eventStreamRequestTimeout = eventStreamRequestTimeout
        self.eventStreamReconnectDelay = eventStreamReconnectDelay
        self.eventStreamMaxReconnectAttempts = eventStreamMaxReconnectAttempts
    }
}
