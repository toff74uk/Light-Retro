import Foundation
import UIKit
import ImageIO
import CryptoKit

actor ArtworkLoader {
    static let shared = ArtworkLoader()
    private let memory = NSCache<NSString, NSData>()
    private var missing: [String: Date] = [:]
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let cache: URL
    private let session: URLSession
    init() {
        cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        memory.totalCostLimit = 16 * 1024 * 1024
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 10
        config.httpMaximumConnectionsPerHost = 3
        session = URLSession(configuration: config)
    }
    private func acquire() async { if active < 3 { active += 1 } else { await withCheckedContinuation { waiting.append($0) } } }
    private func release() { if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() } }
    func retryMissing() { missing.removeAll(); memory.removeAllObjects() }
    nonisolated static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 12_000, height <= 12_000 else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.85)
    }
    func load(_ game: Game, root: URL?, manual: URL?, downloads: Bool) async -> Data? {
        let raw = "\(game.id)|\(game.customTitle ?? "")|\(game.catalogueTitle ?? "")|\(game.localArtworkPath ?? "")|\(game.artwork ?? "")"
        let key = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        if let bytes = memory.object(forKey: key as NSString) { return bytes as Data }
        await acquire(); defer { release() }
        if Task.isCancelled { return nil }
        if let bytes = memory.object(forKey: key as NSString) { return bytes as Data }
        let disk = cache.appendingPathComponent(key + ".jpg")
        func remember(_ bytes: Data) -> Data { memory.setObject(bytes as NSData, forKey: key as NSString, cost: bytes.count); return bytes }
        if let manual, let bytes = try? Data(contentsOf: manual), let image = Self.thumbnail(bytes) { return remember(image) }
        if let bytes = localImage(game, root: root) { return remember(bytes) }
        if let bytes = try? Data(contentsOf: disk) { return remember(bytes) }
        guard downloads, missing[key].map({ Date().timeIntervalSince($0) > 3600 }) ?? true else { return nil }
        var allNotFound = true
        for url in GameCatalogue.artworkURLs(game) {
            if Task.isCancelled { return nil }
            do {
                let (stream, response) = try await session.bytes(from: url)
                guard let response = response as? HTTPURLResponse else { continue }
                guard response.statusCode == 200 else { if response.statusCode != 404 { allNotFound = false }; continue }
                guard response.expectedContentLength <= 3_000_000 else { continue }
                var data = Data()
                for try await byte in stream {
                    data.append(byte)
                    if data.count > 3_000_000 || Task.isCancelled { break }
                }
                guard !Task.isCancelled, data.count <= 3_000_000, let image = Self.thumbnail(data) else { continue }
                try? image.write(to: disk, options: .atomic); trimCache()
                return remember(image)
            } catch { if Task.isCancelled { return nil }; allNotFound = false; break }
        }
        if allNotFound { missing[key] = Date() }
        return nil
    }
    private func localImage(_ game: Game, root: URL?) -> Data? {
        guard let root else { return nil }
        let access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
        let parent = (game.relativePath as NSString).deletingLastPathComponent
        var paths = [game.localArtworkPath].compactMap { $0 }
        for dir in [parent, parent + "/covers", parent + "/images", "covers", "artwork", "images"] {
            for name in [game.romStem, game.catalogueTitle ?? game.title, game.displayTitle] {
                for ext in ["png", "jpg", "jpeg"] { paths.append((dir.isEmpty ? "" : dir + "/") + name + "." + ext) }
            }
        }
        let base = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        for path in paths where LibraryRules.safeRelativePath(path) {
            let url = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
            guard url.pathComponents.starts(with: base), let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 20_000_000,
                  let bytes = try? Data(contentsOf: url), let image = Self.thumbnail(bytes) else { continue }
            return image
        }
        return nil
    }
    private func trimCache() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let sizes = files.map { ($0, (try? $0.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]))) }
        var total = sizes.reduce(0) { $0 + ($1.1?.fileSize ?? 0) }
        for (file, values) in sizes.sorted(by: { ($0.1?.contentModificationDate ?? .distantPast) < ($1.1?.contentModificationDate ?? .distantPast) }) where total > 150 * 1024 * 1024 {
            try? fm.removeItem(at: file); total -= values?.fileSize ?? 0
        }
    }
}
