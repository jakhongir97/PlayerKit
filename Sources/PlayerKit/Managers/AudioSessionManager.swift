import Foundation

#if os(iOS)
import AVFoundation

@MainActor
class AudioSessionManager: NSObject {
    static let shared = AudioSessionManager()
    var onPauseRequested: (() -> Void)?
    var onResumeRequested: (() -> Void)?

    /// Lets the manager distinguish "the interruption paused us" from "the user
    /// had already paused". Without it, every ended interruption that carried
    /// `.shouldResume` resumed playback the user had deliberately stopped.
    var isPlayingProvider: (() -> Bool)?

    private(set) var isSessionActive = false
    private var wasPlayingWhenInterrupted = false
    private struct AudioSessionConfiguration {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }
    private var previousConfiguration: AudioSessionConfiguration?

    let ownership = SharedResourceOwnership()

    /// How many times the audio session has actually been handed back, i.e.
    /// how many times the last remaining owner let go. A second player
    /// releasing while a first still holds the session must not move this.
    private(set) var resourceReleaseCount = 0

    private override init() {
        super.init()
        setupNotifications()
    }

    /// Activates the shared audio session on behalf of `owner`.
    ///
    /// `AVAudioSession` is process-global, so the session stays active until
    /// every owner has released it — see `deactivateAudioSession(for:)`.
    func configureAudioSession(for owner: AnyObject) {
        guard ownership.addOwner(owner) else { return }
        let session = AVAudioSession.sharedInstance()
        let configurationToRestore = AudioSessionConfiguration(
            category: session.category,
            mode: session.mode,
            options: session.categoryOptions
        )
        previousConfiguration = configurationToRestore
        do {
            // Configure iOS playback audio session.
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
            isSessionActive = true
        } catch {
            ownership.removeOwner(owner)
            // `setCategory` may have succeeded before `setActive` failed. Roll
            // the process-global session back even on a partial acquisition;
            // otherwise PlayerKit changes the host's audio policy without ever
            // owning an active session that teardown could restore.
            do {
                try session.setCategory(
                    configurationToRestore.category,
                    mode: configurationToRestore.mode,
                    options: configurationToRestore.options
                )
            } catch {
                PlayerKitLog.debug(
                    "AudioSessionManager",
                    "Failed to restore audio category after activation failure: \(error)"
                )
            }
            previousConfiguration = nil
            PlayerKitLog.debug("AudioSessionManager", "Failed to configure audio session: \(error)")
        }
    }

    /// Releases `owner`'s claim on the shared audio session.
    ///
    /// The session is only handed back to the rest of the system once the last
    /// owner has released it. Deactivating unconditionally is correct for one
    /// player and wrong for two: dismissing an inline trailer would silence the
    /// main player and hand the session to whatever else was waiting for it.
    ///
    /// Before that, the session was activated on first playback and never
    /// deactivated at all, so other apps stayed interrupted for the remaining
    /// lifetime of the host process. `.notifyOthersOnDeactivation` is what lets
    /// a backgrounded music app resume rather than staying silently stopped.
    func deactivateAudioSession(for owner: AnyObject) {
        ownership.removeOwner(owner)
        guard !ownership.isHeld else { return }
        guard isSessionActive else { return }
        isSessionActive = false
        resourceReleaseCount += 1
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
            if let previousConfiguration {
                try session.setCategory(
                    previousConfiguration.category,
                    mode: previousConfiguration.mode,
                    options: previousConfiguration.options
                )
            }
        } catch {
            PlayerKitLog.debug("AudioSessionManager", "Failed to deactivate audio session: \(error)")
        }
        previousConfiguration = nil
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc nonisolated private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt

        // AVAudioSession notifications are not guaranteed to arrive on the main
        // thread, and both callbacks drive @Published state on PlayerManager.
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                self.wasPlayingWhenInterrupted = self.isPlayingProvider?() ?? true
                self.onPauseRequested?()
            case .ended:
                guard self.wasPlayingWhenInterrupted else { return }
                self.wasPlayingWhenInterrupted = false
                if let optionsValue {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self.onResumeRequested?()
                    }
                }
            @unknown default:
                break
            }
        }
    }

    @objc nonisolated private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        guard reason == .oldDeviceUnavailable else { return }
        // Headphones unplugged: pause rather than blasting through the speaker.
        Task { @MainActor [weak self] in
            self?.onPauseRequested?()
        }
    }
}
#else
@MainActor
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    var onPauseRequested: (() -> Void)?
    var onResumeRequested: (() -> Void)?
    var isPlayingProvider: (() -> Bool)?

    private(set) var isSessionActive = false

    let ownership = SharedResourceOwnership()

    /// See the iOS declaration. macOS performs no session work, but it tracks
    /// the same ownership transitions so the refcounting contract is identical
    /// — and observable — on both platforms.
    private(set) var resourceReleaseCount = 0

    private init() {}

    // macOS uses default system audio handling.
    func configureAudioSession(for owner: AnyObject) {
        ownership.addOwner(owner)
        isSessionActive = true
    }

    func deactivateAudioSession(for owner: AnyObject) {
        ownership.removeOwner(owner)
        guard !ownership.isHeld else { return }
        guard isSessionActive else { return }
        isSessionActive = false
        resourceReleaseCount += 1
    }
}
#endif
