import SwiftUI

struct InfoButtonView: View {
    @State private var showInfoView = false

    var body: some View {
        Button(action: {
            showInfoView = true // Trigger the presentation of StreamingInfoView
        }) {
            Image(systemName: "info.circle")
                .hierarchicalSymbolRendering()
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .padding(5)
                .contentShape(Rectangle())
        }
        .sheet(isPresented: $showInfoView) {
            if #available(iOS 16.0, *) {
                StreamingInfoView()
                    .presentationDetents([.medium, .large]) // Half-height and full-height
                    .presentationDragIndicator(.visible)
            } else {
                StreamingInfoView()
            }
        }
    }
}

