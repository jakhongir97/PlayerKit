import Foundation
import UIKit

public protocol PlayerProtocol: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var isBuffering: Bool { get }

    var availableAudioTracks: [String] { get }
    var availableSubtitles: [String] { get }
    var availableVideoTracks: [String] { get }
    
    var playbackSpeed: Float { get set }

    func play()
    func pause()
    func stop()
    func load(url: URL)

    /// Updated seek method with optional completion handler
    func seek(to time: Double, completion: ((Bool) -> Void)?)
    
    func selectAudioTrack(index: Int)
    func selectSubtitle(index: Int)
    func selectVideoTrack(index: Int)
    
    func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void)
    
    // View management and PiP abstraction
    func getPlayerView() -> UIView  // Return the reusable view for rendering
    func setupPiP()                 // Setup PiP functionality if supported
    func startPiP()                 // Start PiP
    func stopPiP()                  // Stop PiP
}
