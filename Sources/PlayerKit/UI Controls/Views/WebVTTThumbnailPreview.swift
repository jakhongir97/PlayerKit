import CoreGraphics
import Foundation
import ImageIO

struct WebVTTThumbnailCue: Equatable, Sendable {
    let identifier: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let imageURL: URL
    let cropRect: CGRect?

    func contains(_ time: TimeInterval) -> Bool {
        time.isFinite && time >= startTime && time < endTime
    }
}

enum WebVTTThumbnailParser {
    static let maximumCueCount = 10_000

    static func parse(_ data: Data, baseURL: URL) -> [WebVTTThumbnailCue] {
        guard var source = String(data: data, encoding: .utf8) else { return [] }
        source = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if source.first == "\u{feff}" { source.removeFirst() }

        let lines = source.components(separatedBy: "\n")
        guard let header = lines.first?.trimmingCharacters(in: .whitespaces),
              header == "WEBVTT" || header.hasPrefix("WEBVTT ") || header.hasPrefix("WEBVTT\t") else {
            return []
        }

        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines.dropFirst() {
            if Task.isCancelled { return [] }
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !current.isEmpty {
                    blocks.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if !current.isEmpty { blocks.append(current) }

        var parsed: [(TimeInterval, TimeInterval, URL, CGRect?)] = []
        for block in blocks {
            if Task.isCancelled { return [] }
            guard parsed.count < maximumCueCount else { break }
            guard let first = block.first, !isMetadata(first),
                  let timingIndex = block.firstIndex(where: { $0.contains("-->") }),
                  let times = parseTimeRange(block[timingIndex]),
                  let payload = block.dropFirst(timingIndex + 1).first(where: { !$0.isEmpty }),
                  let image = parsePayload(payload, baseURL: baseURL) else {
                continue
            }
            parsed.append((times.0, times.1, image.0, image.1))
        }

        parsed.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        return parsed.enumerated().map {
            WebVTTThumbnailCue(
                identifier: $0.offset,
                startTime: $0.element.0,
                endTime: $0.element.1,
                imageURL: $0.element.2,
                cropRect: $0.element.3
            )
        }
    }

    static func parse(_ source: String, baseURL: URL) -> [WebVTTThumbnailCue] {
        parse(Data(source.utf8), baseURL: baseURL)
    }

    static func cue(at time: TimeInterval, in cues: [WebVTTThumbnailCue]) -> WebVTTThumbnailCue? {
        guard time.isFinite, !cues.isEmpty else { return nil }
        var low = 0
        var high = cues.count
        while low < high {
            let middle = low + (high - low) / 2
            if cues[middle].startTime <= time { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }

        // ponytail: thumbnail tracks are normally non-overlapping. This short
        // scan handles overlaps too; replace it with an interval index only if
        // production profiling shows unusually large overlapping manifests.
        for index in stride(from: low - 1, through: 0, by: -1) {
            if cues[index].contains(time) { return cues[index] }
        }
        return nil
    }

    private static func isMetadata(_ line: String) -> Bool {
        ["NOTE", "STYLE", "REGION"].contains {
            line == $0 || line.hasPrefix($0 + " ") || line.hasPrefix($0 + "\t")
        }
    }

    private static func parseTimeRange(_ line: String) -> (TimeInterval, TimeInterval)? {
        guard let arrow = line.range(of: "-->") else { return nil }
        let startText = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        let remainder = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let endText = remainder.split(whereSeparator: \.isWhitespace).first,
              let start = parseTimestamp(startText),
              let end = parseTimestamp(String(endText)),
              start >= 0, end > start else {
            return nil
        }
        return (start, end)
    }

    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let parts = raw.replacingOccurrences(of: ",", with: ".")
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Int(parts[parts.count - 2]), minutes >= 0,
              let seconds = Double(parts[parts.count - 1]), seconds.isFinite,
              seconds >= 0, seconds < 60 else {
            return nil
        }
        let hours: Int
        if parts.count == 3 {
            guard minutes < 60, let value = Int(parts[0]), value >= 0 else { return nil }
            hours = value
        } else {
            hours = 0
        }
        let total = Double(hours) * 3_600 + Double(minutes) * 60 + seconds
        return total.isFinite ? total : nil
    }

    private static func parsePayload(_ line: String, baseURL: URL) -> (URL, CGRect?)? {
        guard let token = line.split(whereSeparator: \.isWhitespace).first,
              let resolved = URL(string: String(token), relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        guard let fragment = resolved.fragment,
              let xywh = fragment.split(separator: "&").first(where: { $0.hasPrefix("xywh=") }) else {
            return (resolved, nil)
        }

        var rawCrop = String(xywh.dropFirst("xywh=".count))
        if rawCrop.hasPrefix("pixel:") { rawCrop.removeFirst("pixel:".count) }
        let parts = rawCrop.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let values = parts.map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.allSatisfy({ $0?.isFinite == true }),
              let x = values[0], let y = values[1], let width = values[2], let height = values[3],
              x >= 0, y >= 0, width > 0, height > 0,
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        guard let imageURL = components.url else { return nil }
        return (imageURL, CGRect(x: x, y: y, width: width, height: height))
    }
}

enum WebVTTThumbnailCropper {
    static func crop(_ image: CGImage, to rect: CGRect?) -> CGImage? {
        guard let rect else { return image }
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.minX >= 0, rect.minY >= 0, rect.width > 0, rect.height > 0 else {
            return nil
        }
        let pixels = CGRect(
            x: floor(rect.minX),
            y: floor(rect.minY),
            width: ceil(rect.maxX) - floor(rect.minX),
            height: ceil(rect.maxY) - floor(rect.minY)
        )
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let crop = pixels.intersection(bounds)
        guard !crop.isNull, crop.width > 0, crop.height > 0,
              let borrowed = image.cropping(to: crop),
              let context = CGContext(
                data: nil,
                width: Int(crop.width),
                height: Int(crop.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.draw(borrowed, in: CGRect(origin: .zero, size: crop.size))
        return context.makeImage()
    }
}

struct BoundedThumbnailDataBuffer: Sendable {
    let limit: Int
    private(set) var data = Data()

    init(limit: Int) { self.limit = max(limit, 0) }

    mutating func append(_ chunk: Data) -> Bool {
        guard data.count <= limit, chunk.count <= limit - data.count else {
            data.removeAll(keepingCapacity: false)
            return false
        }
        data.append(chunk)
        return true
    }
}

final class WebVTTThumbnailToken: @unchecked Sendable {}

struct WebVTTThumbnailGeneration: Sendable {
    private(set) var owner = WebVTTThumbnailToken()
    private(set) var request = WebVTTThumbnailToken()
    private(set) var sprite = WebVTTThumbnailToken()

    @discardableResult mutating func replaceOwner() -> WebVTTThumbnailToken {
        owner = WebVTTThumbnailToken()
        request = WebVTTThumbnailToken()
        sprite = WebVTTThumbnailToken()
        return owner
    }

    @discardableResult mutating func replaceRequest() -> (
        owner: WebVTTThumbnailToken,
        request: WebVTTThumbnailToken
    ) {
        request = WebVTTThumbnailToken()
        return (owner, request)
    }

    @discardableResult mutating func replaceSprite() -> (
        owner: WebVTTThumbnailToken,
        sprite: WebVTTThumbnailToken
    ) {
        sprite = WebVTTThumbnailToken()
        return (owner, sprite)
    }

    func isCurrent(
        owner: WebVTTThumbnailToken,
        request: WebVTTThumbnailToken? = nil
    ) -> Bool {
        self.owner === owner && (request == nil || self.request === request)
    }

    func isCurrent(owner: WebVTTThumbnailToken, sprite: WebVTTThumbnailToken) -> Bool {
        self.owner === owner && self.sprite === sprite
    }
}

struct LatestThumbnailWorkSlot<Work> {
    private(set) var work: Work?

    mutating func replace(with work: Work) { self.work = work }

    mutating func take() -> Work? {
        defer { work = nil }
        return work
    }

    mutating func remove(where shouldRemove: (Work) -> Bool = { _ in true }) {
        if let work, shouldRemove(work) { self.work = nil }
    }
}

final class BoundedThumbnailDataRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Completion = @Sendable (Data?, URL?) -> Void

    private let lock = NSLock()
    private let byteLimit: Int
    private var buffer: BoundedThumbnailDataBuffer
    private var responseURL: URL
    private var completion: Completion?
    private var finished = false
    private var acceptedResponse = false
    private var session: URLSession!
    private var task: URLSessionDataTask!

    init(
        url: URL,
        byteLimit: Int,
        protocolClasses: [AnyClass]? = nil,
        completion: @escaping Completion
    ) {
        self.byteLimit = max(byteLimit, 0)
        buffer = BoundedThumbnailDataBuffer(limit: byteLimit)
        responseURL = url
        self.completion = completion
        super.init()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        task = session.dataTask(with: request)
    }

    func resume() { task.resume() }

    func cancel() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        completion = nil
        buffer = BoundedThumbnailDataBuffer(limit: byteLimit)
        lock.unlock()
        task.cancel()
        session.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let validStatus = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
        guard validStatus, response.expectedContentLength <= Int64(byteLimit) else {
            completionHandler(.cancel)
            finish(success: false)
            return
        }
        lock.lock()
        if !finished {
            acceptedResponse = true
            responseURL = response.url ?? responseURL
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let accepted = !finished && buffer.append(data)
        lock.unlock()
        if !accepted { finish(success: false) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(success: error == nil)
    }

    private func finish(success: Bool) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let callback = completion
        completion = nil
        let accepted = success && acceptedResponse
        let data = accepted ? buffer.data : nil
        let url = accepted ? responseURL : nil
        buffer = BoundedThumbnailDataBuffer(limit: byteLimit)
        lock.unlock()
        task.cancel()
        session.invalidateAndCancel()
        callback?(data, url)
    }

    deinit {
        task?.cancel()
        session?.invalidateAndCancel()
    }
}

struct SendableCGImage: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

struct DecodedThumbnailSprite: @unchecked Sendable {
    let image: CGImage
    let cost: Int
}

actor WebVTTThumbnailProcessor {
    static let defaultDecodedByteLimit = 64 * 1_024 * 1_024

    private let decodedByteLimit: Int

    init(decodedByteLimit: Int = defaultDecodedByteLimit) {
        self.decodedByteLimit = max(decodedByteLimit, 0)
    }

    func parse(_ data: Data, baseURL: URL) -> [WebVTTThumbnailCue]? {
        guard !Task.isCancelled else { return nil }
        let cues = WebVTTThumbnailParser.parse(data, baseURL: baseURL)
        guard !Task.isCancelled else { return nil }
        return cues
    }

    func decode(_ data: Data) -> DecodedThumbnailSprite? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              let preflightCost = Self.rgbaCost(width: width, height: height),
              preflightCost <= decodedByteLimit else {
            return nil
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsDimensions = (5...8).contains(orientation)
        let outputWidth = swapsDimensions ? height : width
        let outputHeight = swapsDimensions ? width : height
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard !Task.isCancelled,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              !Task.isCancelled,
              image.width == outputWidth,
              image.height == outputHeight,
              let cost = Self.cost(image),
              cost <= decodedByteLimit else {
            return nil
        }
        return DecodedThumbnailSprite(image: image, cost: cost)
    }

    func crop(_ image: SendableCGImage, to rect: CGRect?) -> SendableCGImage? {
        guard !Task.isCancelled,
              let result = WebVTTThumbnailCropper.crop(image.image, to: rect),
              !Task.isCancelled else {
            return nil
        }
        return SendableCGImage(result)
    }

    nonisolated static func rgbaCost(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        return pixelOverflow || byteOverflow ? nil : bytes
    }

    nonisolated static func cost(_ image: CGImage) -> Int? {
        let (value, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        return overflow ? nil : max(value, 1)
    }
}

#if os(iOS)
import Combine
import SwiftUI
import UIKit

@MainActor
final class WebVTTThumbnailPreviewController: ObservableObject {
    @Published private(set) var image: UIImage?

    private enum WorkKind { case parse, decode, crop }

    private enum Work {
        case parse(data: Data, baseURL: URL, sourceURL: URL, owner: WebVTTThumbnailToken)
        case decode(
            data: Data,
            url: URL,
            owner: WebVTTThumbnailToken,
            sprite: WebVTTThumbnailToken
        )
        case crop(
            image: SendableCGImage,
            cue: WebVTTThumbnailCue,
            owner: WebVTTThumbnailToken,
            request: WebVTTThumbnailToken
        )

        var kind: WorkKind {
            switch self {
            case .parse: .parse
            case .decode: .decode
            case .crop: .crop
            }
        }
    }

    private static let manifestLimit = 1 * 1_024 * 1_024
    private static let spriteLimit = 16 * 1_024 * 1_024

    private var generation = WebVTTThumbnailGeneration()
    private var desiredSourceURL: URL?
    private var sourceURL: URL?
    private var cues: [WebVTTThumbnailCue] = []
    private var latestTime: TimeInterval?
    private var requestedCue: Int?
    private var activeSpriteURL: URL?
    private var active = false
    private var isPresented = false

    private var manifestRequest: BoundedThumbnailDataRequest?
    private var spriteRequest: BoundedThumbnailDataRequest?
    private var pendingWork = LatestThumbnailWorkSlot<Work>()
    private var processingTask: Task<Void, Never>?
    private var currentWorkKind: WorkKind?

    private let processor = WebVTTThumbnailProcessor()

    private let previews = NSCache<NSNumber, UIImage>()
    private let sprites = NSCache<NSURL, UIImage>()

    init() {
        previews.countLimit = 80
        previews.totalCostLimit = 40 * 1_024 * 1_024
        sprites.countLimit = 24
        sprites.totalCostLimit = 120 * 1_024 * 1_024
    }

    func replaceOwner(sourceURL: URL?) {
        desiredSourceURL = sourceURL
        generation.replaceOwner()
        stopAll()
        self.sourceURL = nil
        cues = []
        latestTime = nil
        requestedCue = nil
        active = false
        image = nil
        previews.removeAllObjects()
        sprites.removeAllObjects()

        guard isPresented, let sourceURL, Self.supports(sourceURL) else { return }
        self.sourceURL = sourceURL
        loadManifest(sourceURL)
    }

    func begin(at time: TimeInterval) {
        guard sourceURL != nil else { return }
        active = true
        latestTime = time
        requestedCue = nil
        image = nil
        generation.replaceRequest()
        update(to: time)
    }

    func update(to time: TimeInterval) {
        guard active else { return }
        latestTime = time
        guard let cue = WebVTTThumbnailParser.cue(at: time, in: cues) else {
            clearPreview()
            return
        }
        guard requestedCue != cue.identifier else { return }
        requestedCue = cue.identifier
        image = nil
        generation.replaceRequest()
        cancelProcessing { $0 == .crop }
        resolve(cue)
    }

    func end() {
        active = false
        latestTime = nil
        requestedCue = nil
        image = nil
        generation.replaceRequest()
        stopSprite()
    }

    func suspend() {
        isPresented = false
        replaceOwner(sourceURL: desiredSourceURL)
    }

    func resumeIfNeeded(sourceURL: URL?) {
        isPresented = true
        guard self.sourceURL != sourceURL else { return }
        replaceOwner(sourceURL: sourceURL)
    }

    private func loadManifest(_ url: URL) {
        let owner = generation.owner
        let request = BoundedThumbnailDataRequest(url: url, byteLimit: Self.manifestLimit) { [weak self] data, finalURL in
            Task { @MainActor in
                guard let self, self.generation.isCurrent(owner: owner), self.sourceURL == url else { return }
                self.manifestRequest = nil
                guard let data, let finalURL else { return }
                self.enqueue(
                    .parse(data: data, baseURL: finalURL, sourceURL: url, owner: owner)
                ) { _ in true }
            }
        }
        manifestRequest = request
        request.resume()
    }

    private func resolve(_ cue: WebVTTThumbnailCue) {
        let key = NSNumber(value: cue.identifier)
        if let preview = previews.object(forKey: key) {
            stopSprite()
            publish(preview, cue: cue.identifier)
            return
        }
        guard Self.supports(cue.imageURL) else { return }
        if let activeSpriteURL, activeSpriteURL != cue.imageURL { stopSprite() }
        if let sprite = sprites.object(forKey: cue.imageURL as NSURL) {
            stopSprite()
            crop(sprite, cue: cue)
            return
        }
        guard activeSpriteURL != cue.imageURL else { return }

        stopSprite()
        activeSpriteURL = cue.imageURL
        let spriteToken = generation.replaceSprite()
        let url = cue.imageURL
        let request = BoundedThumbnailDataRequest(url: url, byteLimit: Self.spriteLimit) { [weak self] data, _ in
            Task { @MainActor in
                guard let self,
                      self.generation.isCurrent(owner: spriteToken.owner, sprite: spriteToken.sprite),
                      self.activeSpriteURL == url else { return }
                self.spriteRequest = nil
                guard let data else { self.activeSpriteURL = nil; return }
                self.decode(data, url: url, spriteToken: spriteToken)
            }
        }
        spriteRequest = request
        request.resume()
    }

    private func decode(
        _ data: Data,
        url: URL,
        spriteToken: (owner: WebVTTThumbnailToken, sprite: WebVTTThumbnailToken)
    ) {
        enqueue(
            .decode(
                data: data,
                url: url,
                owner: spriteToken.owner,
                sprite: spriteToken.sprite
            )
        ) { $0 == .decode || $0 == .crop }
    }

    private func crop(_ sprite: UIImage, cue: WebVTTThumbnailCue) {
        guard let source = sprite.cgImage else { return }
        let token = generation.replaceRequest()
        enqueue(
            .crop(
                image: SendableCGImage(source),
                cue: cue,
                owner: token.owner,
                request: token.request
            )
        ) { $0 == .crop }
    }

    private func enqueue(_ work: Work, cancelling shouldCancel: (WorkKind) -> Bool) {
        if let currentWorkKind, shouldCancel(currentWorkKind) { processingTask?.cancel() }
        pendingWork.replace(with: work)
        startProcessingIfNeeded()
    }

    private func startProcessingIfNeeded() {
        guard processingTask == nil, pendingWork.work != nil else { return }
        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let work = self.pendingWork.take() {
                self.currentWorkKind = work.kind
                await self.process(work)
                self.currentWorkKind = nil
            }
            self.currentWorkKind = nil
            self.processingTask = nil
            self.startProcessingIfNeeded()
        }
    }

    private func process(_ work: Work) async {
        switch work {
        case let .parse(data, baseURL, sourceURL, owner):
            let cues = await processor.parse(data, baseURL: baseURL)
            guard !Task.isCancelled, generation.isCurrent(owner: owner),
                  self.sourceURL == sourceURL, let cues else { return }
            self.cues = cues
            if active, let time = latestTime { update(to: time) }

        case let .decode(data, url, owner, spriteToken):
            let decoded = await processor.decode(data)
            guard !Task.isCancelled,
                  generation.isCurrent(owner: owner, sprite: spriteToken),
                  activeSpriteURL == url else { return }
            activeSpriteURL = nil
            guard let decoded else { return }
            let sprite = UIImage(cgImage: decoded.image)
            sprites.setObject(sprite, forKey: url as NSURL, cost: decoded.cost)
            guard let id = requestedCue,
                  let cue = cues.first(where: { $0.identifier == id }), cue.imageURL == url else { return }
            crop(sprite, cue: cue)

        case let .crop(source, cue, owner, request):
            let result = await processor.crop(source, to: cue.cropRect)
            guard !Task.isCancelled, active,
                  generation.isCurrent(owner: owner, request: request),
                  requestedCue == cue.identifier, let result else { return }
            let preview = UIImage(cgImage: result.image)
            previews.setObject(
                preview,
                forKey: NSNumber(value: cue.identifier),
                cost: WebVTTThumbnailProcessor.cost(result.image) ?? 0
            )
            publish(preview, cue: cue.identifier)
        }
    }

    private func publish(_ image: UIImage, cue: Int) {
        guard active, requestedCue == cue else { return }
        self.image = image
    }

    private func clearPreview() {
        guard requestedCue != nil || image != nil || activeSpriteURL != nil else { return }
        requestedCue = nil
        image = nil
        generation.replaceRequest()
        stopSprite()
    }

    private func stopAll() {
        manifestRequest?.cancel()
        manifestRequest = nil
        stopSprite()
        cancelProcessing { $0 == .parse }
    }

    private func stopSprite() {
        generation.replaceSprite()
        spriteRequest?.cancel()
        spriteRequest = nil
        cancelProcessing { $0 == .decode || $0 == .crop }
        activeSpriteURL = nil
    }

    private func cancelProcessing(where shouldCancel: (WorkKind) -> Bool) {
        pendingWork.remove { shouldCancel($0.kind) }
        if let currentWorkKind, shouldCancel(currentWorkKind) { processingTask?.cancel() }
    }

    private static func supports(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

}

@MainActor
struct WebVTTThumbnailPreviewOverlay: View {
    @ObservedObject var controller: WebVTTThumbnailPreviewController

    var body: some View {
        Group {
            if let image = controller.image {
                ZStack {
                    Color.black
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                }
                .edgesIgnoringSafeArea(.all)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
