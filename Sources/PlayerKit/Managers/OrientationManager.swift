import SwiftUI
import Combine

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
                self?.orientation = UIDevice.current.orientation
                if UIDevice.current.orientation == .portrait || UIDevice.current.orientation == .portraitUpsideDown || UIDevice.current.isPortrait {
                    self?.onPortraitOrientation?()
                }
            }
        #endif
    }
}
