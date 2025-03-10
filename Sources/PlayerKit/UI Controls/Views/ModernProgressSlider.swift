import SwiftUI

struct ModernProgressSlider<T: BinaryFloatingPoint>: View {
    @Binding var value: T
    @Binding var bufferedValue: T // New binding for buffered progress
    let inRange: ClosedRange<T>
    let activeFillColor: Color
    let fillColor: Color
    let emptyColor: Color
    let bufferedColor: Color // New color for buffered progress
    let height: CGFloat
    let onEditingChanged: (Bool) -> Void
    
    // private variables
    @State private var localRealProgress: T = 0
    @State private var localTempProgress: T = 0
    @GestureState private var isActive: Bool = false
    @State private var progressDuration: T = 0
    
    init(
        value: Binding<T>,
        bufferedValue: Binding<T>, // New buffered value binding
        inRange: ClosedRange<T>,
        activeFillColor: Color,
        fillColor: Color,
        emptyColor: Color,
        bufferedColor: Color, // New color
        height: CGFloat,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        self._value = value
        self._bufferedValue = bufferedValue // Assign new binding
        self.inRange = inRange
        self.activeFillColor = activeFillColor
        self.fillColor = fillColor
        self.emptyColor = emptyColor
        self.bufferedColor = bufferedColor // Assign new color
        self.height = height
        self.onEditingChanged = onEditingChanged
    }
    
    var body: some View {
        GeometryReader { bounds in
            ZStack {
                VStack {
                    ZStack(alignment: .center) {
                        Capsule()
                            .fill(emptyColor)
                        
                        // Buffered progress layer (NEW)
                        if #available(iOS 15.0, *) {
                            Capsule()
                                .fill(bufferedColor)
                                .mask({
                                    HStack {
                                        Rectangle()
                                            .frame(width: max(bounds.size.width * CGFloat(getPrgPercentage(bufferedValue)), 0), alignment: .leading)
                                        Spacer(minLength: 0)
                                    }
                                })
                        }
                        
                        if #available(iOS 15.0, *) {
                            Capsule()
                                .fill(isActive ? activeFillColor : fillColor)
                                .mask({
                                    HStack {
                                        Rectangle()
                                            .frame(width: max(bounds.size.width * CGFloat((localRealProgress + localTempProgress)), 0), alignment: .leading)
                                        Spacer(minLength: 0)
                                    }
                                })
                        } else {
                            Capsule()
                                    .fill(isActive ? activeFillColor : fillColor)
                                    .mask(
                                        HStack {
                                            Rectangle()
                                                .frame(width: max(bounds.size.width * CGFloat((localRealProgress + localTempProgress)), 0), alignment: .leading)
                                            Spacer(minLength: 0)
                                        }
                                    )
                        }
                    }
                    
                    HStack {
                        if #available(iOS 15, *) {
                            Text(progressDuration.asTimeString(style: .positional))
                                .monospacedDigit()
                            Spacer(minLength: 0)
                            Text("-" + (inRange.upperBound - progressDuration).asTimeString(style: .positional))
                                .monospacedDigit()
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
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($isActive) { value, state, transaction in
                    state = true
                }
                .onChanged { gesture in
                    localTempProgress = T(gesture.translation.width / bounds.size.width)
                    let prg = max(min((localRealProgress + localTempProgress), 1), 0)
                    progressDuration = inRange.upperBound * prg
                    value = max(min(getPrgValue(), inRange.upperBound), inRange.lowerBound)
                }
                .onEnded { value in
                    localRealProgress = max(min(localRealProgress + localTempProgress, 1), 0)
                    localTempProgress = 0
                    progressDuration = inRange.upperBound * localRealProgress
                })
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
    
    private var animation: Animation {
        if isActive {
            return .spring()
        } else {
            return .spring(response: 0.5, dampingFraction: 0.5, blendDuration: 0.6)
        }
    }
    
    private func getPrgPercentage(_ value: T) -> T {
        let range = inRange.upperBound - inRange.lowerBound
        let correctedStartValue = value - inRange.lowerBound
        let percentage = correctedStartValue / range
        return percentage
    }
    
    private func getPrgValue() -> T {
        return ((localRealProgress + localTempProgress) * (inRange.upperBound - inRange.lowerBound)) + inRange.lowerBound
    }
}

