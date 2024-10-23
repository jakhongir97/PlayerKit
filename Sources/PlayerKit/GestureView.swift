import SwiftUI

struct GestureView: View {
    @ObservedObject var gestureManager: GestureManager

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent layer to capture gestures
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                gestureManager.handleTap(at: value.location, in: geometry.size)
                            }
                    )

                // Visual feedback for seeking
                if let feedbackID = gestureManager.feedbackID,
                   let feedback = gestureManager.visualFeedback,
                   let feedbackImage = gestureManager.feedbackImage {
                    FeedbackView(image: feedbackImage, text: feedback)
                        .id(feedbackID) // Use the feedbackID to trigger the view update
                        .position(x: gestureManager.feedbackPosition(in: geometry.size),
                                  y: geometry.size.height / 2)
                        .transition(.opacity)
                }
            }
        }
    }
}

