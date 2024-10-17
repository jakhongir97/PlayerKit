import AVFoundation
import UIKit

/// A simple class responsible for generating thumbnail images from an AVAsset at specified times.
public class AVPlayerThumbnailGenerator {
    
    private let asset: AVAsset
    private let imageGenerator: AVAssetImageGenerator
    
    public init(asset: AVAsset) {
        self.asset = asset
        self.imageGenerator = AVAssetImageGenerator(asset: asset)
        self.imageGenerator.appliesPreferredTrackTransform = true
        self.imageGenerator.requestedTimeToleranceBefore = .zero
        self.imageGenerator.requestedTimeToleranceAfter = .zero
    }
    
    /// Generates a thumbnail image at the specified time.
    /// - Parameters:
    ///   - time: The time in seconds at which to generate the thumbnail.
    ///   - completion: Completion handler called with the generated UIImage or nil if failed.
    public func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        print("Generating thumbnail at time \(time)")
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        
        // Generate the CGImage asynchronously
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { _, cgImage, _, _, error in
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

