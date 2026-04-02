import SwiftUI

struct DubberHeroView: View {
    let phase: DubberVisualState
    let accentColor: Color
    let title: String
    let badgeText: String
    let statusText: String?
    let headline: String
    let subheadline: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                heroChip(title, systemName: "waveform.badge.mic", fill: Color.white.opacity(0.08))
                heroChip(badgeText, systemName: nil, fill: accentColor.opacity(0.16))
            }

            Text(headline)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Text(subheadline)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let statusText, showsAnimatedStatus {
                DubberAnimatedStatusView(
                    text: statusText,
                    accentColor: accentColor,
                    isActive: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsAnimatedStatus: Bool {
        phase == .loading || phase == .settling
    }

    private func heroChip(_ text: String, systemName: String?, fill: Color = Color.white.opacity(0.08)) -> some View {
        HStack(spacing: 6) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.vertical, 4)
        .padding(.horizontal, 9)
        .background(
            Capsule(style: .continuous)
                .fill(fill)
        )
    }
}
