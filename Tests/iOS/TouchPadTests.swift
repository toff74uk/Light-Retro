import XCTest
@testable import LightRetro

final class TouchPadTests: XCTestCase {
    @MainActor func testIdleBeginsAfterLastTouchIncludingCentredStick() {
        let hub = ControllerHub()
        XCTAssertFalse(hub.touchingControls)
        hub.setStickContact(true)
        hub.moveTouchStick(x: 0, y: 0, mode: .analogue, response: .standard)
        XCTAssertTrue(hub.touchingControls)
        hub.setTouch(3, down: true)
        hub.setTouchC(4, down: true)
        hub.setStickContact(false)
        hub.setTouch(3, down: false)
        XCTAssertTrue(hub.touchingControls)
        hub.setTouchC(4, down: false)
        XCTAssertFalse(hub.touchingControls)
        hub.setStickContact(true)
        hub.clear()
        XCTAssertFalse(hub.touchingControls)
    }

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

    @MainActor func testStickAndTwoHeldButtonsReleaseIndependently() {
        let hub = ControllerHub()
        var port = GamepadState()
        hub.onGameInput = { port = $0[0] }
        hub.moveTouchStick(x: -0.8, y: 0.8, mode: .arcade, response: .standard)
        XCTAssertLessThan(port.sticks[0][0], 0)
        XCTAssertGreaterThan(port.sticks[0][1], 0)
        hub.setTouch(0, down: true)
        hub.setTouch(8, down: true)
        XCTAssertTrue(hub.pressed.isSuperset(of: [5, 6, 0, 8]))
        hub.setTouch(0, down: false)
        XCTAssertFalse(hub.pressed.contains(0))
        XCTAssertTrue(hub.pressed.isSuperset(of: [5, 6, 8]))
        hub.moveTouchStick(x: 0, y: 0, mode: .arcade, response: .standard)
        XCTAssertTrue(hub.pressed.isDisjoint(with: [4, 5, 6, 7]))
        XCTAssertTrue(hub.pressed.contains(8))
        hub.setTouch(8, down: false)
        hub.moveTouchStick(x: 0.5, y: 0, mode: .analogue, response: .standard)
        hub.setTouchC(4, down: true)
        XCTAssertGreaterThan(port.sticks[0][0], 0)
        XCTAssertEqual(port.sticks[1][1], -1)
        XCTAssertTrue(hub.pressed.isDisjoint(with: [4, 5, 6, 7]))
        hub.setTouchC(4, down: false)
        XCTAssertEqual(port.sticks[1][1], 0)
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
