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

    /// - Parameter baseURL: The Dubber service endpoint.
    ///
    ///   This is deliberately **required**. It previously defaulted to a live
    ///   third-party host, so any integrator following the README's quick-start
    ///   snippet silently shipped an app that POSTed the user's media URL —
    ///   typically a signed, entitlement-bearing CDN URL — to a service they
    ///   may never have evaluated. Choosing where playback data is sent has to
    ///   be an explicit decision by the host app.
    public init(
        baseURL: URL,
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
