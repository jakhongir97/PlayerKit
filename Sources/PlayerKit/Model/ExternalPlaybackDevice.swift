import Foundation

struct ExternalPlaybackDevice: Identifiable, Hashable {
    enum Kind: String {
        case dlna
        case googleCast
    }

    let id: String
    let name: String
    let kind: Kind
    let locationURL: URL?
    let avTransportControlURL: URL?
}
