import Foundation

public struct StreamingInfo {
    public let frameRate: String
    public let videoBitrate: String
    public let resolution: String
    public let bufferDuration: String

    public init(frameRate: String, videoBitrate: String, resolution: String, bufferDuration: String) {
        self.frameRate = frameRate
        self.videoBitrate = videoBitrate
        self.resolution = resolution
        self.bufferDuration = bufferDuration
    }

    public static let placeholder = StreamingInfo(
        frameRate: "Unknown",
        videoBitrate: "0 Mbps",
        resolution: "Unknown",
        bufferDuration:"0 sec"
    )
}
