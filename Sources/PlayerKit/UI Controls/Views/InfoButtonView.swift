import SwiftUI

struct InfoButtonView: View {
    @State private var showPopover = false

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
        // Overlay StreamingInfoView to the right with a slide-in/slide-out transition
        .overlay(
            Group {
                if showPopover {
                    StreamingInfoView()
                        .frame(width: 250)
                        .offset(x: 35)
                        .transition(.opacity)
                        .zIndex(1)
                }
            },
            alignment: .leading
        )
    }
}

