import SwiftUI

struct InfoButtonView: View {
    @State private var showPopover = false

    var body: some View {
        ZStack {
            // Main Button
            Button(action: {
                withAnimation {
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
            
            // Conditional Popover
            if showPopover {
                FloatingPopoverView {
                    StreamingInfoView()
                }
                .transition(.scale)
                .zIndex(1) // Ensure it appears above other content
            }
        }
        .onTapGesture {
            if showPopover {
                withAnimation {
                    showPopover = false // Dismiss popover when tapping outside
                }
            }
        }
    }
}

struct FloatingPopoverView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack {
            Spacer() // Push the content to the bottom or adjust positioning
            content
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                .shadow(radius: 10)
                .frame(maxWidth: 300) // Limit width
        }
        .padding()
    }
}

