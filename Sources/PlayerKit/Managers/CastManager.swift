import GoogleCast

class CastManager: NSObject, GCKLoggerDelegate {
    
    static let shared = CastManager()
    
    @Published var isCasting = false
    @Published var isCastingAvailable = false

    override init() {
        super.init()
        setupGoogleCast()
        addCastStateListener()
    }
    
    // MARK: - Google Cast Setup
    
    /// Sets up Google Cast options and logger delegate
    private func setupGoogleCast() {
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.startDiscoveryAfterFirstTapOnCastButton = false
        
        let launchOptions = GCKLaunchOptions()
        launchOptions.androidReceiverCompatible = true
        options.launchOptions = launchOptions
        
        GCKCastContext.setSharedInstanceWith(options)
        GCKLogger.sharedInstance().delegate = self
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
    }
    
    // MARK: - Chromecast State Management
    
    /// Start listening for changes in Chromecast availability
    func addCastStateListener() {
        NotificationCenter.default.addObserver(forName: .gckCastStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.isCastingAvailable = GCKCastContext.sharedInstance().castState != .noDevicesAvailable
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .gckCastStateDidChange, object: nil)
    }
    
    // MARK: - Media Playback Control on Chromecast
    
    /// Initiates playback of media on Chromecast
    func playMediaOnCast(url: URL) {
        guard let mediaClient = GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient else {
            return
        }
        
        let mediaInfoBuilder = GCKMediaInformationBuilder(contentURL: url)
        mediaInfoBuilder.streamType = .buffered
        mediaInfoBuilder.contentType = "application/x-mpegURL" // Adjust based on your content type

        let mediaInfo = mediaInfoBuilder.build()
        mediaClient.loadMedia(mediaInfo)
        isCasting = true
    }
    
    /// Pauses playback on Chromecast
    func pauseCast() {
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?.pause()
    }
    
    /// Stops playback on Chromecast
    func stopCast() {
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?.stop()
        isCasting = false
    }
    
    // MARK: - GCKLoggerDelegate
    
    /// Logs Google Cast SDK messages
    func logMessage(_ message: String, fromFunction function: String) {
        print("Google Cast Log - Function: \(function) Message: \(message)")
    }
}

