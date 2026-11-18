import XCTest
import ZIPFoundation
@testable import LightRetro

final class ConsoleArchiveTests: XCTestCase {
    func testArcadeDiscAuditDistinguishesHeaderAndBIOSFailures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("sfiii3")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rom = root.appendingPathComponent("sfiii3.zip")
        let zip = try Archive(url: rom, accessMode: .create)
        try zip.addEntry(with: "sfiii3_euro.29f400.u2", type: .file, uncompressedSize: Int64(1),
                         provider: { _, _ in Data([1]) })
        let game = Game(title: "", system: .arcade, relativePath: "sfiii3.zip", folderID: UUID())
        let digest = String(repeating: "11", count: 20)
        let set = ArcadeDiscSet(parents: nil, discs: ["cap-33s-2": digest])
        let missing = ArcadeFileCheck.report(game: game, archive: rom, set: set)
        XCTAssertTrue(missing.contains("Expected BIOS missing or incorrect"))
        XCTAssertTrue(missing.contains("Missing cap-33s-2.chd"))
        let file = folder.appendingPathComponent("cap-33s-2.chd")
        var header = Data(repeating: 0, count: 124)
        header.replaceSubrange(0..<8, with: "MComprHD".utf8)
        header[11] = 124
        header[15] = 5
        header.replaceSubrange(84..<104, with: Data(repeating: 0x11, count: 20))
        try header.write(to: file)
        XCTAssertTrue(ArcadeFileCheck.report(game: game, archive: rom, set: set).contains("Disc header matches MAME"))
        header[84] = 0
        try header.write(to: file)
        XCTAssertTrue(ArcadeFileCheck.discResult(file, expected: digest).contains("Disc ID does not match"))
        try header.prefix(100).write(to: file)
        XCTAssertTrue(ArcadeFileCheck.discResult(file, expected: digest).contains("Incomplete CHD header"))
    }

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
        try archive.addEntry(with: "../escape.nes", type: .file, uncompressedSize: Int64(1), provider: { _, _ in Data([1]) })
        XCTAssertThrowsError(try ConsoleArchive.extract(file, system: .nes, destination: root.appendingPathComponent("out")))
        let good = root.appendingPathComponent("good.zip")
        let safeArchive = try Archive(url: good, accessMode: .create)
        try safeArchive.addEntry(with: "game.nes", type: .file, uncompressedSize: Int64(1), provider: { _, _ in Data([1]) })
        var access: GameAccess? = GameAccess(root: root, path: "good.zip")
        try access?.prepareConsoleZIP(for: .nes)
        let extracted = try XCTUnwrap(access?.url)
        XCTAssertTrue(fm.fileExists(atPath: extracted.path))
        access = nil
        XCTAssertFalse(fm.fileExists(atPath: extracted.path))
        XCTAssertTrue(fm.fileExists(atPath: good.path))
    }
}
