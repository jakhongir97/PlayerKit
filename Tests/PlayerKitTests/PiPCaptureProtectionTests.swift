import XCTest
@testable import PlayerKit

/// Picture in Picture must be withheld while a capture-protecting policy is
/// active.
///
/// Every protection PlayerKit has stops at the app's own windows: `.automatic`
/// takes the hosting `NSWindow` out of capture, `.blackOutVideo` blanks the
/// video surface in-window, and the iOS secure canvas re-parents the player
/// view. The PiP window is none of ours — it is composited by a system process
/// (`PIPAgent` on macOS) — so a PiP session shows, and lets any recorder
/// capture, the exact frames the policy promises to hide. The only coherent
/// behaviour is: no PiP unless the policy is `.allowCapture`, and a live PiP
/// session dies the moment the policy flips to a protecting one.
@MainActor
final class PiPCaptureProtectionTests: XCTestCase {

    private var manager: PlayerManager!
    private var backend: PiPRecordingBackend!
    private var originalPolicy: PlayerCaptureProtectionPolicy!

    override func setUp() async throws {
        manager = PlayerManager.shared
        originalPolicy = manager.captureProtectionPolicy
        backend = PiPRecordingBackend()
        manager.currentPlayer = backend
    }

    override func tearDown() async throws {
        manager.playerDidChangePiPState(isActive: false)
        manager.captureProtectionPolicy = originalPolicy
        manager.tearDown()
        backend = nil
        manager = nil
    }

    /// The policy itself owns the rule, so every consumer gates the same way.
    func testOnlyAllowCapturePermitsPictureInPicture() {
        XCTAssertFalse(PlayerCaptureProtectionPolicy.automatic.allowsPictureInPicture)
        XCTAssertFalse(PlayerCaptureProtectionPolicy.blackOutVideo.allowsPictureInPicture)
        XCTAssertTrue(PlayerCaptureProtectionPolicy.allowCapture.allowsPictureInPicture)
    }

    /// A backend that fully supports PiP must still report unsupported under a
    /// protecting policy — `isPiPSupported` is what hides the PiP button.
    func testProtectingPoliciesWithholdPiPSupport() {
        manager.captureProtectionPolicy = .automatic
        XCTAssertFalse(manager.isPiPSupported)
        XCTAssertFalse(manager.canTogglePiP)

        manager.captureProtectionPolicy = .blackOutVideo
        XCTAssertFalse(manager.isPiPSupported)
        XCTAssertFalse(manager.canTogglePiP)

        manager.captureProtectionPolicy = .allowCapture
        XCTAssertTrue(manager.isPiPSupported)
        XCTAssertTrue(manager.canTogglePiP)
    }

    /// The button is hidden under a protecting policy, but hosts can call
    /// `startPiP()` directly; the refusal has to live in the manager too.
    func testStartPiPIsRefusedWhileVideoIsHiddenFromCapture() {
        manager.captureProtectionPolicy = .blackOutVideo
        manager.startPiP()
        XCTAssertEqual(backend.startPiPCallCount, 0)

        manager.captureProtectionPolicy = .automatic
        manager.startPiP()
        XCTAssertEqual(backend.startPiPCallCount, 0)

        manager.captureProtectionPolicy = .allowCapture
        manager.startPiP()
        XCTAssertEqual(backend.startPiPCallCount, 1)
    }

    /// A session legitimately started under `.allowCapture` must not keep the
    /// system PiP window on screen once the host flips to a protecting policy
    /// (the ⇧⌥⌘H menu toggle does exactly this flip mid-playback).
    func testFlippingToProtectingPolicyStopsAnActivePiPSession() {
        manager.captureProtectionPolicy = .allowCapture
        manager.playerDidChangePiPState(isActive: true)

        manager.captureProtectionPolicy = .blackOutVideo
        XCTAssertEqual(backend.stopPiPCallCount, 1)
    }

    /// No PiP session, no stop call — flipping between the two protecting
    /// policies must not poke the backend.
    func testPolicyFlipsWithoutActivePiPDoNotTouchTheBackend() {
        manager.captureProtectionPolicy = .automatic
        manager.captureProtectionPolicy = .blackOutVideo
        manager.captureProtectionPolicy = .automatic
        XCTAssertEqual(backend.stopPiPCallCount, 0)
        XCTAssertEqual(backend.startPiPCallCount, 0)
    }

    /// Stopping must always pass through — a protecting policy is a reason to
    /// end PiP, never a reason to strand a running session.
    func testStopPiPPassesThroughUnderAnyPolicy() {
        manager.captureProtectionPolicy = .blackOutVideo
        manager.stopPiP()
        XCTAssertEqual(backend.stopPiPCallCount, 1)
    }
}

@MainActor
private final class PiPRecordingBackend: PlayerProtocol, PlayerPictureInPictureSupporting {
    var isPlaying = false
    var playbackSpeed: Float = 1
    var currentTime: Double = 0
    var duration: Double = 600
    var bufferedDuration: Double = 0
    var isBuffering = false
    var availableAudioTracks: [TrackInfo] = []
    var availableSubtitles: [TrackInfo] = []
    var currentAudioTrack: TrackInfo?
    var currentSubtitleTrack: TrackInfo?

    let isPictureInPictureSupported = true
    let isPictureInPicturePossible = true
    private(set) var startPiPCallCount = 0
    private(set) var stopPiPCallCount = 0

    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }

    func seek(to time: Double, completion: (@MainActor (Bool) -> Void)?) {
        currentTime = time
        completion?(true)
    }

    func scrubForward(by seconds: TimeInterval) { currentTime += seconds }
    func scrubBackward(by seconds: TimeInterval) { currentTime -= seconds }
    func selectAudioTrack(withID id: String) {}
    func selectSubtitle(withID id: String?) {}

    func load(url: URL, lastPosition: Double?) {
        currentTime = lastPosition ?? 0
    }

    func getPlayerView() -> PKView {
        PlayerKit.AVPlayerView()
    }

    func setupPiP() {}
    func startPiP() { startPiPCallCount += 1 }
    func stopPiP() { stopPiPCallCount += 1 }
    func handlePinchGesture(scale: CGFloat) {}
    func setGravityToDefault() {}
    func setGravityToFill() {}

    func fetchStreamingInfo() -> StreamingInfo {
        .placeholder
    }
}
