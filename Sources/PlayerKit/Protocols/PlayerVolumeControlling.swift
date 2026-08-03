import Foundation

/// A backend whose audio output level can be set.
///
/// A separate protocol rather than a requirement on `PlayerProtocol` because
/// `PlayerProtocol` is public and conformable by a host's own backend — adding a
/// requirement to it would be a source break for anyone who has one. Same
/// reasoning, and same shape, as `PlayerMuteControlling`.
@MainActor
public protocol PlayerVolumeControlling: AnyObject {
    /// 0…1. Unity is 1.0; PlayerKit does not amplify above it.
    var outputVolume: Float { get }
    func setOutputVolume(_ value: Float)
}
