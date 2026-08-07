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
    let onEditingCancelled: () -> Void

    // private variables
    @State private var localRealProgress: T = 0
    @State private var progressDuration: T = 0
    @State private var isActive = false
    @State private var isHoveringTrack = false
    @State private var hoverLocationX: CGFloat?
    @GestureState private var scrubGestureIsActive = false
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
        onEditingChanged: @escaping (Bool) -> Void,
        onEditingCancelled: @escaping () -> Void = {}
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
        self.onEditingCancelled = onEditingCancelled
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
        if isActive {
            return 8
        }
        return isHoveringTrack ? 7 : 5
    }

    private var trackPaddingY: CGFloat {
        PlayerChromeMetrics.spacingS
    }

    private var contentHorizontalInset: CGFloat {
        PlayerChromeMetrics.spacingXS
    }

    private var thumbDiameter: CGFloat {
        if isActive {
            return 15
        }
        if PlayerKitPlatform.isDesktop {
            return isHoveringTrack ? 12 : 0
        }
        return 0
    }

    private var containerHeight: CGFloat {
        height
    }

    /// The band the track lives in: the thickest the track ever gets, plus the
    /// thumb's overhang on both sides, plus its padding. Derived rather than
    /// hardcoded so growing the thumb cannot silently clip it.
    private var trackZoneHeight: CGFloat {
        max(15, 8) + (trackPaddingY * 2)
    }

    var body: some View {
        VStack(spacing: PlayerChromeMetrics.spacingXS) {
            GeometryReader { bounds in
                interactiveTrack(boundsWidth: max(bounds.size.width, 1))
                    .frame(width: bounds.size.width, height: bounds.size.height, alignment: .center)
            }
            .frame(height: trackZoneHeight)

            HStack {
                Text(displayedDuration.asTimeString(style: .positional))
                    .monospacedDigitsCompat()
                Spacer(minLength: 0)
                Text("-" + (inRange.upperBound - displayedDuration).asTimeString(style: .positional))
                    .monospacedDigitsCompat()
            }
            .padding(.horizontal, contentHorizontalInset)
            // One timecode style on both platforms. iOS used `.headline`,
            // which is a body-text role roughly 17pt — larger than the player's
            // own title on a phone — for what is a secondary readout.
            .playerChromeFont(.timecode)
            .foregroundColor(.white.opacity((isActive || isHoveringTrack) ? 0.95 : 0.7))
        }
        .frame(height: containerHeight, alignment: .center)
        .onAppear {
            syncProgress(with: value)
        }
        .compatOnChange(of: value) { newValue in
            if !isActive {
                syncProgress(with: newValue)
            }
        }
        .compatOnChange(of: scrubGestureIsActive) { isGestureActive in
            if !isGestureActive {
                cancelScrubbingIfNeeded()
            }
        }
        .onDisappear {
            cancelScrubbingIfNeeded()
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
                let x = clampedLocation(hoverLocationX, within: trackWidth)
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2, height: trackHeight + 8)
                    .position(x: x, y: trackHeight / 2)
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
        // No tray. The track used to sit on a full-width glass capsule, which
        // is why the timeline read as a grey bar pinned across the bottom of
        // the window rather than as a scrubber: a 5pt line inside a 40pt
        // capsule makes the container the dominant shape. The bottom scrim
        // supplies the contrast the tray was standing in for.
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
            .updating($scrubGestureIsActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { gesture in
                beginScrubbingIfNeeded()
                updateProgress(at: gesture.location.x, within: boundsWidth, horizontalInset: horizontalInset)
            }
            .onEnded { gesture in
                if !isActive {
                    beginScrubbingIfNeeded()
                }
                updateProgress(at: gesture.location.x, within: boundsWidth, horizontalInset: horizontalInset)
                finishScrubbing()
            }
    }

    private func beginScrubbingIfNeeded() {
        guard !isActive else { return }
        isActive = true
        onEditingChanged(true)
    }

    private func finishScrubbing() {
        guard isActive else { return }
        isActive = false
        onEditingChanged(false)
    }

    private func cancelScrubbingIfNeeded() {
        guard isActive else { return }
        isActive = false
        syncProgress(with: value)
        onEditingCancelled()
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
