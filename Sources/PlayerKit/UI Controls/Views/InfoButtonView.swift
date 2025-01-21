import SwiftUI

struct InfoButtonView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @State private var showPopover = false

    // Determine landscape orientation based on size classes.
    // On an iPhone:
    //  - Portrait: verticalSizeClass = .regular, horizontalSizeClass = .compact
    //  - Landscape: verticalSizeClass = .compact
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        Button(action: {
            withAnimation(.spring()) {
                showPopover.toggle()
            }
        }) {
            Image(systemName: "info.circle")
                .hierarchicalSymbolRendering()
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(.white)
                .padding(5)
                .contentShape(Rectangle())
        }
        .overlay(
            Group {
                if showPopover {
                    StreamingInfoView()
                        .frame(width: 250)
                        .offset(
                            x: isLandscape ? 40 : 0,
                            y: isLandscape ? 0 : -110
                        )
                        .transition(.opacity)
                        .zIndex(1)
                }
            },
            alignment: .leading
        )
    }
}
