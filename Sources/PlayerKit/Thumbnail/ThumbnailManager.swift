import UIKit
import Combine

public class ThumbnailManager: ObservableObject {
    public static let shared = ThumbnailManager()
    
    @Published public var thumbnailImage: UIImage?
    private var thumbnails: [Double: UIImage] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private var currentRequestTime: Double?
    
    private init() {}
    
    /// Generates a thumbnail at the given time dynamically during seeking.
    public func requestThumbnail(for player: PlayerProtocol, at time: Double) {
        currentRequestTime = time
        
        // Check if we already have the thumbnail cached
        if let cachedThumbnail = thumbnails[time] {
            thumbnailImage = cachedThumbnail
            return
        }
        
        // Request a new thumbnail from the player
        player.generateThumbnail(at: time) { [weak self] image in
            if let image = image, self?.currentRequestTime == time {
                DispatchQueue.main.async {
                    self?.thumbnails[time] = image
                    self?.thumbnailImage = image
                }
            }
        }
    }
}

