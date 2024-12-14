import SwiftUI

struct InfoButtonView: View {

    var body: some View {
        Button(action: infoAction) {
            Image(systemName: "info.circle")
                .hierarchicalSymbolRendering()
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .padding(5)
                .contentShape(Rectangle())
        }
    }
    
    private func infoAction() {
        
    }
}

