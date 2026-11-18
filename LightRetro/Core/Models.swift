import Foundation

enum GameSystem: String, Codable, CaseIterable, Identifiable {
    case arcade, fbneo, nes, n64, snes, mega, pce, pcecd, scumm
    var id: String { rawValue }
    var title: String {
        switch self {
        case .arcade: return "MAME / Arcade"
        case .fbneo: return "FinalBurn Neo"
        case .nes: return "NES"
        case .n64: return "Nintendo 64"
        case .snes: return "Super Nintendo"
        case .mega: return "Mega Drive"
        case .pce: return "PC Engine"
        case .pcecd: return "PC Engine CD"
        case .scumm: return "SCUMM Adventures"
        }
    }
    var core: String? {
        switch self {
        case .arcade: return "mamearcade"
        case .n64: return "mupen64plus_next"
        case .nes: return "fceumm"
        case .snes: return "snes9x"
        case .mega: return "genesis_plus_gx"
        case .pce, .pcecd: return "mednafen_pce_fast"
        case .fbneo: return "fbneo"
        default: return nil
        }
    }
    var extensions: Set<String> {
        switch self {
        case .arcade, .fbneo: return ["zip", "7z"]
        case .nes: return ["nes", "unf", "unif", "zip"]
        case .n64: return ["n64", "v64", "z64", "zip"]
        case .snes: return ["sfc", "smc", "fig", "zip"]
        case .mega: return ["md", "gen", "smd", "bin", "zip"]
        case .pce: return ["pce", "bin", "zip"]
        case .pcecd: return ["cue", "chd", "ccd"]
        case .scumm: return ["scummvm"]
        }
    }
    var help: String {
        switch self {
        case .arcade: return "Use MAME 0.289 sets. Link the complete arcade folder so parent and BIOS ZIPs stay together; keep each CHD in its matching game subfolder. Start the game ZIP, not the CHD."
        case .n64: return "Use .z64, .n64 or .v64 ROMs, or a ZIP containing one ROM. Left stick moves, right stick controls C buttons, left trigger is Z. Runs without JIT; demanding games may be slow."
        case .scumm: return "SCUMM engine and pointer controls are planned for a later build."
        case .fbneo: return "Use a matching FBNeo ROM set. Keep parent sets and required BIOS ZIPs in the same linked folder."
        case .pcecd: return "Link a folder containing your disc and all its tracks. Import your syscard3.pce BIOS in Settings."
        default: return "Add ROMs or ZIPs containing one game. Folder contents stay in place; a zipped console game is temporarily unpacked when played."
        }
    }
    static func recognises(_ name: String, for system: GameSystem) -> Bool {
        let components = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
        guard !components.contains(where: { ["bios", "system", "support", "artwork", "covers"].contains($0.lowercased()) }),
              components.last?.lowercased() != "syscard3.pce" else { return false }
        let stem = ((name as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        if system == .arcade || system == .fbneo, ["neogeo", "pgm", "cps3", "qsound", "naomi", "awbios", "stvbios", "skns", "cchip", "decocass", "aristmk5"].contains(stem) { return false }
        return system.extensions.contains((name as NSString).pathExtension.lowercased())
    }
    var isArcade: Bool { self == .arcade || self == .fbneo }
    static var playable: [GameSystem] { allCases.filter { $0.core != nil } }
    var aliases: Set<String> {
        switch self {
        case .arcade: return ["mame", "arcade", "arcades"]
        case .fbneo: return ["fbneo", "finalburnneo", "fbn"]
        case .nes: return ["nes", "nintendo", "famicom", "nintendoentertainmentsystem"]
        case .n64: return ["n64", "nintendo64"]
        case .snes: return ["snes", "supernintendo", "superfamicom", "sfc"]
        case .mega: return ["mega", "megadrive", "genesis", "segagenesis", "segamegadrivegenesis"]
        case .pce: return ["pce", "pcengine", "turbografx", "turbografx16", "tg16"]
        case .pcecd: return ["pcecd", "pcenginecd", "turbografxcd", "tgcd", "tg16cd"]
        case .scumm: return ["scumm", "scummvm"]
        }
    }
    static func detect(rootName: String, relativePath: String) -> GameSystem? {
        let parts = relativePath.split(separator: "/").dropLast().map(String.init)
        for name in ([rootName] + parts).reversed() {
            let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
            if let system = playable.first(where: { $0.aliases.contains(key) }) {
                return recognises(relativePath, for: system) ? system : nil
            }
        }
        let ext = (relativePath as NSString).pathExtension.lowercased()
        let system: GameSystem?
        switch ext {
        case "nes", "unf", "unif": system = .nes
        case "n64", "v64", "z64": system = .n64
        case "sfc", "smc", "fig": system = .snes
        case "md", "gen", "smd": system = .mega
        case "pce": system = .pce
        case "cue", "ccd", "chd": system = .pcecd
        case "zip", "7z": system = .arcade
        default: system = nil
        }
        return system.flatMap { recognises(relativePath, for: $0) ? $0 : nil }
    }
}

struct Game: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var system: GameSystem
    var relativePath: String
    var folderID: UUID?
    var artwork: String?
    var catalogueTitle: String?
    var year: String?
    var maker: String?
    var summary: String?
    var customTitle: String?
    var localArtworkPath: String?
    var fileName: String { (relativePath as NSString).lastPathComponent }
    var romStem: String { (fileName as NSString).deletingPathExtension }
    var displayTitle: String { customTitle ?? title }
    var collectionFolder: String { folderID == nil ? "Imported files" : ((relativePath as NSString).deletingLastPathComponent.isEmpty ? "Root folder" : (relativePath as NSString).deletingLastPathComponent) }
}

struct GameFolder: Identifiable, Codable {
    var id = UUID()
    var name: String
    var system: GameSystem
    var bookmark: Data
    var detectSystems: Bool?
    var subtitle: String { detectSystems == true ? "All systems · automatic detection" : system.title }
}

struct PlayerProfile: Identifiable, Codable {
    var id = UUID()
    var name: String
    var favourites: Set<UUID> = []
    var recent: [UUID: Date] = [:]
    var theme = "orange"
    var leftHanded = false
    // Optional additions preserve all libraries saved by 0.1/0.2.
    var compactTiles: Bool?
    var colourHex: String?
    var colourStrength: Double?
    var brightness: Double?
    var darkText: Bool?
    var hiddenSystems: Set<GameSystem>?
    var screensaverMinutes: Int?
}

struct LibraryData: Codable {
    var version = 1
    var games: [Game] = []
    var folders: [GameFolder] = []
    var profiles = [PlayerProfile(name: "Player 1")]
    var currentProfile: UUID?
    var downloadArtwork: Bool?
}

enum LibraryRules {
    static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") &&
        !path.split(separator: "/").contains("..") && !path.contains("\0")
    }
    static func displayName(_ filename: String) -> String {
        let stem = ((filename as NSString).lastPathComponent as NSString).deletingPathExtension
        let clean = stem.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s*\((?:USA|Europe|Japan|World|U|E|J|Rev\b|En\b|Proto\b|Beta\b)[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? stem : clean
    }
    static func upsert(_ candidate: Game, in games: inout [Game]) {
        if games.contains(where: { $0.folderID == candidate.folderID && $0.relativePath == candidate.relativePath && $0.system == candidate.system }) { return }
        games.append(candidate)
    }
}
