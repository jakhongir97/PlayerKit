import Foundation

protocol PlayerMuteControlling: AnyObject {
    func setMuted(_ muted: Bool)
}

protocol PlayerPreciseSeeking: AnyObject {
    func seekExactly(to time: Double, completion: ((Bool) -> Void)?)
}

protocol PlayerSeekWindowReporting: AnyObject {
    func canSeekWithinCurrentWindow(to time: Double, tolerance: Double) -> Bool
}
