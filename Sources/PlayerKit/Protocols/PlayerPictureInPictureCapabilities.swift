import Foundation

protocol PlayerPictureInPictureSupporting: AnyObject {
    var isPictureInPictureSupported: Bool { get }
    var isPictureInPicturePossible: Bool { get }
}
