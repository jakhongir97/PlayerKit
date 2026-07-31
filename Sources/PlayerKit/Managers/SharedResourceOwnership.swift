import Foundation

/// Tracks which objects are currently holding a process-global resource, so it
/// is released only when the last of them lets go.
///
/// PlayerKit reaches outside its own object graph for the shared
/// `AVAudioSession`, the idle-timer/display-sleep override and the process-wide
/// `GCController` handlers. With a single player that is fine; with two it is
/// not — dismissing an inline trailer would deactivate the audio session out
/// from under the main player.
///
/// Ownership is tracked by identity rather than as a plain integer count on
/// purpose. Both of PlayerKit's acquisition sites are idempotent by design —
/// `configureIntegrationsIfNeeded()` runs again after a teardown, and
/// `tearDown()` is documented as safe to call repeatedly — so a counter would
/// drift upwards on a repeated acquire and go negative on a repeated release.
/// A set makes each operation idempotent *per owner*, which is the property the
/// call sites actually need.
///
/// Owners are held as `ObjectIdentifier`, so this never retains them and can
/// never form a cycle with the resource it guards.
final class SharedResourceOwnership {
    private var owners: Set<ObjectIdentifier> = []
    private let lock = NSLock()

    /// Registers `owner` as a holder.
    ///
    /// - Returns: `true` when this is the first holder and the caller should
    ///   therefore acquire the underlying resource. Registering an owner that
    ///   already holds the resource returns `false` and changes nothing.
    @discardableResult
    func addOwner(_ owner: AnyObject) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasUnheld = owners.isEmpty
        owners.insert(ObjectIdentifier(owner))
        return wasUnheld
    }

    /// Removes `owner` as a holder.
    ///
    /// - Returns: `true` when `owner` was the last remaining holder and the
    ///   caller should therefore release the underlying resource. Removing an
    ///   owner that does not hold the resource returns `false`, so a double
    ///   release cannot release it twice.
    @discardableResult
    func removeOwner(_ owner: AnyObject) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard owners.remove(ObjectIdentifier(owner)) != nil else { return false }
        return owners.isEmpty
    }

    /// Whether any object currently holds the resource.
    var isHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !owners.isEmpty
    }

    /// How many distinct objects currently hold the resource.
    var ownerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return owners.count
    }

    /// Drops every owner without reporting a release.
    ///
    /// Only for resetting state between tests; production code must balance
    /// its own acquisitions.
    func removeAllOwners() {
        lock.lock()
        defer { lock.unlock() }
        owners.removeAll()
    }
}
