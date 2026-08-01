import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerManager: PlayerManager

    private var isIPhone: Bool {
        PlayerKitPlatform.isPhone
    }

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
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
                .allowsHitTesting(false)
                .opacity(playerManager.areControlsVisible ? 1 : 0)

            VStack {
                TopControlsView(playerManager: playerManager)
                    .presented(showsChrome)

                Spacer()

                HStack {
                    InfoButtonView(playerManager: playerManager)
                        .presented(showsChrome)
                    Spacer()

                    MiddleControlsView(playerManager: playerManager)
                        .presented(showsChrome)
                    Spacer()

                    // The one control that survives the lock — it is how the
                    // user gets back out.
                    LockButtonView(playerManager: playerManager)
                        .presented(playerManager.areControlsVisible)
                }

                Spacer()

                VStack {
                    BottomControlsView(playerManager: playerManager)
                        .presented(showsChrome)
                    PlaybackSliderView(playerManager: playerManager)
                        .presented(showsScrubber)
                }
            }
            .padding(isIPhone ? 16 : 32)
        }
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
