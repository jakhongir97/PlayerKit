enum CastPendingRequestKind: Equatable {
    case mediaLoad
    case stop

    var cancelsWhenPlayerDetaches: Bool { self == .mediaLoad }
}

enum CastMediaStreamKind: Equatable {
    case buffered
    case live
}

struct CastMediaLoadPolicy: Equatable {
    let streamKind: CastMediaStreamKind
    let startTime: Double

    static func resolve(
        for playerItem: PlayerItem,
        currentPlaybackPosition: Double?
    ) -> Self {
        switch playerItem.timelineMode {
        case .seekableLive, .pureLive:
            return Self(streamKind: .live, startTime: 0)
        case .automatic, .onDemand:
            let requestedStartTime = currentPlaybackPosition
                ?? playerItem.lastPosition
                ?? 0
            return Self(
                streamKind: .buffered,
                startTime: requestedStartTime.isFinite
                    ? max(requestedStartTime, 0)
                    : 0
            )
        }
    }
}

#if canImport(GoogleCast) && canImport(UIKit)
@preconcurrency import GoogleCast
import AVFoundation
import Combine
import UIKit
import MobileCoreServices

@MainActor
class CastManager: NSObject, ObservableObject {

    // MARK: - Singleton Instance
    static let shared = CastManager()

    // MARK: - Published Properties
    @Published var isCasting = false
    @Published var isCastingAvailable = false
    @Published var isConnectedToCastDevice = false
    @Published private(set) var availableDevices: [ExternalPlaybackDevice] = []
    @Published private(set) var isSearchingForDevices = false
    @Published private(set) var activeDeviceID: String?
    
    // MARK: - Private Properties
    private var sessionManager: GCKSessionManager?
    private var isPrepared = false
    private var didInitializeCastContext = false
    private var pendingMediaLoadRequestID: GCKRequestID?
    private var pendingMediaLoadRequest: GCKRequest?
    private var pendingRequestKind: CastPendingRequestKind?
    private weak var observedRemoteMediaClient: GCKRemoteMediaClient?
    private var receiverApplicationID = kGCKDefaultMediaReceiverApplicationID
    var currentPlayerItemProvider: (() -> PlayerItem?)?
    var currentPlaybackPositionProvider: (() -> Double?)?
    var onError: ((PlayerKitError) -> Void)?
    var onDismissRequested: (() -> Void)?
    
    // MARK: - Initializer
    private override init() {
        super.init()
    }

    // MARK: - Google Cast Setup
    @discardableResult
    func configure(receiverApplicationID: String) -> Bool {
        guard Thread.isMainThread else { return false }
        let normalized = receiverApplicationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !isPrepared,
              !GCKCastContext.isSharedInstanceInitialized() else {
            return false
        }
        self.receiverApplicationID = normalized
        return true
    }

    /// Initializes Google Cast immediately before its official button is made.
    /// Discovery itself remains deferred until that button's first tap.
    /// Reuses a host-owned context rather than replacing process-global state.
    @discardableResult
    func prepareForUserInteraction() -> Bool {
        guard Thread.isMainThread else { return false }
        guard !isPrepared else { return true }

        if !GCKCastContext.isSharedInstanceInitialized() {
            let discoveryCriteria = GCKDiscoveryCriteria(applicationID: receiverApplicationID)
            let options = GCKCastOptions(discoveryCriteria: discoveryCriteria)
            options.startDiscoveryAfterFirstTapOnCastButton = true
            options.disableAnalyticsLogging = true
            options.launchOptions = createLaunchOptions()

            var setupError: GCKError?
            guard GCKCastContext.setSharedInstanceWith(options, error: &setupError) else {
                let code = (setupError as NSError?)?.code
                onError?(.externalPlaybackFailed(Self.failureMessage(
                    operation: "initialize Google Cast",
                    code: code
                )))
                return false
            }
            didInitializeCastContext = true
        }

        let context = GCKCastContext.sharedInstance()
        if didInitializeCastContext {
            context.useDefaultExpandedMediaControls = true
        }
        sessionManager = context.sessionManager
        sessionManager?.add(self)
        addCastStateListener()
        isPrepared = true
        if sessionManager?.currentCastSession != nil {
            handleSessionResumed()
        }
        return true
    }

    @discardableResult
    func presentCastDialog() -> Bool {
        guard prepareForUserInteraction() else { return false }
        let context = GCKCastContext.sharedInstance()
        // This path is explicitly requested by the host rather than triggered
        // by GCKUICastButton, so begin discovery ourselves.
        context.discoveryManager.startDiscovery()
        context.presentCastDialog()
        return true
    }

