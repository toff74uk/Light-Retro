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
        case .nes: return ["nes", "unf", "unif"]
        case .n64: return ["n64", "v64", "z64"]
        case .snes: return ["sfc", "smc", "fig"]
        case .mega: return ["md", "gen", "smd", "bin"]
        case .pce: return ["pce", "bin"]
        case .pcecd: return ["cue", "chd", "ccd"]
        case .scumm: return ["scummvm"]
        }
    }
    var help: String {
        switch self {
        case .arcade: return "Use MAME 0.289 sets. Link the complete arcade folder so parent and BIOS ZIPs stay together; keep each CHD in its matching game subfolder. Start the game ZIP, not the CHD."
        case .n64: return "Use uncompressed .z64, .n64 or .v64 ROMs. Left stick moves, right stick controls C buttons, left trigger is Z. Runs without JIT; demanding games may be slow."
        case .scumm: return "SCUMM engine and pointer controls are planned for a later build."
        case .fbneo: return "Use a matching FBNeo ROM set. Keep parent sets and required BIOS ZIPs in the same linked folder."
        case .pcecd: return "Link a folder containing your disc and all its tracks. Import your syscard3.pce BIOS in Settings."
        default: return "Use uncompressed ROMs. Unzip console ZIPs in Files before adding them."
        }
    }
    static func recognises(_ name: String, for system: GameSystem) -> Bool {
        let components = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
        guard !components.contains(where: { ["bios", "system", "support", "artwork", "covers"].contains($0.lowercased()) }),
              components.last?.lowercased() != "syscard3.pce" else { return false }
        return system.extensions.contains((name as NSString).pathExtension.lowercased())
    }
}

struct Game: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var system: GameSystem
    var relativePath: String
    var folderID: UUID?
    var artwork: String?
}

struct GameFolder: Identifiable, Codable {
    var id = UUID()
    var name: String
    var system: GameSystem
    var bookmark: Data
}

struct PlayerProfile: Identifiable, Codable {
    var id = UUID()
    var name: String
    var favourites: Set<UUID> = []
    var recent: [UUID: Date] = [:]
    var theme = "orange"
    var leftHanded = false
}

struct LibraryData: Codable {
    var version = 1
    var games: [Game] = []
    var folders: [GameFolder] = []
    var profiles = [PlayerProfile(name: "Player 1")]
    var currentProfile: UUID?
}

enum LibraryRules {
    static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") &&
        !path.split(separator: "/").contains("..") && !path.contains("\0")
    }
    static func displayName(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
    }
    static func upsert(_ candidate: Game, in games: inout [Game]) {
        if games.contains(where: { $0.folderID == candidate.folderID && $0.relativePath == candidate.relativePath && $0.system == candidate.system }) { return }
        games.append(candidate)
    }
}
