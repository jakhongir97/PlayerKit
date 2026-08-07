import SwiftUI

@MainActor
struct PlayerControlsView: View {
    @ObservedObject var playerManager: PlayerManager
    #if os(iOS)
    @ObservedObject var thumbnailPreviewController: WebVTTThumbnailPreviewController
    #endif
    let presentationPolicy: PlayerPresentationPolicy

    /// The chrome is on screen and not suppressed by the lock.
    private var showsChrome: Bool {
        playerManager.areControlsVisible && !playerManager.isLocked
    }

    /// The scrubber outlives the chrome: it stays up while a skip session or a
    /// drag is moving the playhead, so the user can see where they are going.
    var showsScrubber: Bool {
        (playerManager.isDoubleTapSeeking || playerManager.isSeeking || playerManager.areControlsVisible)
            && !playerManager.isLocked
            && playerManager.playerItem?.timelineMode != .pureLive
    }

    var body: some View {
        GeometryReader { proxy in
            let padding = Self.contentPadding(for: proxy.size.width)
            let contentWidth = max(proxy.size.width - (padding * 2), 0)

            ZStack {
                scrim

                VStack(spacing: 0) {
                    // Presented on visibility alone: the row gates its own
                    // children on `showsChrome` and deliberately keeps the lock
                    // alive past it, since the lock is the way back out.
                    TopControlsView(playerManager: playerManager)
                        .presented(playerManager.areControlsVisible)

                    Spacer(minLength: PlayerChromeMetrics.spacingL)

                    // The transport gets the whole content width. It used to be
                    // handed `contentWidth - 104`, reserving room for the info
                    // and lock buttons that flanked it — but both moved into
                    // the top bar, so the reservation was paying rent for an
                    // empty room and stacked the episode row at widths where it
                    // fits comfortably.
                    MiddleControlsView(
                        playerManager: playerManager,
                        availableWidth: contentWidth
                    )
                    .presented(showsChrome)

                    Spacer(minLength: PlayerChromeMetrics.spacingL)

                    // Scrubber above the buttons, the way every streaming
                    // player puts it: the timeline is what the bottom row acts
                    // on, so it reads top-down as position-then-actions. It
                    // also stops the time readouts from being stranded in the
                    // window's bottom corners under everything else.
                    VStack(spacing: PlayerChromeMetrics.spacingS) {
                        playbackSlider
                            .presented(showsScrubber)

                        BottomControlsView(
                            playerManager: playerManager,
                            presentationPolicy: presentationPolicy,
                            availableWidth: contentWidth
                        )
                        .presented(showsChrome)
                    }
                }
                .padding(padding)
            }
        }
    }

    /// Top-and-bottom gradient rather than one flat wash.
    ///
    /// The chrome used to sit under a full-screen `black.opacity(0.62)`, which
    /// dimmed the *whole picture* by 62% every time the controls appeared —
    /// including the middle of the frame, where there are no controls to make
    /// legible. It also defeats the point of glass: a translucent surface over
    /// a uniformly darkened backdrop has nothing left to refract. Weighting the
    /// scrim to the edges keeps the same contrast behind the bars and hands the
    /// picture back.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.68), location: 0),
                .init(color: .black.opacity(0.24), location: 0.22),
                .init(color: .black.opacity(0.12), location: 0.5),
                .init(color: .black.opacity(0.34), location: 0.76),
                .init(color: .black.opacity(0.78), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .edgesIgnoringSafeArea(.all)
        .allowsHitTesting(false)
        .opacity(playerManager.areControlsVisible ? 1 : 0)
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

    static func contentPadding(for width: CGFloat) -> CGFloat {
        PlayerChromeMetrics.contentInset(for: width)
    }

    /// The width the transport is laid out in.
    ///
    /// Now simply the content width. The `transportWidth` / `separatesSideControls`
    /// pair this replaces existed to keep the transport clear of the info and
    /// lock buttons that sat on its line; those moved into the top bar, and the
    /// subtraction they justified made the function non-monotonic across its
    /// own breakpoint — a 287pt surface reported 287 and a 288pt one reported
    /// 184.
    static func effectiveTransportWidth(for totalWidth: CGFloat) -> CGFloat {
        max(totalWidth - (contentPadding(for: totalWidth) * 2), 0)
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
