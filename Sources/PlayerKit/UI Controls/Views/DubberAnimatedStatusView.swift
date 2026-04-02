import SwiftUI

struct DubberAnimatedStatusView: View {
    private enum Metrics {
        static let fontSize: CGFloat = 15
        static let pulseSize: CGFloat = 8.5
        static let dotWidth: CGFloat = 20
    }

    let text: String
    let accentColor: Color
    let isActive: Bool

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                    statusRow(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                statusRow(at: 0)
            }
        }
    }

    private func statusRow(at time: TimeInterval) -> some View {
        HStack(spacing: 8) {
            leadingPulse(at: time)
            animatedText(at: time)
        }
    }

    private func leadingPulse(at time: TimeInterval) -> some View {
        let pulse = isActive ? (sin(time * 3.1) + 1) * 0.5 : 0
        let scale = 0.74 + (pulse * 0.26)
        let glow = 0.14 + (pulse * 0.24)

        return Circle()
            .fill(accentColor.opacity(isActive ? 0.94 : 0.64))
            .frame(width: Metrics.pulseSize, height: Metrics.pulseSize)
            .scaleEffect(scale)
            .shadow(color: accentColor.opacity(glow), radius: 10, x: 0, y: 0)
    }

    private func animatedText(at time: TimeInterval) -> some View {
        let baseText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let renderedText = baseText.isEmpty ? "Translating" : baseText
        let dotCount = isActive ? Int((time * 2.2).truncatingRemainder(dividingBy: 4)) : 0

        return HStack(spacing: 0) {
            shimmerText(renderedText, at: time)

            Text(String(repeating: ".", count: dotCount))
                .font(.system(size: Metrics.fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: Metrics.dotWidth, alignment: .leading)
                .monospacedDigitsCompat()
        }
    }

    private func shimmerText(_ value: String, at time: TimeInterval) -> some View {
        DubberShimmerTextView(
            value: value,
            accentColor: accentColor,
            isActive: isActive,
            time: time,
            fontSize: Metrics.fontSize
        )
    }
}
