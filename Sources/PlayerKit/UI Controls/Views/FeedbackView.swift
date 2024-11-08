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
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
            Text(text)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
        }
        .padding()
        .cornerRadius(10)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            startFeedbackAnimation()
        }
        .onChange(of: text) { _ in // Reset animation on new feedback
            resetFeedbackAnimation()
        }
    }

    private func startFeedbackAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1.2
        }
        withAnimation(.easeInOut(duration: 0.5).delay(0.2)) {
            scale = 1.0
        }
        fadeOutFeedback()
    }

    private func resetFeedbackAnimation() {
        opacity = 1.0 // Reset opacity
        startFeedbackAnimation()
    }

    private func fadeOutFeedback() {
        // Start fading out after a delay, allowing multiple taps to keep feedback visible
        withAnimation(.easeIn(duration: 0.5).delay(1.0)) {
            opacity = 0.0
        }
    }
}

