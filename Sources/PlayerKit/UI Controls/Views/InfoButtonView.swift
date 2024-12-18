import SwiftUI

struct InfoButtonView: View {
    @State private var showPopover = false
    @State private var isLandscape = false

    var body: some View {
        Button(action: {
            withAnimation(.spring()) {
                showPopover.toggle()
            }
        }) {
            Image(systemName: "info.circle")
                .hierarchicalSymbolRendering()
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .padding(5)
                .contentShape(Rectangle())
        }
        // Overlay StreamingInfoView with a slide-in/slide-out transition
        .overlay(
            Group {
                if showPopover {
                    StreamingInfoView()
                        .frame(width: 250)
                        .offset(x: isLandscape ? 40 : 0, y: isLandscape ? 0 : -110)
                        .transition(.opacity)
                        .zIndex(1)
                }
            },
            alignment: .leading
        )
        .onAppear {
            // Check initial orientation
            updateOrientation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Update orientation on change
            updateOrientation()
        }
    }

    private func updateOrientation() {
        let orientation = UIDevice.current.orientation
        isLandscape = orientation.isValidInterfaceOrientation ? orientation.isLandscape : UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }
}

