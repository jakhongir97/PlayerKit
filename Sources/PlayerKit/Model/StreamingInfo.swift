import Foundation

public struct StreamingInfo {
    let server: String
    let bitrates: [String]
    let loadingSpeed: String
    let bufferDuration: Int
    let videoCodec: String
    let resolution: String
    let videoBitrate: String
    let audioCodec: String
    let trackName: String
    let channels: String

    static let placeholder = StreamingInfo(
        server: "Unknown",
        bitrates: [],
        loadingSpeed: "0 kbps",
        bufferDuration: 0,
        videoCodec: "Unknown",
        resolution: "Unknown",
        videoBitrate: "0 kbps",
        audioCodec: "Unknown",
        trackName: "Unknown",
        channels: "Unknown"
    )
}

