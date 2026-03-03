import Foundation

public protocol PlayerProtocol: PlaybackControlProtocol,
                                TimeControlProtocol,
                                TrackSelectionProtocol,
                                MediaLoadingProtocol,
                                ViewRenderingProtocol,
                                GestureHandlingProtocol,
                                StreamingInfoProtocol {}
