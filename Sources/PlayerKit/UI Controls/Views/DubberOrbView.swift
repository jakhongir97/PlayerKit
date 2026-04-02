import SwiftUI

struct DubberOrbView: View {
    let color: Color
    let phase: DubberVisualState

    @ViewBuilder
    var body: some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            SiriDubberOrb(color: color, phase: phase)
        } else {
            ZStack {
                switch phase {
                case .idle:
                    DubberIdleOrb(color: color)
                case .loading:
                    DubberLoadingOrb(color: color)
                case .settling:
                    DubberSettledOrb(color: color, emphasis: .medium)
                case .live:
                    DubberSettledOrb(color: color, emphasis: .strong)
                case .error:
                    DubberErrorOrb(color: color)
                }
            }
            .frame(width: 118, height: 118)
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct SiriDubberOrb: View {
    let color: Color
    let phase: DubberVisualState

    var body: some View {
        ZStack {
            if phase == .loading || phase == .settling {
                DubberLoopingMediaView(isPlaying: phase == .loading)
                    .saturation(0)
                    .opacity(phase == .loading ? 0.12 : 0.05)
                    .blur(radius: 16)
                    .clipShape(Circle())
                    .scaleEffect(1.08)
            }

            if phase == .idle {
                DubberIdleOrb(color: color)
            } else if phase == .live {
                DubberSettledOrb(color: color, emphasis: .strong)
            } else {
                TimelineView(.animation(minimumInterval: timelineInterval, paused: false)) { timeline in
                    orbLayer(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: 118, height: 118)
    }

    private var timelineInterval: TimeInterval {
        switch phase {
        case .loading:
            return 1.0 / 36.0
        case .settling:
            return 1.0 / 28.0
        case .error:
            return 1.0 / 24.0
        case .idle, .live:
            return 1.0 / 18.0
        }
    }

    private func orbLayer(time: TimeInterval) -> some View {
        let configuration = motionConfiguration

        return ZStack {
            ForEach(Array(configuration.blobs.enumerated()), id: \.offset) { index, blob in
                movingBlob(blob, index: index, time: time, configuration: configuration)
            }

            Circle()
                .stroke(color.opacity(configuration.ringOpacity), lineWidth: 1)
                .frame(width: configuration.ringSize, height: configuration.ringSize)

            coreOrb(color: configuration.coreColor)
                .scaleEffect(configuration.coreScale)

            if phase == .error {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white.opacity(0.92))
            }
        }
        .drawingGroup()
        .transition(.opacity)
    }

    private func movingBlob(
        _ blob: OrbBlob,
        index: Int,
        time: TimeInterval,
        configuration: OrbMotionConfiguration
    ) -> some View {
        let x = cos(time * configuration.speed + blob.phase) * blob.radiusX
        let y = sin(time * (configuration.speed * blob.yMultiplier) + blob.phase) * blob.radiusY
        let rotation = Angle.degrees(sin(time * 0.45 + Double(index)) * blob.rotationAmplitude)

        return blob.gradient
            .frame(width: blob.size.width, height: blob.size.height)
            .blur(radius: blob.blur)
            .rotationEffect(rotation)
            .offset(x: x, y: y)
            .blendMode(.plusLighter)
    }

    private var motionConfiguration: OrbMotionConfiguration {
        switch phase {
        case .loading:
            return OrbMotionConfiguration(
                speed: 1.15,
                coreColor: color,
                coreScale: 1.03,
                ringOpacity: 0.20,
                ringSize: 92,
                blobs: [
                    OrbBlob(
                        size: CGSize(width: 72, height: 88),
                        radiusX: 15,
                        radiusY: 9,
                        blur: 10,
                        phase: 0,
                        yMultiplier: 1.2,
                        rotationAmplitude: 20,
                        gradient: RadialGradient(
                            colors: [color.opacity(0.90), color.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 46
                        )
                    ),
                    OrbBlob(
                        size: CGSize(width: 62, height: 70),
                        radiusX: 11,
                        radiusY: 14,
                        blur: 12,
                        phase: 1.7,
                        yMultiplier: 0.86,
                        rotationAmplitude: 18,
                        gradient: RadialGradient(
                            colors: [.white.opacity(0.82), color.opacity(0.12), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 40
                        )
                    ),
                    OrbBlob(
                        size: CGSize(width: 68, height: 60),
                        radiusX: 12,
                        radiusY: 11,
                        blur: 13,
                        phase: 3.1,
                        yMultiplier: 1.05,
                        rotationAmplitude: 16,
                        gradient: RadialGradient(
                            colors: [color.opacity(0.55), .white.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 42
                        )
                    ),
                ]
            )
        case .settling:
            return OrbMotionConfiguration(
                speed: 0.58,
                coreColor: color.opacity(0.88),
                coreScale: 0.98,
                ringOpacity: 0.14,
                ringSize: 86,
                blobs: [
                    OrbBlob(
                        size: CGSize(width: 70, height: 78),
                        radiusX: 6,
                        radiusY: 4,
                        blur: 11,
                        phase: 0.2,
                        yMultiplier: 0.74,
                        rotationAmplitude: 8,
                        gradient: RadialGradient(
                            colors: [color.opacity(0.68), color.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 42
                        )
                    ),
                    OrbBlob(
                        size: CGSize(width: 58, height: 64),
                        radiusX: 5,
                        radiusY: 6,
                        blur: 12,
                        phase: 2.1,
                        yMultiplier: 0.62,
                        rotationAmplitude: 10,
                        gradient: RadialGradient(
                            colors: [.white.opacity(0.70), color.opacity(0.10), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 38
                        )
                    ),
                ]
            )
        case .error:
            return OrbMotionConfiguration(
                speed: 0.46,
                coreColor: color.opacity(0.90),
                coreScale: 0.96,
                ringOpacity: 0.20,
                ringSize: 88,
                blobs: [
                    OrbBlob(
                        size: CGSize(width: 70, height: 72),
                        radiusX: 5,
                        radiusY: 4,
                        blur: 11,
                        phase: 0,
                        yMultiplier: 0.9,
                        rotationAmplitude: 7,
                        gradient: RadialGradient(
                            colors: [color.opacity(0.74), color.opacity(0.20), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 42
                        )
                    ),
                ]
            )
        case .idle, .live:
            return OrbMotionConfiguration(
                speed: 0.01,
                coreColor: color,
                coreScale: 1,
                ringOpacity: 0,
                ringSize: 0,
                blobs: []
            )
        }
    }
}

private struct DubberLoadingOrb: View {
    let color: Color

    @State private var isBreathing = false
    @State private var isRotating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 122, height: 122)
                .blur(radius: 22)
                .scaleEffect(isBreathing ? 1.12 : 0.90)

            Circle()
                .stroke(color.opacity(0.18), lineWidth: 1)
                .frame(width: 104, height: 104)
                .scaleEffect(isBreathing ? 1.04 : 0.95)

            Circle()
                .trim(from: 0.08, to: 0.72)
                .stroke(
                    AngularGradient(
                        colors: [
                            color.opacity(0.02),
                            .white.opacity(0.88),
                            color.opacity(0.88),
                            color.opacity(0.08),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 92, height: 92)
                .rotationEffect(.degrees(isRotating ? 360 : 0))

            coreOrb(color: color)
                .scaleEffect(isBreathing ? 1.03 : 0.97)
        }
        .onAppear {
            isBreathing = true
            isRotating = true
        }
        .animation(.easeInOut(duration: 1.65).repeatForever(autoreverses: true), value: isBreathing)
        .animation(.linear(duration: 6.2).repeatForever(autoreverses: false), value: isRotating)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }
}

private struct DubberSettledOrb: View {
    enum Emphasis {
        case medium
        case strong
    }

    let color: Color
    let emphasis: Emphasis

    @State private var hasSettled = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(emphasis == .strong ? 0.18 : 0.12))
                .frame(width: emphasis == .strong ? 118 : 106, height: emphasis == .strong ? 118 : 106)
                .blur(radius: 18)
                .scaleEffect(hasSettled ? 1 : 0.86)
                .opacity(hasSettled ? 1 : 0.3)

            Circle()
                .stroke(color.opacity(0.16), lineWidth: 1)
                .frame(width: emphasis == .strong ? 96 : 88, height: emphasis == .strong ? 96 : 88)
                .scaleEffect(hasSettled ? 1 : 1.08)
                .opacity(hasSettled ? 0.92 : 0.12)

            coreOrb(color: color)
                .scaleEffect(hasSettled ? 1 : 0.8)
                .opacity(hasSettled ? 1 : 0.18)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                hasSettled = true
            }
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

private struct DubberErrorOrb: View {
    let color: Color

    @State private var highlight = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
                .frame(width: 110, height: 110)
                .blur(radius: 20)
                .scaleEffect(highlight ? 1.02 : 0.94)

            Circle()
                .stroke(color.opacity(0.26), lineWidth: 1)
                .frame(width: 94, height: 94)

            coreOrb(color: color)

            Image(systemName: "exclamationmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white.opacity(0.92))
        }
        .onAppear {
            highlight = true
        }
        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: highlight)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

private struct DubberIdleOrb: View {
    let color: Color

    var body: some View {
        coreOrb(color: color.opacity(0.75))
            .scaleEffect(0.74)
            .opacity(0.74)
            .transition(.opacity)
    }
}

private func coreOrb(color: Color) -> some View {
    ZStack {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.95),
                        color.opacity(0.84),
                        color.opacity(0.24),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 72, height: 72)
            .shadow(color: color.opacity(0.48), radius: 22, x: 0, y: 0)

        Circle()
            .fill(Color.white.opacity(0.26))
            .frame(width: 24, height: 24)
            .offset(x: 8, y: -8)
            .blur(radius: 0.8)
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct OrbBlob {
    let size: CGSize
    let radiusX: CGFloat
    let radiusY: CGFloat
    let blur: CGFloat
    let phase: Double
    let yMultiplier: Double
    let rotationAmplitude: Double
    let gradient: RadialGradient
}

@available(iOS 15.0, macOS 12.0, *)
private struct OrbMotionConfiguration {
    let speed: Double
    let coreColor: Color
    let coreScale: CGFloat
    let ringOpacity: Double
    let ringSize: CGFloat
    let blobs: [OrbBlob]
}
