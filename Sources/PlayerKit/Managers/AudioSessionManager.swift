import Foundation

#if os(iOS)
import AVFoundation

class AudioSessionManager: NSObject {
    static let shared = AudioSessionManager()
    var onPauseRequested: (() -> Void)?
    var onResumeRequested: (() -> Void)?

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
        } catch {
            print("AudioSessionManager: Failed to configure audio session: \(error)")
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

        switch type {
        case .began:
            onPauseRequested?()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    onResumeRequested?()
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        if reason == .oldDeviceUnavailable {
            onPauseRequested?()
        }
    }
}
#else
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    var onPauseRequested: (() -> Void)?
    var onResumeRequested: (() -> Void)?

    private init() {}

    // macOS uses default system audio handling.
    func configureAudioSession() {}
}
#endif
