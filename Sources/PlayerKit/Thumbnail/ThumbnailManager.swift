import Combine
import UIKit

/// A simple manager for handling thumbnail generation requests and updating the UI.
public class ThumbnailManager: ObservableObject {
    public static let shared = ThumbnailManager()
    
    @Published public var thumbnailImage: UIImage?
    
    private var debounceTimer: Timer?
    
    private init() {}
    
    /// Requests a thumbnail with debouncing to avoid excessive requests.
    public func requestThumbnail(for player: PlayerProtocol, at time: Double) {
        // Cancel any previous debounce timer
        debounceTimer?.invalidate()
        
        // Set up a debounced request
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            player.generateThumbnail(at: time) { [weak self] image in
                DispatchQueue.main.async {
                    self?.thumbnailImage = image
                }
            }
        }
    }
    
    /// Cancels any ongoing thumbnail requests.
    public func cancelThumbnailRequest() {
        debounceTimer?.invalidate()
    }
}