    private func createLaunchOptions() -> GCKLaunchOptions {
        let launchOptions = GCKLaunchOptions()
        launchOptions.androidReceiverCompatible = true
        return launchOptions
    }

    // MARK: - Cast State Management
    private func addCastStateListener() {
        NotificationCenter.default.addObserver(self, selector: #selector(castStateDidChange), name: .gckCastStateDidChange, object: nil)
        castStateDidChange()
    }

    @objc private func castStateDidChange() {
        isCastingAvailable = GCKCastContext.sharedInstance().castState != .noDevicesAvailable
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .gckCastStateDidChange, object: nil)
    }
    
    // MARK: - Media Playback
    func playMediaOnCast() {
        guard prepareForUserInteraction() else { return }
        guard let remoteMediaClient = sessionManager?.currentCastSession?.remoteMediaClient else {
            activeDeviceID = nil
            onError?(.castSessionUnavailable)
            PlayerKitLog.debug("CastManager", "Error: No active cast session.")
            return
        }
        guard let playerItem = currentPlayerItemProvider?() else {
            activeDeviceID = nil
            onError?(.unknown("No media selected for casting."))
            return
        }
        guard let externalURL = playerItem.preferredExternalPlaybackURL else {
            activeDeviceID = nil
            onError?(.castURLMissing)
            return
        }
        guard ["http", "https"].contains(externalURL.scheme?.lowercased() ?? "") else {
            activeDeviceID = nil
            onError?(.externalPlaybackRequiresReachableURL)
            return
        }
        
        let mediaLoadRequest = createMediaLoadRequest(for: playerItem)
        cancelPendingMediaLoadRequest()
        let request = remoteMediaClient.loadMedia(with: mediaLoadRequest)
        request.delegate = self
        pendingMediaLoadRequest = request
        pendingMediaLoadRequestID = request.requestID
        pendingRequestKind = .mediaLoad
    }

    func refreshAvailableDevices(force: Bool = false) {
        if force {
            _ = prepareForUserInteraction()
        }
    }

    func playMedia(on device: ExternalPlaybackDevice) {
        activeDeviceID = device.id
        playMediaOnCast()
    }
    
    private func createMediaLoadRequest(for playerItem: PlayerItem) -> GCKMediaLoadRequestData {
        let metadata = createMediaMetadata(for: playerItem)
        let loadPolicy = CastMediaLoadPolicy.resolve(
            for: playerItem,
            currentPlaybackPosition: currentPlaybackPositionProvider?()
        )
        
        let mediaInfoBuilder = GCKMediaInformationBuilder()
        mediaInfoBuilder.contentURL = playerItem.preferredExternalPlaybackURL
        switch loadPolicy.streamKind {
        case .buffered:
            mediaInfoBuilder.streamType = .buffered
        case .live:
            mediaInfoBuilder.streamType = .live
        }
        mediaInfoBuilder.contentType = playerItem.preferredExternalPlaybackContentType
        mediaInfoBuilder.metadata = metadata
        // Keep the existing buffered builder behavior and do not publish a
        // finite duration for live; the receiver owns its moving timeline.
        
        let mediaLoadRequestDataBuilder = GCKMediaLoadRequestDataBuilder()
        mediaLoadRequestDataBuilder.mediaInformation = mediaInfoBuilder.build()
        mediaLoadRequestDataBuilder.autoplay = true
        mediaLoadRequestDataBuilder.startTime = loadPolicy.startTime
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
        sessionManager?.currentCastSession?.remoteMediaClient?.pause()
    }
    
    func stopCast() {
        cancelPendingMediaLoadRequest()
        guard let remoteMediaClient = sessionManager?.currentCastSession?.remoteMediaClient else {
            onError?(.castSessionUnavailable)
            return
        }
        let request = remoteMediaClient.stop()
        request.delegate = self
        pendingMediaLoadRequest = request
        pendingMediaLoadRequestID = request.requestID
        pendingRequestKind = .stop
    }

    /// Detaches a dismissed local player from an in-flight handoff without
    /// stopping media that already started on the receiver.
    func detachPlayerSession() {
        guard pendingMediaLoadRequest != nil,
              pendingRequestKind?.cancelsWhenPlayerDetaches == true else {
            // A requested stop belongs to the receiver, not the departing
            // local UI. Keep its delegate alive until completion so teardown
            // cannot leave remote playback running behind a false idle state.
            return
        }
        cancelPendingMediaLoadRequest()
        activeDeviceID = nil
        isCasting = false
    }

