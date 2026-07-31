import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import IOKit.pwr_mgt
#endif

@MainActor
final class PlaybackWakeLockCoordinator {
    static let shared = PlaybackWakeLockCoordinator()

    #if os(iOS)
    private var isHoldingIdleTimerOverride = false
    private var previousIdleTimerDisabled = false
    #elseif os(macOS)
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var isHoldingDisplaySleepAssertion = false
    #endif

    let ownership = SharedResourceOwnership()

    /// Whether the platform override is currently held. Platform-independent,
    /// unlike the two `#if`-guarded flags below, so the accounting is exact on
    /// every platform including the `#else` no-op branch.
    private(set) var isHoldingWakeLock = false

    /// How many times the wake lock has actually been dropped.
    private(set) var resourceReleaseCount = 0

    private init() {}

    /// Records whether `owner` needs the screen kept awake, and acquires or
    /// drops the process-wide override accordingly.
    ///
    /// The override is held while *any* owner wants it. This used to store a
    /// single boolean, so a second player pausing would let the screen sleep
    /// under a first player that was still playing.
    func setPlaybackActive(_ isActive: Bool, for owner: AnyObject) {
        if isActive {
            ownership.addOwner(owner)
            guard !isHoldingWakeLock else { return }
            isHoldingWakeLock = true
        } else {
            ownership.removeOwner(owner)
            // Drop it when nobody wants it, not merely when the caller was the
            // last registered owner — same reasoning as GameControllerManager.
            guard !ownership.isHeld else { return }
            guard isHoldingWakeLock else { return }
            isHoldingWakeLock = false
            resourceReleaseCount += 1
        }

        applyPlaybackActive(isActive)
    }

    private func applyPlaybackActive(_ isActive: Bool) {
        #if os(iOS)
        if isActive {
            guard !isHoldingIdleTimerOverride else { return }
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            isHoldingIdleTimerOverride = true
        } else {
            guard isHoldingIdleTimerOverride else { return }
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            isHoldingIdleTimerOverride = false
        }
        #elseif os(macOS)
        if isActive {
            guard !isHoldingDisplaySleepAssertion else { return }

            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "PlayerKit active playback" as CFString,
                &assertionID
            )

            guard result == kIOReturnSuccess else { return }
            displaySleepAssertionID = assertionID
            isHoldingDisplaySleepAssertion = true
        } else {
            guard isHoldingDisplaySleepAssertion else { return }
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
            isHoldingDisplaySleepAssertion = false
        }
        #else
        _ = isActive
        #endif
    }
}
