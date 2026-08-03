import SwiftUI

@MainActor
struct RotateButtonView: View {
    private let playerManager: PlayerManager
    #if canImport(UIKit)
    @State private var windowScene: UIWindowScene?
    #endif
    
    init(playerManager: PlayerManager = .shared) {
        self.playerManager = playerManager
    }

    var body: some View {
        Button(action: toggleOrientation) {
            Image(systemName: "rotate.right")
                .circularGlassIcon()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rotate player")
        .accessibilityHint("Toggles between portrait and landscape")
        .accessibilityIdentifier("player.rotate")
        #if canImport(UIKit)
        .background(WindowSceneReader(scene: $windowScene).frame(width: 0, height: 0))
        #endif
    }
    
    private func toggleOrientation() {
        #if canImport(UIKit)
        guard let windowScene else { return }
        if windowScene.interfaceOrientation.isLandscape {
            setDeviceOrientation(.portrait, in: windowScene)
            playerManager.setGravityToDefault()
        } else {
            setDeviceOrientation(.landscapeRight, in: windowScene)
        }
        #else
        playerManager.setGravityToDefault()
        #endif
    }
}

#if canImport(UIKit)
import UIKit

private struct WindowSceneReader: UIViewRepresentable {
    @Binding var scene: UIWindowScene?

    func makeUIView(context: Context) -> SceneReaderView {
        let view = SceneReaderView()
        view.onWindowChange = { scene = $0 }
        return view
    }

    func updateUIView(_ uiView: SceneReaderView, context: Context) {
        uiView.onWindowChange = { scene = $0 }
        let resolved = uiView.window?.windowScene
        guard scene !== resolved else { return }
        DispatchQueue.main.async { scene = resolved }
    }

    final class SceneReaderView: UIView {
        var onWindowChange: ((UIWindowScene?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(window?.windowScene)
        }
    }
}
#endif
