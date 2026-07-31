import Foundation

/// A backend whose audio output can be silenced without changing volume.
///
/// Every backend implements this. It is a separate protocol rather than a
/// requirement on `PlayerProtocol` because `PlayerProtocol` is public and
/// conformable by a host's own backend — adding a requirement to it would be a
/// source break for anyone who has one.
protocol PlayerMuteControlling: AnyObject {
    func setMuted(_ muted: Bool)
}
