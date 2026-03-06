import SwiftUI

struct DubberButton: View {
    @ObservedObject var playerManager: PlayerManager
    let title: String?

    init(playerManager: PlayerManager = .shared, title: String? = nil) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        self.title = title
    }

    var body: some View {
        Button(action: startDubbedPlayback) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .bold))
                    .hierarchicalSymbolRendering()

                Text(buttonTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: gradientColors.first?.opacity(0.24) ?? .clear, radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!playerManager.canStartDubbedPlayback)
        .opacity(playerManager.canStartDubbedPlayback ? 1 : 0.64)
        .accessibilityLabel(buttonTitle)
        .accessibilityHint("Creates a dubbed voice track for the current media")
        .accessibilityIdentifier("player.dub")
    }

    private var buttonTitle: String {
        title ?? (playerManager.hasDubberIssue ? "Retry Dubbing" : "Start Dubbing")
    }

    private var iconName: String {
        playerManager.hasDubberIssue ? "arrow.clockwise.circle.fill" : "waveform.circle.fill"
    }

    private var gradientColors: [Color] {
        if playerManager.hasDubberIssue {
            return [
                Color(red: 0.89, green: 0.32, blue: 0.39),
                Color(red: 0.99, green: 0.58, blue: 0.35),
            ]
        }

        return [
            Color(red: 0.16, green: 0.68, blue: 0.92),
            Color(red: 0.22, green: 0.92, blue: 0.72),
        ]
    }

    private func startDubbedPlayback() {
        playerManager.userInteracted()
        Task {
            await playerManager.startDubbedPlayback()
        }
    }
}
