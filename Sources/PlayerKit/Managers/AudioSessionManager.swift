import AVFoundation

class AudioSessionManager: NSObject {
    static let shared = AudioSessionManager()
    
    private override init() {
        super.init()
        setupNotifications()
    }
    
    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Set the audio session category, mode, and options
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
            
            print("AudioSessionManager: Audio session configured successfully.")
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
            print("AudioSessionManager: Audio interruption began.")
            // Pause the player
            PlayerManager.shared.pause()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    print("AudioSessionManager: Audio interruption ended. Resuming playback.")
                    // Resume playback
                    PlayerManager.shared.play()
                }
            }
        @unknown default:
            print("AudioSessionManager: Unknown audio interruption.")
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        switch reason {
        case .oldDeviceUnavailable:
            print("AudioSessionManager: Audio output route changed. Pausing playback.")
            // Pause the player
            PlayerManager.shared.pause()
        default:
            break
        }
    }
}

