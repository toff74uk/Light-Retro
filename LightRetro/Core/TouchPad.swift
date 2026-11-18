import Foundation

struct PadButton {
    enum Input: Hashable { case digital(Int), cDirection(Int) }
    let label: String
    let input: Input
    let column: CGFloat
    let row: CGFloat

    init(_ label: String, _ id: Int, _ column: CGFloat, _ row: CGFloat, cButton: Bool = false) {
        self.label = label
        input = cButton ? .cDirection(id) : .digital(id)
        self.column = column
        self.row = row
    }
}

enum TouchPad {
    // MAME 0.289's default player-one assignments, in cabinet button order.
    static let mame = [0, 8, 1, 9, 10, 11]
    static let fbneoClassic = [0, 8, 1, 9, 11, 10]

    static func face(system: GameSystem, count: Int, fbneoInputs: [Int]) -> [PadButton] {
        switch system {
        case .arcade, .fbneo:
            let count = min(6, max(2, count))
            var inputs = system == .arcade ? mame : fbneoInputs
            for id in fbneoClassic where !inputs.contains(id) { inputs.append(id) }
            let columns = count == 4 ? 2 : 3
            return (0..<count).map {
                PadButton(String($0 + 1), inputs[$0], CGFloat($0 % columns), CGFloat($0 / columns))
            }
        case .nes:
            return [PadButton("B", 0, 0, 0), PadButton("A", 8, 1, 0)]
        case .snes:
            return [PadButton("X", 9, 1, 0), PadButton("Y", 1, 0, 1),
                    PadButton("A", 8, 2, 1), PadButton("B", 0, 1, 2)]
        case .mega:
            let six = count == 6
            let abc = [PadButton("A", 1, 0, six ? 1 : 0), PadButton("B", 0, 1, six ? 1 : 0),
                       PadButton("C", 8, 2, six ? 1 : 0)]
            return six ? [PadButton("X", 10, 0, 0), PadButton("Y", 9, 1, 0), PadButton("Z", 11, 2, 0)] + abc : abc
        case .pce, .pcecd:
            return [PadButton("II", 0, 0, 0), PadButton("I", 8, 1, 0)]
        case .n64:
            return [PadButton("B", 1, 0, 1.3), PadButton("A", 0, 0.75, 2.2),
                    PadButton("C↑", 4, 1.9, 0, cButton: true), PadButton("C←", 6, 1, 0.9, cButton: true),
                    PadButton("C→", 7, 2.8, 0.9, cButton: true), PadButton("C↓", 5, 1.9, 1.8, cButton: true)]
        case .scumm:
            return []
        }
    }

    static func megaDriveButtonCount(rom: URL) -> Int {
        // Genesis Plus GX uses '6' in the cartridge's peripheral field. Show the
        // full pad for interleaved/headerless dumps whose header we cannot read.
        guard let file = try? FileHandle(forReadingFrom: rom) else { return 6 }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 414), header.count == 414,
              header[256..<260].elementsEqual("SEGA".utf8) else { return 6 }
        return header[400..<414].contains(0x36) ? 6 : 3
    }
}
