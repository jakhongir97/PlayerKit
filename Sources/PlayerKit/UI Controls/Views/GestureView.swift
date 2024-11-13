import SwiftUI

struct GestureView: View {
    @ObservedObject var gestureManager: GestureManager

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent layer to capture gestures
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture(in: geometry.size))
                    .gesture(pinchGesture)
                    .gesture(tapGesture(in: geometry.size))
                
                // Feedback View for visual feedback on gestures
                feedbackView(in: geometry.size)
            }
        }
    }
}

extension GestureView {
    
    // Drag gesture for vertical swipe (volume/brightness)
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                gestureManager.handleVerticalSwipe(at: value.location, translation: value.translation, in: size)
            }
            .onEnded { _ in
                gestureManager.resetInitialStates()
            }
    }
    
    // Pinch gesture for zoom
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onEnded { scale in
                gestureManager.handlePinch(scale: scale)
            }
    }

    // Tap gesture for seeking
    private func tapGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                gestureManager.handleTap(at: value.location, in: size)
            }
    }
    
    // Visual feedback for seeking, volume, brightness
    @ViewBuilder
    private func feedbackView(in size: CGSize) -> some View {
        if let feedbackID = gestureManager.feedbackID,
           let feedback = gestureManager.visualFeedback,
           let feedbackImage = gestureManager.feedbackImage {
            FeedbackView(image: feedbackImage, text: feedback)
                .id(feedbackID)
                .position(x: gestureManager.feedbackPosition(in: size),
                          y: size.height / 2)
                .transition(.opacity)
        }
    }
}

