import SwiftUI

struct BottomControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    private var isIPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private let pillInsets = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)

    var body: some View {
        HStack {
            MediaOptionsMenu()
            BufferingIndicatorView(playerManager: playerManager)
            Spacer()

            if #available(iOS 26.0, *) {
                // Groups glass shapes & renders them as one, avoiding flash/morphs
                GlassEffectContainer {
                    HStack {
                        PiPButton()
                        if isIPhone { RotateButtonView() }
                    }
                    .padding(pillInsets)
                    .contentShape(Capsule())
                    .glassEffect(.clear, in: .capsule)   // single capsule around the row
                }
                .transaction { $0.animation = nil }     // avoids one-frame flicker on Menu rehost
            } else if #available(iOS 15.0, *) {
                // Fallback for iOS 15–25: material-based "glass"
                HStack {
                    PiPButton()
                    if isIPhone { RotateButtonView() }
                }
                .padding(pillInsets)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
            } else {
                // Very old fallback
                HStack {
                    PiPButton()
                    if isIPhone { RotateButtonView() }
                }
                .padding(pillInsets)
                .background(Color.white.opacity(0.10))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
            }
        }
    }
}

