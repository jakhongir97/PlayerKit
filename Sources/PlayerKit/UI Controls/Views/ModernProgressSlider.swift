import SwiftUI
import UIKit

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
    @State private var localTempProgress: T = 0
    @GestureState private var isActive: Bool = false
    @State private var progressDuration: T = 0

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

    var body: some View {
        GeometryReader { bounds in
            ZStack {
                VStack {
                    // === BAR: wrap the existing ZStack in a capsule container and glass it ===
                    barZStack(boundsWidth: bounds.size.width)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Capsule())
                        .compositingGroup()                  // union inner layers before effect
                        .modifier(GlassCapsuleBackground())  // glass iOS26+, materials <26

                    // === TIME ROW (unchanged) ===
                    HStack {
                        if #available(iOS 15, *) {
                            Text(progressDuration.asTimeString(style: .positional)).monospacedDigit()
                            Spacer(minLength: 0)
                            Text("-" + (inRange.upperBound - progressDuration).asTimeString(style: .positional)).monospacedDigit()
                        } else {
                            Text(progressDuration.asTimeString(style: .positional))
                            Spacer(minLength: 0)
                            Text("-" + (inRange.upperBound - progressDuration).asTimeString(style: .positional))
                        }
                    }
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(isActive ? fillColor : emptyColor)
                }
                .frame(width: isActive ? bounds.size.width * 1.04 : bounds.size.width, alignment: .center)
                .animation(animation, value: isActive)
            }
            .frame(width: bounds.size.width, height: bounds.size.height, alignment: .center)
            // === Gestures & lifecycle (unchanged) ===
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($isActive) { _, state, _ in state = true }
                .onChanged { gesture in
                    localTempProgress = T(gesture.translation.width / bounds.size.width)
                    let prg = max(min((localRealProgress + localTempProgress), 1), 0)
                    progressDuration = inRange.upperBound * prg
                    value = max(min(getPrgValue(), inRange.upperBound), inRange.lowerBound)
                }
                .onEnded { _ in
                    localRealProgress = max(min(localRealProgress + localTempProgress, 1), 0)
                    localTempProgress = 0
                    progressDuration = inRange.upperBound * localRealProgress
                }
            )
            .onChange(of: isActive) { newValue in
                value = max(min(getPrgValue(), inRange.upperBound), inRange.lowerBound)
                onEditingChanged(newValue)
            }
            .onAppear {
                localRealProgress = getPrgPercentage(value)
                progressDuration = inRange.upperBound * localRealProgress
            }
            .onChange(of: value) { newValue in
                if !isActive {
                    localRealProgress = getPrgPercentage(newValue)
                    progressDuration = newValue
                }
            }
        }
        .frame(height: isActive ? height * 1.25 : height, alignment: .center)
    }

    // MARK: - Bar layers (unchanged logic, just moved into a builder)
    @ViewBuilder
    private func barZStack(boundsWidth: CGFloat) -> some View {
        ZStack(alignment: .center) {
            Capsule().fill(emptyColor)

            // Buffered progress
            if #available(iOS 15.0, *) {
                Capsule()
                    .fill(bufferedColor)
                    .mask(
                        HStack {
                            Rectangle()
                                .frame(width: max(boundsWidth * CGFloat(getPrgPercentage(bufferedValue)), 0), alignment: .leading)
                            Spacer(minLength: 0)
                        }
                    )
            }

            // Active progress
            if #available(iOS 15.0, *) {
                Capsule()
                    .fill(isActive ? activeFillColor : fillColor)
                    .mask(
                        HStack {
                            Rectangle()
                                .frame(width: max(boundsWidth * CGFloat((localRealProgress + localTempProgress)), 0), alignment: .leading)
                            Spacer(minLength: 0)
                        }
                    )
            } else {
                Capsule()
                    .fill(isActive ? activeFillColor : fillColor)
                    .mask(
                        HStack {
                            Rectangle()
                                .frame(width: max(boundsWidth * CGFloat((localRealProgress + localTempProgress)), 0), alignment: .leading)
                            Spacer(minLength: 0)
                        }
                    )
            }
        }
    }

    // MARK: - Helpers
    private var animation: Animation {
        isActive ? .spring() : .spring(response: 0.5, dampingFraction: 0.5, blendDuration: 0.6)
    }

    private func getPrgPercentage(_ value: T) -> T {
        let range = inRange.upperBound - inRange.lowerBound
        let correctedStartValue = value - inRange.lowerBound
        return correctedStartValue / range
    }

    private func getPrgValue() -> T {
        ((localRealProgress + localTempProgress) * (inRange.upperBound - inRange.lowerBound)) + inRange.lowerBound
    }
}

