import SwiftUI

struct DubberShimmerTextView: View {
    let value: String
    let accentColor: Color
    let isActive: Bool
    let time: TimeInterval
    let fontSize: CGFloat

    private let animationDuration: TimeInterval = 1.7
    private let highlightWindow: Double = 0.24

    private var glyphs: [Character] {
        Array(value)
    }

    var body: some View {
        let highlightCenter = highlightCenter(at: time)

        HStack(spacing: 0) {
            ForEach(Array(glyphs.enumerated()), id: \.offset) { index, character in
                let strength = highlightStrength(for: character, index: index, center: highlightCenter)

                Text(String(character))
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(foregroundStyle(strength: strength))
                    .scaleEffect(1 + (strength * 0.045), anchor: .center)
                    .offset(
                        x: horizontalOffset(for: character, index: index, strength: strength),
                        y: verticalOffset(for: character, index: index, strength: strength)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func highlightCenter(at time: TimeInterval) -> Double {
        guard isActive else { return -highlightWindow }
        let progress = time.truncatingRemainder(dividingBy: animationDuration) / animationDuration
        return (progress * (1 + (highlightWindow * 2))) - highlightWindow
    }

    private func highlightStrength(for character: Character, index: Int, center: Double) -> Double {
        guard isActive, !isWhitespace(character) else { return 0 }

        let normalizedIndex = glyphs.count > 1
            ? Double(index) / Double(glyphs.count - 1)
            : 0.5
        let distance = abs(normalizedIndex - center)
        let rawStrength = max(0, 1 - (distance / highlightWindow))
        return rawStrength * rawStrength
    }

    private func foregroundStyle(strength: Double) -> LinearGradient {
        let baseOpacity = 0.18 + (strength * 0.54)
        let whiteOpacity = 0.9 + (strength * 0.1)

        return LinearGradient(
            colors: [
                accentColor.opacity(baseOpacity),
                .white.opacity(whiteOpacity),
            ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }

    private func verticalOffset(for character: Character, index: Int, strength: Double) -> CGFloat {
        guard strength > 0, !isWhitespace(character) else { return 0 }

        let seed = Double(index) * 0.73
        let wave = sin((time * 18.0) + seed)
        return CGFloat(wave * strength * 1.35)
    }

    private func horizontalOffset(for character: Character, index: Int, strength: Double) -> CGFloat {
        guard strength > 0, !isWhitespace(character) else { return 0 }

        let seed = Double(index) * 0.41
        let wave = cos((time * 12.0) + seed)
        return CGFloat(wave * strength * 0.45)
    }

    private func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(\.properties.isWhitespace)
    }
}
