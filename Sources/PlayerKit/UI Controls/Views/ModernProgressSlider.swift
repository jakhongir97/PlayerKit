import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ModernProgressSlider<T: BinaryFloatingPoint>: View {
    @Binding var value: T
    @Binding var bufferedValue: T
    let inRange: ClosedRange<T>
    let activeFillColor: Color
    let fillColor: Color
    let emptyColor: Color
    let bufferedColor: Color
    let height: CGFloat
    let onEditingChanged: (Bool) -> Void

    // private variables
    @State private var localRealProgress: T = 0
    @State private var progressDuration: T = 0
    @State private var isActive = false
    @State private var isHoveringTrack = false
    @State private var hoverLocationX: CGFloat?
    #if os(macOS)
    @State private var didPushCursor = false
    #endif

    init(
        value: Binding<T>,
        bufferedValue: Binding<T>,
        inRange: ClosedRange<T>,
        activeFillColor: Color,
        fillColor: Color,
        emptyColor: Color,
        bufferedColor: Color,
        height: CGFloat,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        self._value = value
        self._bufferedValue = bufferedValue
        self.inRange = inRange
        self.activeFillColor = activeFillColor
        self.fillColor = fillColor
        self.emptyColor = emptyColor
        self.bufferedColor = bufferedColor
        self.height = height
        self.onEditingChanged = onEditingChanged
    }

    private var displayedProgress: T {
        isActive ? localRealProgress : clampedProgress(getPrgPercentage(value))
    }

    private var displayedDuration: T {
        isActive ? progressDuration : value
    }

    private var displayedBufferedProgress: T {
        clampedProgress(getPrgPercentage(bufferedValue))
    }

    private var trackHeight: CGFloat {
        if PlayerKitPlatform.isDesktop {
            if isActive {
                return 11
            }
            return isHoveringTrack ? 9 : 7
        }
        return isActive ? 11 : 8
    }

    private var trackPaddingY: CGFloat {
        PlayerKitPlatform.isDesktop ? 8 : 6
    }

    private var contentHorizontalInset: CGFloat {
        PlayerKitPlatform.isDesktop ? trackPaddingY : 6
    }

    private var thumbDiameter: CGFloat {
        if PlayerKitPlatform.isDesktop {
            if isActive {
                return 16
            }
            return isHoveringTrack ? 12 : 0
        }
        return isActive ? 16 : 0
    }

    private var containerHeight: CGFloat {
        PlayerKitPlatform.isDesktop ? max(height, 34) : height
    }

    var body: some View {
        VStack(spacing: PlayerKitPlatform.isDesktop ? 4 : 6) {
            GeometryReader { bounds in
                interactiveTrack(boundsWidth: max(bounds.size.width, 1))
                    .frame(width: bounds.size.width, height: bounds.size.height, alignment: .center)
            }
            .frame(height: PlayerKitPlatform.isDesktop ? 26 : 28)

            HStack {
                if #available(iOS 15, *) {
                    Text(displayedDuration.asTimeString(style: .positional)).monospacedDigit()
                    Spacer(minLength: 0)
                    Text("-" + (inRange.upperBound - displayedDuration).asTimeString(style: .positional)).monospacedDigit()
                } else {
                    Text(displayedDuration.asTimeString(style: .positional))
                    Spacer(minLength: 0)
                    Text("-" + (inRange.upperBound - displayedDuration).asTimeString(style: .positional))
                }
            }
            .padding(.horizontal, contentHorizontalInset)
            .font(PlayerKitPlatform.isDesktop ? .system(size: 12, weight: .semibold, design: .rounded) : .system(.headline, design: .rounded))
            .foregroundColor((isActive || isHoveringTrack) ? fillColor : emptyColor)
        }
        .frame(height: containerHeight, alignment: .center)
        .onAppear {
            syncProgress(with: value)
        }
        .onChange(of: value) { _, newValue in
            if !isActive {
                syncProgress(with: newValue)
            }
        }
        .onDisappear {
            clearDesktopCursor()
        }
    }

    @ViewBuilder
    private func interactiveTrack(boundsWidth: CGFloat) -> some View {
        let trackWidth = max(boundsWidth - (contentHorizontalInset * 2), 1)
        let baseTrack = ZStack(alignment: .leading) {
            Capsule()
                .fill(emptyColor)

            Capsule()
                .fill(bufferedColor)
                .frame(width: max(trackWidth * CGFloat(displayedBufferedProgress), 0), alignment: .leading)

            Capsule()
                .fill(isActive ? activeFillColor : fillColor)
                .frame(width: max(trackWidth * CGFloat(displayedProgress), 0), alignment: .leading)

            if PlayerKitPlatform.isDesktop,
               let hoverLocationX,
               isHoveringTrack,
               !isActive {
                Circle()
                    .fill(activeFillColor.opacity(0.4))
                    .frame(width: 10, height: 10)
                    .position(x: clampedLocation(hoverLocationX, within: trackWidth), y: trackHeight / 2)
            }

            if thumbDiameter > 0 {
                Circle()
                    .fill(isActive ? activeFillColor : fillColor.opacity(0.98))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.15), lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(isActive ? 0.22 : 0.14), radius: isActive ? 8 : 4, x: 0, y: 1)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .position(x: thumbPositionX(boundsWidth: trackWidth), y: trackHeight / 2)
            }
        }
        .frame(width: trackWidth, height: trackHeight, alignment: .leading)
        .padding(.horizontal, contentHorizontalInset)
        .padding(.vertical, trackPaddingY)
        .contentShape(Rectangle())
        .compositingGroup()
        .modifier(GlassCapsuleBackground())
        .gesture(scrubGesture(boundsWidth: trackWidth, horizontalInset: contentHorizontalInset))
        .animation(animation, value: isActive)
        .animation(animation, value: isHoveringTrack)

        #if os(macOS)
        if #available(macOS 13.0, *) {
            baseTrack
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        isHoveringTrack = true
                        hoverLocationX = clampedLocation(location.x - contentHorizontalInset, within: trackWidth)
                    case .ended:
                        isHoveringTrack = false
                        hoverLocationX = nil
                    }
                }
                .onHover { hovering in
                    updateDesktopCursor(hovering: hovering)
                }
        } else {
            baseTrack
                .onHover { hovering in
                    isHoveringTrack = hovering
                    if !hovering {
                        hoverLocationX = nil
                    }
                    updateDesktopCursor(hovering: hovering)
                }
        }
        #else
        baseTrack
        #endif
    }

    private var animation: Animation {
        isActive
            ? .spring(response: 0.22, dampingFraction: 0.82)
            : .spring(response: 0.3, dampingFraction: 0.88)
    }

    private func getPrgPercentage(_ value: T) -> T {
        let range = inRange.upperBound - inRange.lowerBound
        guard range != 0 else { return 0 }
        let correctedStartValue = value - inRange.lowerBound
        return correctedStartValue / range
    }

    private func progressValue(for progress: T) -> T {
        (progress * (inRange.upperBound - inRange.lowerBound)) + inRange.lowerBound
    }

    private func progress(at locationX: CGFloat, within boundsWidth: CGFloat, horizontalInset: CGFloat) -> T {
        guard boundsWidth > 0 else { return 0 }
        let clampedX = clampedLocation(locationX - horizontalInset, within: boundsWidth)
        return clampedProgress(T(clampedX / boundsWidth))
    }

    private func clampedProgress(_ progress: T) -> T {
        max(min(progress, 1), 0)
    }

    private func clampedLocation(_ locationX: CGFloat, within boundsWidth: CGFloat) -> CGFloat {
        min(max(locationX, 0), boundsWidth)
    }

    private func syncProgress(with value: T) {
        localRealProgress = clampedProgress(getPrgPercentage(value))
        progressDuration = max(min(value, inRange.upperBound), inRange.lowerBound)
    }

    private func thumbPositionX(boundsWidth: CGFloat) -> CGFloat {
        clampedLocation(boundsWidth * CGFloat(displayedProgress), within: boundsWidth)
    }

    private func scrubGesture(boundsWidth: CGFloat, horizontalInset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { gesture in
                beginScrubbingIfNeeded()
                updateProgress(at: gesture.location.x, within: boundsWidth, horizontalInset: horizontalInset)
            }
            .onEnded { gesture in
                if !isActive {
                    beginScrubbingIfNeeded()
                }
                updateProgress(at: gesture.location.x, within: boundsWidth, horizontalInset: horizontalInset)
                isActive = false
                onEditingChanged(false)
            }
    }

    private func beginScrubbingIfNeeded() {
        guard !isActive else { return }
        isActive = true
        onEditingChanged(true)
    }

    private func updateProgress(at locationX: CGFloat, within boundsWidth: CGFloat, horizontalInset: CGFloat) {
        let progress = progress(at: locationX, within: boundsWidth, horizontalInset: horizontalInset)
        let nextValue = max(min(progressValue(for: progress), inRange.upperBound), inRange.lowerBound)
        localRealProgress = progress
        progressDuration = nextValue
        value = nextValue

        if PlayerKitPlatform.isDesktop {
            hoverLocationX = clampedLocation(locationX - horizontalInset, within: boundsWidth)
            isHoveringTrack = true
        }
    }

    #if os(macOS)
    private func updateDesktopCursor(hovering: Bool) {
        guard hovering != didPushCursor else { return }
        if hovering {
            NSCursor.pointingHand.push()
            didPushCursor = true
        } else {
            clearDesktopCursor()
        }
    }

    private func clearDesktopCursor() {
        guard didPushCursor else { return }
        NSCursor.pop()
        didPushCursor = false
    }
    #else
    private func clearDesktopCursor() {}
    #endif
}
