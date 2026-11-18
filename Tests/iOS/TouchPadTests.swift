import XCTest
@testable import LightRetro

final class TouchPadTests: XCTestCase {
    func testArcadeCountsOrderAndCoreAssignments() {
        let fighter = [1, 9, 10, 0, 8, 11]
        for count in 2...6 {
            for (system, expected) in [(GameSystem.arcade, [0, 8, 1, 9, 10, 11]), (.fbneo, fighter)] {
                let buttons = TouchPad.face(system: system, count: count, fbneoInputs: fighter)
                XCTAssertEqual(buttons.map(\.label), (1...count).map(String.init))
                XCTAssertEqual(buttons.map(\.input), expected.prefix(count).map(PadButton.Input.digital))
                XCTAssertEqual(Set(buttons.map(\.input)).count, count)
                XCTAssertEqual(buttons.filter { $0.row == 0 }.count, count == 4 ? 2 : min(3, count))
            }
        }
        let partial = TouchPad.face(system: .fbneo, count: 6, fbneoInputs: [9, 0])
        XCTAssertEqual(partial.prefix(2).map(\.input), [.digital(9), .digital(0)])
        XCTAssertEqual(Set(partial.map(\.input)).count, 6)
    }

    func testConsoleButtonsDriveExpectedInputs() {
        func face(_ system: GameSystem, _ count: Int = 6) -> [PadButton] {
            TouchPad.face(system: system, count: count, fbneoInputs: [])
        }
        XCTAssertEqual(face(.nes).map(\.input), [.digital(0), .digital(8)])
        XCTAssertEqual(face(.snes).map(\.label), ["X", "Y", "A", "B"])
        XCTAssertEqual(face(.snes).map(\.input), [.digital(9), .digital(1), .digital(8), .digital(0)])
        XCTAssertEqual(face(.pce).map(\.label), ["II", "I"])
        XCTAssertEqual(face(.pcecd).map(\.input), [.digital(0), .digital(8)])
        XCTAssertEqual(face(.mega, 3).map(\.label), ["A", "B", "C"])
        XCTAssertEqual(face(.mega).map(\.input), [10, 9, 11, 1, 0, 8].map(PadButton.Input.digital))
        XCTAssertEqual(Set(face(.n64).map(\.input)), [.digital(1), .digital(0), .cDirection(4), .cDirection(5), .cDirection(6), .cDirection(7)])
    }

    func testMegaDriveReadsCartridgePeripheralField() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var data = Data(repeating: 0x20, count: 512)
        data.replaceSubrange(256..<260, with: "SEGA".utf8)
        data[400] = 0x4a
        try data.write(to: url)
        XCTAssertEqual(TouchPad.megaDriveButtonCount(rom: url), 3)
        data[401] = 0x36
        try data.write(to: url)
        XCTAssertEqual(TouchPad.megaDriveButtonCount(rom: url), 6)
        try Data().write(to: url)
        XCTAssertEqual(TouchPad.megaDriveButtonCount(rom: url), 6)
    }
}
