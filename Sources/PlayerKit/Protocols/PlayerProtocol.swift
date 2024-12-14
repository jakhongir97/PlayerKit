import Foundation
import UIKit

public protocol PlayerProtocol: PlaybackControlProtocol,
                                TimeControlProtocol,
                                TrackSelectionProtocol,
                                MediaLoadingProtocol,
                                ViewRenderingProtocol,
                                GestureHandlingProtocol,
                                StreamingInfoProtocol,
                                ThumbnailGeneratorProtocol {}
