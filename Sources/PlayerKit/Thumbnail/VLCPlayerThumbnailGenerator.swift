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

    func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        print("VLCPlayerThumbnailGenerator: Requesting thumbnail at time \(time)")
        self.thumbnailCompletion = completion

        guard media.length.intValue > 0 else {
            print("VLCPlayerThumbnailGenerator: Media length is invalid or not parsed yet.")
            completion(nil)
            return
        }

        let position = Float(time / Double(media.length.intValue))
        self.mediaThumbnailer.snapshotPosition = position
        print("VLCPlayerThumbnailGenerator: Requesting thumbnail at position \(position * 100)%")
        self.mediaThumbnailer.fetchThumbnail()
    }

    func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        let uiImage = UIImage(cgImage: thumbnail)
        print("VLCPlayerThumbnailGenerator: Successfully generated thumbnail.")
        thumbnailCompletion?(uiImage)
    }

    func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        print("VLCPlayerThumbnailGenerator: Thumbnail generation timed out.")
        thumbnailCompletion?(nil)
    }
}

