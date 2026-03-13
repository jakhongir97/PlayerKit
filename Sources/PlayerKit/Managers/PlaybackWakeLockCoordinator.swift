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

    private init() {}

    func setPlaybackActive(_ isActive: Bool) {
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
