import SwiftUI
import Combine

@MainActor
class OrientationManager: ObservableObject {
    #if os(iOS)
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation
    #else
    @Published var orientation: Int = 0
    #endif
    var onPortraitOrientation: (() -> Void)?

    private var cancellable: AnyCancellable?

    init() {
        #if os(iOS)
        cancellable = NotificationCenter.default
            .publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let current = UIDevice.current.orientation
                    self.orientation = current
                    if current == .portrait || current == .portraitUpsideDown || current.isPortrait {
                        self.onPortraitOrientation?()
                    }
                }
            }
        #endif
    }
}
