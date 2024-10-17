import Combine
import UIKit

public class ThumbnailManager: ObservableObject {
    public static let shared = ThumbnailManager()
    
    @Published public var thumbnailImage: UIImage?
    
    private init() {}
    
    public func requestThumbnail(for player: PlayerProtocol, at time: Double) {
        player.generateThumbnail(at: time) { [weak self] image in
            DispatchQueue.main.async {
                self?.thumbnailImage = image
            }
        }
    }
}

