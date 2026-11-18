import Foundation
import ZIPFoundation

enum ConsoleArchive {
    static func extract(_ file: URL, system: GameSystem, destination: URL) throws -> URL {
        let archive = try Archive(url: file, accessMode: .read)
        let entries = archive.filter { $0.type == .file && ($0.path as NSString).pathExtension.lowercased() != "zip" && GameSystem.recognises($0.path, for: system) && !$0.path.hasPrefix("__MACOSX/") }
        guard entries.count == 1, let entry = entries.first else { throw StoreError.message("This ZIP must contain one \(system.title) ROM. Extract multi-game archives in Files and add their folder.") }
        guard LibraryRules.safeRelativePath(entry.path), entry.uncompressedSize <= 256 * 1024 * 1024 else { throw StoreError.message("This ZIP contains an unsafe path or a ROM larger than 256 MB.") }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let target = destination.appendingPathComponent((entry.path as NSString).lastPathComponent)
        _ = try archive.extract(entry, to: target)
        return target
    }
}
