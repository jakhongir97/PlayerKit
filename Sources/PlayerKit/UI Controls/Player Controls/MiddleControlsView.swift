import SwiftUI

@MainActor
struct MiddleControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    let availableWidth: CGFloat

    enum Arrangement: Equatable {
        case row
        case stacked
    }

    // Four 44pt secondary controls, the 64pt desktop play control, two outer
    // 16pt gaps and two inner 12pt gaps. Deriving the breakpoint from the
    // controls themselves keeps it valid in Slide Over and embedded players
    // without guessing a device type.
    static let episodeRowMinimumWidth: CGFloat = 296
    static let compactTransportMinimumWidth: CGFloat = 172

    init(playerManager: PlayerManager, availableWidth: CGFloat = .greatestFiniteMagnitude) {
        self.playerManager = playerManager
        self.availableWidth = availableWidth
    }

    static func arrangement(
        availableWidth: CGFloat,
        contentType: PlayerContentType
    ) -> Arrangement {
        guard contentType == .episode,
              availableWidth < episodeRowMinimumWidth else { return .row }
        return .stacked
    }

    private var arrangement: Arrangement {
        Self.arrangement(
            availableWidth: availableWidth,
            contentType: playerManager.contentType
        )
    }

    var body: some View {
        Group {
            switch arrangement {
            case .row:
                row
            case .stacked:
                VStack(spacing: 8) {
                    transport
                    episodeNavigation
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 16) {
            if playerManager.contentType == .episode {
                previousButton
            }
            transport
            if playerManager.contentType == .episode {
                nextButton
            }
        }
    }

    /// The visible counterpart to double-tap skip. It keeps seeking reachable
    /// for Switch Control, VoiceOver, Voice Control, and anyone who simply does
    /// not know the gesture.
    private var transport: some View {
        HStack(spacing: 12) {
            SkipButtonView(playerManager: playerManager, direction: .backward)
            PlayPauseButtonView(playerManager: playerManager)
            SkipButtonView(playerManager: playerManager, direction: .forward)
        }
    }

    private var episodeNavigation: some View {
        HStack(spacing: 16) {
            previousButton
            nextButton
        }
    }

    private var previousButton: some View {
        PrevButtonView(playerManager: playerManager)
            .frame(minWidth: 44, minHeight: 44)
    }

    private var nextButton: some View {
        NextButtonView(playerManager: playerManager)
            .frame(minWidth: 44, minHeight: 44)
    }
}
