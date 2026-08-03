import Foundation

@MainActor
public protocol PlayerPictureInPictureSupporting: AnyObject {
    var isPictureInPictureSupported: Bool { get }
    var isPictureInPicturePossible: Bool { get }
}
