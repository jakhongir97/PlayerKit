import GoogleCast

class CastManager: NSObject, GCKLoggerDelegate {

    static let shared = CastManager()

    override init() {
        super.init()
        setupGoogleCast()
    }

    // Google Cast setup function
    func setupGoogleCast() {
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
    
    // GCKLoggerDelegate - Logs Google Cast SDK messages
    func logMessage(_ message: String, fromFunction function: String) {
        print("Google Cast Log - Function: \(function) Message: \(message)")
    }

    // Function to handle media playback on Chromecast
    func playMediaOnCast(url: URL) {
        guard let mediaClient = GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient else {
            return
        }

        let mediaInfoBuilder = GCKMediaInformationBuilder(contentURL: url)
        mediaInfoBuilder.streamType = .buffered
        mediaInfoBuilder.contentType = "application/x-mpegURL" // Adjust based on your content type

        let mediaInfo = mediaInfoBuilder.build()
        mediaClient.loadMedia(mediaInfo)
    }

    // Pause playback on Chromecast
    func pauseCast() {
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?.pause()
    }

    // Stop playback on Chromecast
    func stopCast() {
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?.stop()
    }
}

