#if os(macOS)
import SwiftUI

public struct OpenPlaybackDiagnosticsAction {
    public let isAvailable: Bool
    private let handler: @MainActor () -> Void

    public init(_ handler: @escaping @MainActor () -> Void) {
        isAvailable = true
        self.handler = handler
    }

    @MainActor
    public func callAsFunction() {
        handler()
    }

    fileprivate init() {
        isAvailable = false
        handler = {}
    }
}

private struct OpenPlaybackDiagnosticsActionKey: EnvironmentKey {
    static let defaultValue = OpenPlaybackDiagnosticsAction()
}

public extension EnvironmentValues {
    var openPlaybackDiagnostics: OpenPlaybackDiagnosticsAction {
        get { self[OpenPlaybackDiagnosticsActionKey.self] }
        set { self[OpenPlaybackDiagnosticsActionKey.self] = newValue }
    }
}
#endif
