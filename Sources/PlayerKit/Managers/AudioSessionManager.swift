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

    private var isSessionActive = false
    private var wasPlayingWhenInterrupted = false

    private override init() {
        super.init()
        setupNotifications()
    }

    func configureAudioSession() {
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

    /// Releases the shared audio session back to the rest of the system.
    ///
    /// Previously the session was activated on first playback and never
    /// deactivated, so other apps stayed interrupted for the remaining lifetime
    /// of the host process even after the player was dismissed.
    /// `.notifyOthersOnDeactivation` is what lets a backgrounded music app
    /// resume rather than staying silently stopped.
    func deactivateAudioSession() {
        guard isSessionActive else { return }
        isSessionActive = false
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

    private init() {}

    // macOS uses default system audio handling.
    func configureAudioSession() {}
    func deactivateAudioSession() {}
}
#endif
