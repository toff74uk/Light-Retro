import XCTest
import ZIPFoundation
@testable import LightRetro

final class ConsoleArchiveTests: XCTestCase {
    func testExtractSingleROMAndRejectAmbiguity() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let bytes = Data("not a real ROM".utf8)
        let file = root.appendingPathComponent("game.zip")
        let archive = try Archive(url: file, accessMode: .create)
        try archive.addEntry(with: "nested/game.z64", type: .file, uncompressedSize: Int64(bytes.count), provider: { position, size in bytes.subdata(in: Int(position)..<(Int(position) + size)) })
        let result = try ConsoleArchive.extract(file, system: .n64, destination: root.appendingPathComponent("out"))
        XCTAssertEqual(try Data(contentsOf: result), bytes)
        XCTAssertEqual(result.lastPathComponent, "game.z64")
        try archive.addEntry(with: "second.z64", type: .file, uncompressedSize: Int64(bytes.count), provider: { position, size in bytes.subdata(in: Int(position)..<(Int(position) + size)) })
        XCTAssertThrowsError(try ConsoleArchive.extract(file, system: .n64, destination: root.appendingPathComponent("ambiguous")))
    }
    func testArchiveTraversalAndTemporaryCleanup() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("unsafe.zip")
        let archive = try Archive(url: file, accessMode: .create)
        try archive.addEntry(with: "../escape.nes", type: .file, uncompressedSize: 1, provider: { _, _ in Data([1]) })
        XCTAssertThrowsError(try ConsoleArchive.extract(file, system: .nes, destination: root.appendingPathComponent("out")))
        let good = root.appendingPathComponent("good.zip")
        let safeArchive = try Archive(url: good, accessMode: .create)
        try safeArchive.addEntry(with: "game.nes", type: .file, uncompressedSize: 1, provider: { _, _ in Data([1]) })
        var access: GameAccess? = GameAccess(root: root, path: "good.zip")
        try access?.prepareConsoleZIP(for: .nes)
        let extracted = try XCTUnwrap(access?.url)
        XCTAssertTrue(fm.fileExists(atPath: extracted.path))
        access = nil
        XCTAssertFalse(fm.fileExists(atPath: extracted.path))
        XCTAssertTrue(fm.fileExists(atPath: good.path))
    }
}
