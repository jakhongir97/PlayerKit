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
        // Load the asset asynchronously to ensure it's fully ready.
        asset.loadValuesAsynchronously(forKeys: ["duration"]) {
            var error: NSError? = nil
            let status = self.asset.statusOfValue(forKey: "duration", error: &error)
            
            if status == .loaded {
                // Check if the requested time is within the valid duration.
                let duration = CMTimeGetSeconds(self.asset.duration)
                if time > duration {
                    print("Requested time \(time) exceeds video duration \(duration). Using maximum duration instead.")
                    let cmTime = CMTime(seconds: duration, preferredTimescale: 600)
                    self.generateThumbnail(at: CMTimeGetSeconds(cmTime), completion: completion)
                    return
                }

                // Proceed with generating the thumbnail if within bounds.
                let cmTime = CMTime(seconds: time, preferredTimescale: 600)
                self.imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { _, image, _, _, error in
                    if let error = error {
                        print("AVPlayerThumbnailGenerator: Error generating thumbnail at \(time) seconds: \(error.localizedDescription)")
                        completion(nil)
                    } else if let image = image {
                        let uiImage = UIImage(cgImage: image)
                        completion(uiImage)
                    } else {
                        print("AVPlayerThumbnailGenerator: Failed to generate thumbnail for unknown reasons.")
                        completion(nil)
                    }
                }
            } else {
                print("AVPlayerThumbnailGenerator: Asset could not be loaded. Error: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
            }
        }
    }
}
