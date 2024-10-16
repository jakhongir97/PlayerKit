import VLCKit
import UIKit

public class VLCPlayerThumbnailGenerator: NSObject, VLCMediaThumbnailerDelegate {
    private var mediaThumbnailer: VLCMediaThumbnailer!
    private var thumbnailCompletion: ((UIImage?) -> Void)?
    private var media: VLCMedia

    public init(media: VLCMedia) {
        self.media = media
        super.init()
        self.mediaThumbnailer = VLCMediaThumbnailer(media: media, delegate: self, andVLCLibrary: VLCLibrary.shared())
    }

    /// Generates a thumbnail image at the specified time.
    public func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        self.thumbnailCompletion = completion

        // Ensure media is parsed
        guard media.length.intValue > 0 else {
            print("Media length is invalid or media not parsed yet.")
            completion(nil)
            return
        }

        // Calculate the snapshot position based on the provided time
        let position = Float(time / Double(media.length.intValue))
        self.mediaThumbnailer.snapshotPosition = position
        print("Requesting thumbnail at position: \(position * 100)%")

        // Fetch thumbnail
        self.mediaThumbnailer.fetchThumbnail()
    }

    // MARK: - VLCMediaThumbnailerDelegate Methods

    public func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer!, didFinishThumbnail thumbnail: CGImage!) {
        if let cgImage = thumbnail {
            let uiImage = UIImage(cgImage: cgImage)
            print("Successfully generated thumbnail.")
            thumbnailCompletion?(uiImage)
        } else {
            print("VLCPlayerThumbnailGenerator: Failed to generate thumbnail.")
            thumbnailCompletion?(nil)
        }
    }

    public func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer!) {
        print("VLCPlayerThumbnailGenerator: Thumbnail generation timed out.")
        thumbnailCompletion?(nil)
    }
}

