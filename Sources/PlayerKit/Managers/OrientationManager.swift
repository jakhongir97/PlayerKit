import SwiftUI
import Combine

class OrientationManager: ObservableObject {
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation
    var onPortraitOrientation: (() -> Void)?

    private var cancellable: AnyCancellable?

    init() {
        cancellable = NotificationCenter.default
            .publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in
                self?.orientation = UIDevice.current.orientation
                if UIDevice.current.orientation == .portrait || UIDevice.current.orientation == .portraitUpsideDown || UIDevice.current.isPortrait {
                    self?.onPortraitOrientation?()
                }
            }
    }
}