    private func cancelPendingMediaLoadRequest() {
        let request = pendingMediaLoadRequest
        pendingMediaLoadRequest = nil
        pendingMediaLoadRequestID = nil
        pendingRequestKind = nil
        request?.delegate = nil
        request?.cancel()
    }

    private func handleSessionStarted() {
        PlayerKitLog.debug("CastManager", "Cast session started")
        let remoteMediaClient = sessionManager?.currentCastSession?.remoteMediaClient
        observedRemoteMediaClient?.remove(self)
        remoteMediaClient?.add(self)
        observedRemoteMediaClient = remoteMediaClient
        isConnectedToCastDevice = true
        activeDeviceID = sessionManager?.currentCastSession?.device.deviceID
        playMediaOnCast()
    }

    private func handleSessionResumed() {
        PlayerKitLog.debug("CastManager", "Cast session resumed")
        let remoteMediaClient = sessionManager?.currentCastSession?.remoteMediaClient
        observedRemoteMediaClient?.remove(self)
        remoteMediaClient?.add(self)
        observedRemoteMediaClient = remoteMediaClient
        isConnectedToCastDevice = true
        activeDeviceID = sessionManager?.currentCastSession?.device.deviceID
        updateRemoteMediaActivity(remoteMediaClient?.mediaStatus)
    }

    private func handleSessionEnded(errorCode: Int?) {
        PlayerKitLog.debug(
            "CastManager",
            "Cast session ended error_code=\(errorCode.map(String.init) ?? "none")"
        )
        resetCastState()
    }

    private func handleSessionStartFailure(errorCode: Int?) {
        resetCastState()
        PlayerKitLog.debug(
            "CastManager",
            "Cast session start failed error_code=\(errorCode.map(String.init) ?? "unknown")"
        )
        onError?(.externalPlaybackFailed(Self.failureMessage(
            operation: "start Cast session",
            code: errorCode
        )))
    }

    private func completeRequest(id: GCKRequestID) {
        guard id == pendingMediaLoadRequestID,
              let requestKind = pendingRequestKind else { return }
        pendingMediaLoadRequest = nil
        pendingMediaLoadRequestID = nil
        pendingRequestKind = nil
        switch requestKind {
        case .mediaLoad:
            isCasting = true
            PlayerKitLog.debug("CastManager", "Cast media load completed")
            GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
            onDismissRequested?()
        case .stop:
            isCasting = false
            activeDeviceID = nil
            PlayerKitLog.debug("CastManager", "Cast stop completed")
        }
    }

    private func failRequest(id: GCKRequestID, errorCode: Int) {
        guard id == pendingMediaLoadRequestID,
              let requestKind = pendingRequestKind else { return }
        pendingMediaLoadRequest = nil
        pendingMediaLoadRequestID = nil
        pendingRequestKind = nil
        switch requestKind {
        case .mediaLoad:
            isCasting = false
            activeDeviceID = nil
            onError?(.externalPlaybackFailed(Self.failureMessage(
                operation: "load media on Cast receiver",
                code: errorCode
            )))
        case .stop:
            // The receiver rejected the stop, so it may still be playing.
            updateRemoteMediaActivity(observedRemoteMediaClient?.mediaStatus)
            onError?(.externalPlaybackFailed(Self.failureMessage(
                operation: "stop Cast playback",
                code: errorCode
            )))
        }
        PlayerKitLog.debug("CastManager", "Cast request failed error_code=\(errorCode)")
    }

    private func abortRequest(id: GCKRequestID) {
        guard id == pendingMediaLoadRequestID,
              let requestKind = pendingRequestKind else { return }
        pendingMediaLoadRequest = nil
        pendingMediaLoadRequestID = nil
        pendingRequestKind = nil
        switch requestKind {
        case .mediaLoad:
            isCasting = false
            activeDeviceID = nil
            onError?(.externalPlaybackFailed("Cast media load was cancelled."))
        case .stop:
            updateRemoteMediaActivity(observedRemoteMediaClient?.mediaStatus)
            onError?(.externalPlaybackFailed("Cast stop was cancelled."))
        }
    }

    private func updateRemoteMediaActivity(_ status: GCKMediaStatus?) {
        switch status?.playerState {
        case .playing, .paused, .buffering, .loading:
            isCasting = true
        case .idle, .unknown, nil:
            isCasting = false
        @unknown default:
            isCasting = false
        }
    }

    private func updateRemoteMediaActivity(isActive: Bool) {
        isCasting = isActive
    }

