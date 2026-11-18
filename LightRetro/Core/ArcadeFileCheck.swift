import Foundation
import ZIPFoundation

enum ArcadeFileCheck {
    // Parent CD sets from the bundled MAME 0.289 driver.
    static let streetFighterBIOS: [String: (name: String, crc: UInt32)] = [
        "sfiii": ("sfiii_euro.29f400.u2", 0x27699ddc),
        "sfiii2": ("sfiii2_usa.29f400.u2", 0x75dd72e0),
        "sfiii3": ("sfiii3_euro.29f400.u2", 0x30bbf293)
    ]

    static func report(game: Game, archive: URL, set: ArcadeDiscSet) -> String {
        var lines = ["Selected emulator: \(game.system.title)", "Archive: \(game.fileName)"]
        if let bios = streetFighterBIOS[game.romStem.lowercased()], archive.pathExtension.lowercased() == "zip" {
            do {
                let zip = try Archive(url: archive, accessMode: .read)
                // MAME accepts another entry name when the size and CRC match.
                if let entry = zip.first(where: { $0.type == .file && $0.uncompressedSize == 524288 && $0.checksum == bios.crc }) {
                    let crc = try zip.extract(entry, consumer: { _ in })
                    lines.append(crc == bios.crc ? "BIOS verified: \(bios.name)" : "BIOS checksum mismatch: \(bios.name)")
                } else { lines.append("Expected BIOS missing or incorrect: \(bios.name)") }
            } catch { lines.append("Could not read the BIOS from \(game.fileName).") }
        }
        for (hash, entries) in Dictionary(grouping: set.discs, by: { $0.value }).sorted(by: { $0.key < $1.key }) {
            let names = entries.map(\.key).sorted()
            if let file = names.compactMap({ set.find($0, beside: archive) }).first {
                lines.append(discResult(file, expected: hash))
            } else {
                let name = names[0] + ".chd"
                let directories = [game.romStem] + (set.parents ?? [])
                lines.append("Missing \(name). Looked in " + directories.joined(separator: ", ") + ".")
            }
        }
        if game.folderID == nil {
            lines.append("This archive was imported on its own. Link the arcade folder containing the ZIP and the CHD subfolder.")
        }
        return lines.joined(separator: "\n")
    }

    static func discResult(_ file: URL, expected: String) -> String {
        let name = file.lastPathComponent
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 124) ?? Data()
            guard header.count >= 16, header.prefix(8).elementsEqual("MComprHD".utf8) else {
                return "Invalid CHD header: \(name)"
            }
            let version = header[12..<16].reduce(0) { $0 * 256 + Int($1) }
            // Big-endian CHD v4/v5 combined SHA-1 offsets from util/chd.h.
            let offset: Int
            let length: Int
            switch version {
            case 4: offset = 48; length = 108
            case 5: offset = 84; length = 124
            default: return "Found \(name) (CHD v\(version)). Disc ID was not checked."
            }
            let declared = header[8..<12].reduce(0) { $0 * 256 + Int($1) }
            guard declared == length, header.count >= length else { return "Incomplete CHD header: \(name)" }
            let actual = header[offset..<offset + 20].map { String(format: "%02x", $0) }.joined()
            return actual == expected ? "Disc header matches MAME: \(name)" : "Disc ID does not match MAME 0.289: \(name)"
        } catch { return "Could not read \(name): \(error.localizedDescription)" }
    }
}
