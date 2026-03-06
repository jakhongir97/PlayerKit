import Foundation

public struct DubberConfiguration: Equatable {
    public let baseURL: URL
    public let defaultLanguage: String
    public let defaultTranslateFrom: String
    public let supportedLanguages: [DubberLanguageOption]
    public let supportedSourceLanguages: [DubberLanguageOption]
    public let eventStreamRequestTimeout: TimeInterval
    public let eventStreamReconnectDelay: TimeInterval
    public let eventStreamMaxReconnectAttempts: Int

    public init(
        baseURL: URL = URL(string: "https://dubbing.uz/api/instant-dub")!,
        defaultLanguage: String = "uz",
        defaultTranslateFrom: String = "auto",
        supportedLanguages: [DubberLanguageOption] = DubberConfiguration.defaultTargetLanguages,
        supportedSourceLanguages: [DubberLanguageOption] = DubberConfiguration.defaultSourceLanguages,
        eventStreamRequestTimeout: TimeInterval = 15 * 60,
        eventStreamReconnectDelay: TimeInterval = 1.5,
        eventStreamMaxReconnectAttempts: Int = 8
    ) {
        self.baseURL = baseURL
        self.defaultLanguage = defaultLanguage
        self.defaultTranslateFrom = defaultTranslateFrom
        self.supportedLanguages = supportedLanguages.isEmpty ? DubberConfiguration.defaultTargetLanguages : supportedLanguages
        self.supportedSourceLanguages = supportedSourceLanguages.isEmpty ? DubberConfiguration.defaultSourceLanguages : supportedSourceLanguages
        self.eventStreamRequestTimeout = eventStreamRequestTimeout
        self.eventStreamReconnectDelay = eventStreamReconnectDelay
        self.eventStreamMaxReconnectAttempts = eventStreamMaxReconnectAttempts
    }
}

extension DubberConfiguration {
    public static let defaultTargetLanguages: [DubberLanguageOption] = [
        DubberLanguageOption(code: "uz", name: "Uzbek"),
        DubberLanguageOption(code: "en", name: "English"),
        DubberLanguageOption(code: "ru", name: "Russian"),
        DubberLanguageOption(code: "tr", name: "Turkish"),
        DubberLanguageOption(code: "kk", name: "Kazakh"),
    ]

    public static let defaultSourceLanguages: [DubberLanguageOption] = [
        DubberLanguageOption(code: "auto", name: "Auto Detect"),
        DubberLanguageOption(code: "uz", name: "Uzbek"),
        DubberLanguageOption(code: "en", name: "English"),
        DubberLanguageOption(code: "ru", name: "Russian"),
        DubberLanguageOption(code: "tr", name: "Turkish"),
        DubberLanguageOption(code: "kk", name: "Kazakh"),
    ]
}
