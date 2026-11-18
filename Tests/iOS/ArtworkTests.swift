import XCTest
import UIKit
@testable import LightRetro

final class ArtworkTests: XCTestCase {
    @MainActor func testRefreshPicksUpReplacedLocalCoverWithoutNetwork() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let covers = root.appendingPathComponent("covers", isDirectory: true)
        try fm.createDirectory(at: covers, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = covers.appendingPathComponent("fixture.png")
        func image(_ colour: UIColor) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).pngData { context in context.cgContext.setFillColor(colour.cgColor); context.cgContext.fill(CGRect(x: 0, y: 0, width: 24, height: 24)) }
        }
        try image(.red).write(to: file)
        let game = Game(title: "Fixture", system: .nes, relativePath: "fixture.nes")
        let loader = ArtworkLoader()
        let first = await loader.load(game, root: root, manual: nil, downloads: false)
        XCTAssertNotNil(first)
        try image(.blue).write(to: file)
        await loader.retryMissing()
        let updated = await loader.load(game, root: root, manual: nil, downloads: false)
        XCTAssertNotNil(updated)
        XCTAssertNotEqual(first, updated, "Rescanning must refresh a changed local cover at the same filename")
    }
}
