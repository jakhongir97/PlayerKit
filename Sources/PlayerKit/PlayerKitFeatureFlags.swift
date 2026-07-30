import Foundation

/// Compile-time switches for optional PlayerKit subsystems.
enum PlayerKitFeatureFlags {
    /// Master switch for the Dubber live-dubbing integration.
    ///
    /// **Currently disabled.** While this is `false`:
    ///
    /// - no Dubber affordance is constructed in the player chrome (no button,
    ///   no status card, no floating pill);
    /// - `configureDubber(_:)` does not arm the feature, so `isDubberEnabled`
    ///   never becomes `true`;
    /// - `startDubbedPlayback(language:translateFrom:)` returns without
    ///   contacting the network, so no session is created and no polling or
    ///   SSE task is ever started;
    /// - the remaining public dub API (`setDubLanguage(code:)`,
    ///   `setDubSourceLanguage(code:)`,
    ///   `stopDubbingAndReturnToOriginalAudio()`) is an inert no-op.
    ///
    /// The implementation is intentionally left in place rather than deleted,
    /// so re-enabling is a one-line change here. Nothing else needs to move.
    ///
    /// Note that the no-ops are silent: calling the dub API while disabled does
    /// not set `lastError` or post `PlayerKitDidFail`, because a host that
    /// still calls `configureDubber` has not done anything wrong — the feature
    /// is simply switched off in this build.
    static let isDubberEnabled = false
}
