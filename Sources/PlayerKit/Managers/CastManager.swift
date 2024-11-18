import GoogleCast
import AVFoundation
import UIKit
import MobileCoreServices

class CastManager: NSObject {
    
    // MARK: - Singleton Instance
    static let shared = CastManager()
    
    // MARK: - Published Properties
    @Published var isCasting = false
    @Published var isCastingAvailable = false
    @Published var isConnectedToCastDevice = false
    
    // MARK: - Private Properties
    private var sessionManager: GCKSessionManager!
    
    // MARK: - Initializer
    private override init() {
        super.init()
        setupGoogleCast()
        addCastStateListener()
    }
    
    deinit {
        removeObservers()
        sessionManager?.remove(self)
    }
    
    // MARK: - Google Cast Setup
    private func setupGoogleCast() {
        configureGoogleCastOptions()
        sessionManager = GCKCastContext.sharedInstance().sessionManager
        sessionManager.add(self)
    }
    
    private func configureGoogleCastOptions() {
        let discoveryCriteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: discoveryCriteria)
        options.startDiscoveryAfterFirstTapOnCastButton = false
        options.launchOptions = createLaunchOptions()
        
        GCKCastContext.setSharedInstanceWith(options)
        GCKLogger.sharedInstance().delegate = self
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
    }
    
    private func createLaunchOptions() -> GCKLaunchOptions {
        let launchOptions = GCKLaunchOptions()
        launchOptions.androidReceiverCompatible = true
        return launchOptions
    }
    
    // MARK: - Cast State Management
    private func addCastStateListener() {
        NotificationCenter.default.addObserver(self, selector: #selector(castStateDidChange), name: .gckCastStateDidChange, object: nil)
    }
    
    @objc private func castStateDidChange() {
        isCastingAvailable = GCKCastContext.sharedInstance().castState != .noDevicesAvailable
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .gckCastStateDidChange, object: nil)
    }
    
    // MARK: - Media Playback
    func playMediaOnCast() {
        guard let remoteMediaClient = sessionManager.currentCastSession?.remoteMediaClient else {
            print("Error: No active cast session.")
            return
        }
        guard let playerItem = PlayerManager.shared.playerItem else { return }
        
        let mediaLoadRequest = createMediaLoadRequest(for: playerItem)
        let request = remoteMediaClient.loadMedia(with: mediaLoadRequest)
        request.delegate = self
        isCasting = true
        
        GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
        PlayerManager.shared.shouldDissmiss = true
    }
    
    private func createMediaLoadRequest(for playerItem: PlayerItem) -> GCKMediaLoadRequestData {
        let metadata = createMediaMetadata(for: playerItem)
        
        let mediaInfoBuilder = GCKMediaInformationBuilder()
        mediaInfoBuilder.contentURL = playerItem.castVideoUrl
        mediaInfoBuilder.streamType = .buffered
        mediaInfoBuilder.contentType = "video/mp4"
        mediaInfoBuilder.metadata = metadata
        
        let mediaLoadRequestDataBuilder = GCKMediaLoadRequestDataBuilder()
        mediaLoadRequestDataBuilder.mediaInformation = mediaInfoBuilder.build()
        mediaLoadRequestDataBuilder.autoplay = true
        mediaLoadRequestDataBuilder.startTime = playerItem.lastPosition ?? 0
        return mediaLoadRequestDataBuilder.build()
    }
    
    private func createMediaMetadata(for playerItem: PlayerItem) -> GCKMediaMetadata {
        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(playerItem.title, forKey: kGCKMetadataKeyTitle)
        if let description = playerItem.description {
            metadata.setString(description, forKey: kGCKMetadataKeySubtitle)
        }
        if let posterUrl = playerItem.posterUrl {
            metadata.addImage(GCKImage(url: posterUrl, width: 480, height: 360))
        }
        return metadata
    }
    
    func pauseCast() {
        sessionManager.currentCastSession?.remoteMediaClient?.pause()
    }
    
    func stopCast() {
        sessionManager.currentCastSession?.remoteMediaClient?.stop()
        isCasting = false
    }
}

// MARK: - GCKSessionManagerListener
extension CastManager: GCKSessionManagerListener {
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        print("Cast session started")
        session.remoteMediaClient?.add(self)
        isConnectedToCastDevice = true
        playMediaOnCast()
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKCastSession) {
        print("Cast session resumed")
        session.remoteMediaClient?.add(self)
        isConnectedToCastDevice = true
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKCastSession, withError error: Error?) {
        print("Cast session ended with error: \(String(describing: error))")
        session.remoteMediaClient?.remove(self)
        resetCastState()
        if let error = error {
            print("Session ended with error: \(error.localizedDescription)")
        }
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, didFailToStartSessionWithError error: Error?) {
        if let error = error {
            print("Failed to start session with error: \(error.localizedDescription)")
        }
    }
    
    private func resetCastState() {
        isConnectedToCastDevice = false
        isCasting = false
    }
}

// MARK: - GCKRemoteMediaClientListener
extension CastManager: GCKRemoteMediaClientListener {
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        print("Media status updated: \(String(describing: mediaStatus))")
    }
}

// MARK: - GCKRequestDelegate
extension CastManager: GCKRequestDelegate {
    func requestDidComplete(_ request: GCKRequest) {
        print("Cast request completed")
    }
    
    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        print("Cast request failed with error: \(error.localizedDescription)")
    }
}

// MARK: - GCKLoggerDelegate
extension CastManager: GCKLoggerDelegate {
    func logMessage(_ message: String, fromFunction function: String) {
        print("Google Cast Log - Function: \(function) Message: \(message)")
    }
}

