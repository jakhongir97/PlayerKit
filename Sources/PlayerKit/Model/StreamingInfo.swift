import Foundation

public struct StreamingInfo {
    let frameRate: String
    let videoBitrate: String
    let resolution: String
    let bufferDuration: String

    static let placeholder = StreamingInfo(
        frameRate: "Unknown",
        videoBitrate: "0 Mbps",
        resolution: "Unknown",
        bufferDuration:"0 sec"
    )
}

