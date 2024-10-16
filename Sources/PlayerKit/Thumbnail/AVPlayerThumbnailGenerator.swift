import AVFoundation
import UIKit

public class AVPlayerThumbnailGenerator {
    private let asset: AVAsset
    private let imageGenerator: AVAssetImageGenerator

    public init(asset: AVAsset) {
        self.asset = asset
        self.imageGenerator = AVAssetImageGenerator(asset: asset)
        self.imageGenerator.appliesPreferredTrackTransform = true
        self.imageGenerator.requestedTimeToleranceBefore = CMTime.zero
        self.imageGenerator.requestedTimeToleranceAfter = CMTime.zero
    }

    /// Generates a thumbnail image at the specified time.
    public func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { _, image, _, _, error in
            if let error = error {
                print("AVPlayerThumbnailGenerator: Error generating thumbnail at \(time) seconds: \(error.localizedDescription)")
                completion(nil)
            } else if let image = image {
                let uiImage = UIImage(cgImage: image)
                completion(uiImage)
            } else {
                completion(nil)
            }
        }
    }
}


