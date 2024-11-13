import SwiftUI

public struct CloseButtonView: View {
    @Environment(\.presentationMode) private var presentationMode // Environment variable for dismissing

    public init() {}

    public var body: some View {
        Button(action: {
            presentationMode.wrappedValue.dismiss() // Dismiss the view
        }) {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
        }
        .padding(.trailing)
    }
}

