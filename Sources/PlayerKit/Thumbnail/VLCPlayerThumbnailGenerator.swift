import VLCKit
import UIKit

@objc class VLCPlayerThumbnailGenerator: NSObject, VLCMediaThumbnailerDelegate {
    private var mediaThumbnailer: VLCMediaThumbnailer!
    private var thumbnailCompletion: ((UIImage?) -> Void)?
    private var media: VLCMedia

    init(media: VLCMedia) {
        self.media = media
        super.init()
        self.mediaThumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
    }

    /// Generates a thumbnail image at the specified time.
    func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        self.thumbnailCompletion = completion

        // Ensure media is parsed
        guard media.length.intValue > 0 else {
            print("Media length is invalid or media not parsed yet.")
            completion(nil)
            return
        }

        // Calculate the snapshot position based on the provided time
        let position = Float(time / Double(media.length.intValue))
        //self.mediaThumbnailer.snapshotPosition = position
        print("Requesting thumbnail at position: \(position * 100)%")

        // Fetch thumbnail
        //self.mediaThumbnailer.fetchThumbnail()
    }

    // MARK: - VLCMediaThumbnailerDelegate Methods

    func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        let uiImage = UIImage(cgImage: thumbnail)
        print("Successfully generated thumbnail.")
        thumbnailCompletion?(uiImage)
    }

    func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        print("VLCPlayerThumbnailGenerator: Thumbnail generation timed out.")
        thumbnailCompletion?(nil)
    }
}

