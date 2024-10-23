import SwiftUI

struct FeedbackView: View {
    var image: Image
    var text: String
    
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        HStack(spacing: 10) {
            image
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.white)
            Text(text)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            animateFeedback()
        }
    }
    
    private func animateFeedback() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1.2
        }
        withAnimation(.easeInOut(duration: 0.5).delay(0.2)) {
            scale = 1.0
            opacity = 0.0
        }
    }
}

