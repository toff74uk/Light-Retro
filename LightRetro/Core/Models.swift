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
        case .fbneo: return "Only arcade set names on Light Retro Android’s FBNeo list appear here. Keep the original archive names and place parent sets and BIOS ZIPs beside the games."
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
    static func namedFolder(rootName: String, relativePath: String) -> GameSystem? {
        let parts = relativePath.split(separator: "/").dropLast().map(String.init)
        for name in ([rootName] + parts).reversed() {
            let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
            if let system = playable.first(where: { $0.aliases.contains(key) }) { return system }
        }
        return nil
    }
    static func detect(rootName: String, relativePath: String) -> GameSystem? {
        if let system = namedFolder(rootName: rootName, relativePath: relativePath) {
            return recognises(relativePath, for: system) ? system : nil
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
    // Older automatic-folder entries may already have save states from another core.
    var originalSaveSystem: GameSystem?
    var hasMAMEDisc: Bool?
    var isArcadeDiscCompanion: Bool?
    mutating func preserveSaves(from previous: Game) {
        originalSaveSystem = previous.originalSaveSystem ?? (previous.system == system ? nil : previous.system)
    }
    var alternateSaveFolder: String? {
        guard let originalSaveSystem, originalSaveSystem != system else { return nil }
        return system.rawValue
    }
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

enum ControlResponse: String, CaseIterable, Codable {
    case steady = "Steady", standard = "Standard", quick = "Quick"

    var deadZone: Float {
        switch self { case .steady: return 0.24; case .standard: return 0.12; case .quick: return 0.06 }
    }
    var digitalThreshold: Float {
        switch self { case .steady: return 0.65; case .standard: return 0.5; case .quick: return 0.33 }
    }
    func stick(x: Float, y: Float) -> (Float, Float) {
        let length = hypot(x, y)
        guard length > deadZone else { return (0, 0) }
        let magnitude = (min(1, length) - deadZone) / (1 - deadZone)
        let gain: Float
        switch self { case .steady: gain = magnitude * magnitude; case .standard: gain = magnitude; case .quick: gain = sqrt(magnitude) }
        return (x * gain / length, y * gain / length)
    }
    func touchDirections(x: Float, y: Float) -> Set<Int> {
        guard hypot(x, y) > deadZone else { return [] }
        var directions = Set<Int>()
        if abs(x) >= abs(y) * 0.5 { directions.insert(x < 0 ? 6 : 7) }
        if abs(y) >= abs(x) * 0.5 { directions.insert(y < 0 ? 4 : 5) }
        return directions
    }
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
    var systemOrder: [String]?
    // Optional profile preference: nil preserves the original two-column layout.
    var showCategoryColumn: Bool?
    var screensaverMinutes: Int?
    var controlResponse: ControlResponse?
    var largeTouchButtons: Bool?
    var arcadeTouchButtons: [String: Int]?

    var orderedSystems: [GameSystem] {
        let playable = GameSystem.playable
        guard let systemOrder else { return playable }
        var remaining = Set(playable)
        let saved = systemOrder.compactMap(GameSystem.init(rawValue:)).filter { remaining.remove($0) != nil }
        return saved + playable.filter { remaining.contains($0) }
    }

    mutating func moveSystem(_ system: GameSystem, offset: Int) {
        var systems = orderedSystems
        guard let index = systems.firstIndex(of: system),
              systems.indices.contains(index + offset) else { return }
        systems.swapAt(index, index + offset)
        systemOrder = systems.map(\.rawValue)
    }

    func touchButtonOverride(for game: Game) -> Int? {
        guard game.system.isArcade, let count = arcadeTouchButtons?[game.romStem.lowercased()],
              (2...6).contains(count) else { return nil }
        return count
    }
    mutating func setTouchButtonOverride(_ count: Int?, for game: Game) {
        guard game.system.isArcade else { return }
        let key = game.romStem.lowercased()
        if let count, (2...6).contains(count) {
            if arcadeTouchButtons == nil { arcadeTouchButtons = [:] }
            arcadeTouchButtons?[key] = count
        } else {
            arcadeTouchButtons?.removeValue(forKey: key)
        }
    }
}

struct LibraryData: Codable {
    var version = 1
    var games: [Game] = []
    var folders: [GameFolder] = []
    var profiles = [PlayerProfile(name: "Player 1")]
    var currentProfile: UUID?
    var downloadArtwork: Bool?
}

struct LibraryPage {
    static let size = 200
    let count: Int
    let index: Int
    let games: ArraySlice<Game>

    init(_ results: [Game], index requestedIndex: Int) {
        count = max(1, (results.count + Self.size - 1) / Self.size)
        index = min(max(0, requestedIndex), count - 1)
        games = results.dropFirst(index * Self.size).prefix(Self.size)
    }
}

enum LibraryRules {
    static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") &&
        !path.split(separator: "/").contains("..") && !path.contains("\0")
    }
    static func displayName(_ filename: String) -> String {
        let stem = ((filename as NSString).lastPathComponent as NSString).deletingPathExtension
        return cleanTitle(stem)
    }
    static func cleanTitle(_ title: String) -> String {
        // Catalogue titles are *not* file paths. Preserve "/" characters in titles and dates.
        let clean = title.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s*\((?:USA|US|Europe|Japan|World|U|E|J|Rev|En|Proto|Beta)\b[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? title : clean
    }
    static func upsert(_ candidate: Game, in games: inout [Game]) {
        if games.contains(where: { $0.folderID == candidate.folderID && $0.relativePath == candidate.relativePath && $0.system == candidate.system }) { return }
        games.append(candidate)
    }
}
