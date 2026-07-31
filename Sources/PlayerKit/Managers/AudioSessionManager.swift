import Foundation

#if os(iOS)
import AVFoundation

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
        ownership.addOwner(owner)
        do {
            let session = AVAudioSession.sharedInstance()

            // Configure iOS playback audio session.
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
            isSessionActive = true
        } catch {
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
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            PlayerKitLog.debug("AudioSessionManager", "Failed to deactivate audio session: \(error)")
        }
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

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        // AVAudioSession notifications are not guaranteed to arrive on the main
        // thread, and both callbacks drive @Published state on PlayerManager.
        dispatchToMain { [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                self.wasPlayingWhenInterrupted = self.isPlayingProvider?() ?? true
                self.onPauseRequested?()
            case .ended:
                guard self.wasPlayingWhenInterrupted else { return }
                self.wasPlayingWhenInterrupted = false
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
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

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        guard reason == .oldDeviceUnavailable else { return }
        // Headphones unplugged: pause rather than blasting through the speaker.
        dispatchToMain { [weak self] in
            self?.onPauseRequested?()
        }
    }

    private func dispatchToMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
#else
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
