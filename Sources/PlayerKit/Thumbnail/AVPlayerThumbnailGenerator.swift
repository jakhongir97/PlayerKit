import AVFoundation
import UIKit

/// A class responsible for generating thumbnail images from an AVAsset at specified times.
public class AVPlayerThumbnailGenerator {
    
    private let asset: AVAsset
    private let imageGenerator: AVAssetImageGenerator
    
    public init(asset: AVAsset) {
        self.asset = asset
        self.imageGenerator = AVAssetImageGenerator(asset: asset)
        self.imageGenerator.appliesPreferredTrackTransform = true
        // Set looser tolerances to reduce precision and improve performance
        self.imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        self.imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        // Optionally limit the image size for better performance
        self.imageGenerator.maximumSize = CGSize(width: 200, height: 112) // 16:9 ratio
    }
    
    /// Generates a thumbnail image at the specified time asynchronously.
    /// - Parameters:
    ///   - time: The time in seconds at which to generate the thumbnail.
    ///   - completion: Completion handler called with the generated UIImage or nil if failed.
    public func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        print("Generating thumbnail at time \(time)")
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        
        // Generate the CGImage asynchronously
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { requestedTime, cgImage, actualTime, result, error in
            if let error = error {
                print("Error generating thumbnail: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            guard let cgImage = cgImage else {
                print("No image generated at time \(time)")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let uiImage = UIImage(cgImage: cgImage)
            print("Successfully generated thumbnail for time \(time)")
            
            DispatchQueue.main.async {
                completion(uiImage)
            }
        }
    }
}

