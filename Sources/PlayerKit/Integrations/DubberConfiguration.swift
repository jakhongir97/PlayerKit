import Foundation

public struct DubberConfiguration: Equatable {
    public let baseURL: URL
    public let defaultLanguage: String
    public let defaultTranslateFrom: String

    public init(
        baseURL: URL = URL(string: "https://dubbing.uz/api/instant-dub")!,
        defaultLanguage: String = "uz",
        defaultTranslateFrom: String = "auto"
    ) {
        self.baseURL = baseURL
        self.defaultLanguage = defaultLanguage
        self.defaultTranslateFrom = defaultTranslateFrom
    }
}