    private static func failureMessage(operation: String, code: Int?) -> String {
        guard let code else { return "Unable to \(operation)." }
        return "Unable to \(operation) (Google Cast error code \(code))."
    }
}

// MARK: - GCKSessionManagerListener
extension CastManager: GCKSessionManagerListener {
    nonisolated func sessionManager(
        _ sessionManager: GCKSessionManager,
        didStart session: GCKCastSession
    ) {
        Task { @MainActor [weak self] in
            self?.handleSessionStarted()
        }
    }
    
    nonisolated func sessionManager(
        _ sessionManager: GCKSessionManager,
        didResumeSession session: GCKSession
    ) {
        Task { @MainActor [weak self] in
            self?.handleSessionResumed()
        }
    }
    
    nonisolated func sessionManager(
        _ sessionManager: GCKSessionManager,
        didEnd session: GCKCastSession,
        withError error: Error?
    ) {
        let errorCode = (error as NSError?)?.code
        Task { @MainActor [weak self] in
            self?.handleSessionEnded(errorCode: errorCode)
        }
    }

    nonisolated func sessionManager(
        _ sessionManager: GCKSessionManager,
        didFailToStartSessionWithError error: Error?
    ) {
        let errorCode = (error as NSError?)?.code
        Task { @MainActor [weak self] in
            self?.handleSessionStartFailure(errorCode: errorCode)
        }
    }

    private func resetCastState() {
        cancelPendingMediaLoadRequest()
        observedRemoteMediaClient?.remove(self)
        observedRemoteMediaClient = nil
        isConnectedToCastDevice = false
        isCasting = false
        activeDeviceID = nil
    }
}

// MARK: - GCKRemoteMediaClientListener
extension CastManager: GCKRemoteMediaClientListener {
    nonisolated func remoteMediaClient(
        _ client: GCKRemoteMediaClient,
        didUpdate mediaStatus: GCKMediaStatus?
    ) {
        let isActive: Bool
        switch mediaStatus?.playerState {
        case .playing, .paused, .buffering, .loading:
            isActive = true
        case .idle, .unknown, nil:
            isActive = false
        @unknown default:
            isActive = false
        }
        Task { @MainActor [weak self] in
            self?.updateRemoteMediaActivity(isActive: isActive)
            PlayerKitLog.debug("CastManager", "Media status updated")
        }
    }
}

// MARK: - GCKRequestDelegate
extension CastManager: GCKRequestDelegate {
    nonisolated func requestDidComplete(_ request: GCKRequest) {
        let requestID = request.requestID
        Task { @MainActor [weak self] in
            self?.completeRequest(id: requestID)
        }
    }
    
    nonisolated func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        let requestID = request.requestID
        let errorCode = (error as NSError).code
        Task { @MainActor [weak self] in
            self?.failRequest(id: requestID, errorCode: errorCode)
        }
    }

    nonisolated func request(
        _ request: GCKRequest,
        didAbortWith abortReason: GCKRequestAbortReason
    ) {
        let requestID = request.requestID
        Task { @MainActor [weak self] in
            self?.abortRequest(id: requestID)
        }
    }
}
#else
import Foundation
import Combine

@MainActor
class CastManager: NSObject, ObservableObject {
    static let shared = CastManager()

    @Published var isCasting = false
    @Published var isCastingAvailable = false
    @Published var isConnectedToCastDevice = false
    @Published private(set) var availableDevices: [ExternalPlaybackDevice] = []
    @Published private(set) var isSearchingForDevices = false
    @Published private(set) var activeDeviceID: String?

    var currentPlayerItemProvider: (() -> PlayerItem?)?
    var currentPlaybackPositionProvider: (() -> Double?)?
    var onError: ((PlayerKitError) -> Void)?
    var onDismissRequested: (() -> Void)?

    private override init() {
        super.init()
    }

    @discardableResult
    func configure(receiverApplicationID: String) -> Bool {
        false
    }

    @discardableResult
    func prepareForUserInteraction() -> Bool {
        false
    }

    @discardableResult
    func presentCastDialog() -> Bool {
        false
    }

    func playMediaOnCast() {
        onError?(.castSessionUnavailable)
    }

    func refreshAvailableDevices(force: Bool = false) {}

    func playMedia(on device: ExternalPlaybackDevice) {
        onError?(.castSessionUnavailable)
    }

    func pauseCast() {}

    func stopCast() {
        isCasting = false
        isConnectedToCastDevice = false
        activeDeviceID = nil
    }

    func detachPlayerSession() {}
}
#endif
