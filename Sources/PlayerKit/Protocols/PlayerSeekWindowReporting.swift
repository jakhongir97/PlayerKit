import Foundation

protocol PlayerSeekWindowReporting: AnyObject {
    func canSeekWithinCurrentWindow(to time: Double, tolerance: Double) -> Bool

    /// The range the backend can currently seek within.
    ///
    /// For VOD this tracks `duration`; for live/DVR HLS — where `duration` is
    /// indefinite and therefore reported as 0 — this is the only source of a
    /// usable timeline, and without it seeking is rejected outright.
    var seekableTimeWindow: ClosedRange<Double>? { get }
}
