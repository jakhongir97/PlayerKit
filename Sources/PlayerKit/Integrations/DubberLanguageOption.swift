import Foundation

public struct DubberLanguageOption: Equatable, Hashable, Identifiable {
    public let code: String
    public let name: String

    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}
