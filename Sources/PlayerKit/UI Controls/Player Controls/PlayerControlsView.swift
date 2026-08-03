import SwiftUI

@MainActor
struct PlayerControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    #if os(iOS)
    @ObservedObject var thumbnailPreviewController: WebVTTThumbnailPreviewController
    #endif

    static let sideControlExtent: CGFloat = 50
    static let middleSpacing: CGFloat = 8

    /// The chrome is on screen and not suppressed by the lock.
    private var showsChrome: Bool {
        playerManager.areControlsVisible && !playerManager.isLocked
    }

    /// The scrubber outlives the chrome: it stays up while a skip session or a
    /// drag is moving the playhead, so the user can see where they are going.
    private var showsScrubber: Bool {
        (playerManager.isDoubleTapSeeking || playerManager.isSeeking || playerManager.areControlsVisible)
            && !playerManager.isLocked
    }

    var body: some View {
        GeometryReader { proxy in
            let padding = Self.contentPadding(for: proxy.size.width)
            let contentWidth = max(proxy.size.width - (padding * 2), 0)
            let transportWidth = Self.transportWidth(for: proxy.size.width)
            let separatesSideControls = Self.separatesSideControls(for: proxy.size.width)

            ZStack {
                Color.black.opacity(0.62)
                    .edgesIgnoringSafeArea(.all)
                    .allowsHitTesting(false)
                    .opacity(playerManager.areControlsVisible ? 1 : 0)

                VStack {
                    TopControlsView(playerManager: playerManager)
                        .presented(showsChrome)

                    Spacer(minLength: 8)

                    if separatesSideControls {
                        VStack(spacing: 8) {
                            MiddleControlsView(
                                playerManager: playerManager,
                                availableWidth: contentWidth
                            )
                            .presented(showsChrome)

                            sideControls
                        }
                    } else {
                        HStack(spacing: 0) {
                            InfoButtonView(playerManager: playerManager)
                                .presented(showsChrome)
                            Spacer(minLength: 0)

                            MiddleControlsView(
                                playerManager: playerManager,
                                availableWidth: transportWidth
                            )
                            .padding(.horizontal, Self.middleSpacing)
                            .presented(showsChrome)
                            Spacer(minLength: 0)

                            unlockControl
                        }
                    }

                    Spacer(minLength: 8)

                    VStack {
                        BottomControlsView(playerManager: playerManager)
                            .presented(showsChrome)
                        playbackSlider
                            .presented(showsScrubber)
                    }
                }
                .padding(padding)
            }
        }
    }

    private var sideControls: some View {
        HStack {
            InfoButtonView(playerManager: playerManager)
                .presented(showsChrome)
            Spacer(minLength: 0)
            unlockControl
        }
    }

    @ViewBuilder
    private var playbackSlider: some View {
        #if os(iOS)
        PlaybackSliderView(
            playerManager: playerManager,
            thumbnailPreviewController: thumbnailPreviewController
        )
        #else
        PlaybackSliderView(playerManager: playerManager)
        #endif
    }

    /// The one control that survives the lock — it is how the user gets back
    /// out. Keeping it in one helper avoids the compact and regular layouts
    /// drifting apart.
    private var unlockControl: some View {
        LockButtonView(playerManager: playerManager)
            .presented(playerManager.areControlsVisible)
    }

    static func contentPadding(for width: CGFloat) -> CGFloat {
        min(max(width * 0.04, 12), 32)
    }

    static func transportWidth(for totalWidth: CGFloat) -> CGFloat {
        let contentWidth = max(totalWidth - (contentPadding(for: totalWidth) * 2), 0)
        let sideControlsWidth = (sideControlExtent * 2) + (middleSpacing * 2)
        return max(contentWidth - sideControlsWidth, 0)
    }

    static func separatesSideControls(for totalWidth: CGFloat) -> Bool {
        transportWidth(for: totalWidth) < MiddleControlsView.compactTransportMinimumWidth
    }

    static func effectiveTransportWidth(for totalWidth: CGFloat) -> CGFloat {
        if separatesSideControls(for: totalWidth) {
            return max(totalWidth - (contentPadding(for: totalWidth) * 2), 0)
        }
        return transportWidth(for: totalWidth)
    }
}

private extension View {
    /// Hides a control **completely**: invisible, untappable, and absent from
    /// accessibility.
    ///
    /// These three used to be set independently, and the lock set only opacity.
    /// A locked player therefore still had a fully live — merely invisible —
    /// play/pause button, close button and scrubber sitting under the finger,
    /// and VoiceOver read every one of them out. The lock was decoration; this
    /// makes it mean something.
    @ViewBuilder
    func presented(_ isPresented: Bool) -> some View {
        self
            .opacity(isPresented ? 1 : 0)
            .allowsHitTesting(isPresented)
            .accessibilityHidden(!isPresented)
    }
}
