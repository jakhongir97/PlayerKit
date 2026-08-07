import SwiftUI

@MainActor
struct MiddleControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    let availableWidth: CGFloat

    enum Arrangement: Equatable {
        case row
        case stacked
    }

    // Measured from the controls themselves rather than guessed from a device
    // class, so the breakpoints stay correct in Slide Over and in embedded
    // players: five controls at the shared diameters — two 48pt episode
    // buttons, two 48pt skips and the 60/64pt play control — plus the gaps
    // between them, and the same sum without the episode pair.
    static let episodeRowMinimumWidth: CGFloat =
        (PlayerChromeMetrics.secondaryControlDiameter * 4)
            + PlayerChromeMetrics.primaryControlDiameter
            + (PlayerChromeMetrics.spacingM * 4)
    static let compactTransportMinimumWidth: CGFloat =
        (PlayerChromeMetrics.secondaryControlDiameter * 2)
            + PlayerChromeMetrics.primaryControlDiameter
            + (PlayerChromeMetrics.spacingM * 2)

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

    /// The whole cluster is one glass group.
    ///
    /// Each control still carries its own disc, but declaring them inside a
    /// container lets the platform share one lensing pass across the row and
    /// blend neighbours as they scale under the cursor, instead of compositing
    /// five unrelated blobs that happen to be adjacent.
    var body: some View {
        PlayerGlassGroup(spacing: PlayerChromeMetrics.spacingM) {
            switch arrangement {
            case .row:
                row
            case .stacked:
                VStack(spacing: PlayerChromeMetrics.spacingM) {
                    transport
                    episodeNavigation
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: PlayerChromeMetrics.spacingM) {
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
        HStack(spacing: PlayerChromeMetrics.spacingM) {
            SkipButtonView(playerManager: playerManager, direction: .backward)
            PlayPauseButtonView(playerManager: playerManager)
            SkipButtonView(playerManager: playerManager, direction: .forward)
        }
    }

    private var episodeNavigation: some View {
        HStack(spacing: PlayerChromeMetrics.spacingM) {
            previousButton
            nextButton
        }
    }

    private var previousButton: some View {
        PrevButtonView(playerManager: playerManager)
    }

    private var nextButton: some View {
        NextButtonView(playerManager: playerManager)
    }
}
