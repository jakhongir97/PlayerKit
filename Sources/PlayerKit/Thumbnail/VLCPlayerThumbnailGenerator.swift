import VLCKit
import UIKit

public class VLCPlayerThumbnailGenerator: NSObject {
    private var mediaThumbnailer: VLCMediaThumbnailer!
    private var thumbnailCompletion: ((UIImage?) -> Void)?
    private var isFetchingThumbnail = false  // Flag to indicate if a thumbnail is being fetched
    
    /// Initializes the generator with the VLC media object
    public init(media: VLCMedia) {
        super.init()
        self.mediaThumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
    }

    /// Generates a thumbnail at a specific time
    public func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        guard !isFetchingThumbnail else {
            print("A thumbnail is already being fetched. Ignoring new request.")
            return
        }

        self.thumbnailCompletion = completion

        let length = mediaThumbnailer.media.length
        guard length.intValue > 0 else {
            completion(nil)
            return
        }

        let position = Float(time / Double(length.intValue))
        mediaThumbnailer.snapshotPosition = position
        
        // Set the flag to true as we're starting a new request
        isFetchingThumbnail = true
        
        mediaThumbnailer.fetchThumbnail()
    }
}

// MARK: - VLCMediaThumbnailerDelegate
extension VLCPlayerThumbnailGenerator: VLCMediaThumbnailerDelegate {
    
    public func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        let image = UIImage(cgImage: thumbnail)
        thumbnailCompletion?(image)
        
        // Reset the flag once the thumbnail generation completes
        isFetchingThumbnail = false
    }

    public func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        thumbnailCompletion?(nil)
        
        // Reset the flag once the thumbnail generation times out
        isFetchingThumbnail = false
    }
}

