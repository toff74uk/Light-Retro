import Foundation

struct GameCollection: Codable, Identifiable {
    var title: String
    var systems: [GameSystem]
    var roms: Set<String>
    var names: [String]
    var id: String { title }
    func contains(_ game: Game) -> Bool {
        systems.contains(game.system) && (roms.contains(game.romStem.lowercased()) || names.contains { GameCatalogue.normalise($0) == GameCatalogue.normalise(game.displayTitle) })
    }
}

/// The Android 2.10 catalogues are bundled: arcade names never require an upload.
final class GameCatalogue {
    static let shared = GameCatalogue()
    let mame: [String: [String]]
    let fbneo: [String: String]
    static let fbneoBoards = ["CPS-1", "CPS-2", "CPS-3", "Neo Geo", "Other"]
    private let boardBySet: [String: String]
    private let buttonCountBySet: [String: Int]
    let collections: [GameCollection]
    private let descriptions: [String: String]
    init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Catalogue")) {
        func read<T: Decodable>(_ name: String, as: T.Type, fallback: T) -> T {
            guard let url = directory?.appendingPathComponent(name), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
            return value
        }
        mame = read("mame-titles.json", as: [String: [String]].self, fallback: [:])
        fbneo = read("fbneo-titles.json", as: [String: String].self, fallback: [:])
        let buttonGroups = read("arcade-buttons.json", as: [String: [String]].self, fallback: [:])
        var counts: [String: Int] = [:]
        for (group, sets) in buttonGroups {
            guard let count = Int(group), (2...5).contains(count) else { continue }
            for stem in sets { counts[stem] = count }
        }
        buttonCountBySet = counts
        let boards = read("fbneo-boards.json", as: [String: [String]].self, fallback: [:])
        var boardBySet: [String: String] = [:]
        for (board, names) in boards {
            for name in names { boardBySet[name] = board }
        }
        self.boardBySet = boardBySet
        collections = read("collections.json", as: [GameCollection].self, fallback: [])
        descriptions = read("descriptions.json", as: [String: String].self, fallback: [:])
    }
    func arcadeButtonCount(for game: Game) -> Int { buttonCountBySet[game.romStem.lowercased()] ?? 6 }

    func fbneoBoard(for game: Game) -> String? { boardBySet[game.romStem.lowercased()] }

    func isListed(_ game: Game) -> Bool { game.system != .fbneo || fbneoBoard(for: game) != nil }

    func routeAutomaticArcade(_ game: inout Game) {
        guard game.system.isArcade, !boardBySet.isEmpty else { return }
        game.system = fbneoBoard(for: game) == nil ? .arcade : .fbneo
    }

    func updateExistingArcadeRoutes(in library: inout LibraryData) {
        let automatic = Set(library.folders.filter { $0.detectSystems == true }.map(\.id))
        for index in library.games.indices {
            var game = library.games[index]
            guard game.system.isArcade, let folder = game.folderID, automatic.contains(folder) else { continue }
            let previous = game.system
            routeAutomaticArcade(&game)
            if game.system != previous {
                game.originalSaveSystem = game.originalSaveSystem ?? previous
                library.games[index] = game
            }
        }
    }
    func identify(_ source: Game) -> Game {
        var game = source
        let key = game.romStem.lowercased()
        let record = game.system.isArcade ? mame[key] : nil
        let canonical = game.system == .fbneo ? (fbneo[key] ?? record?.first) : record?.first
        game.catalogueTitle = canonical
        // Keep revision information in catalogueTitle for artwork and the details page.
        game.title = canonical.map { LibraryRules.displayName($0 + ".rom") } ?? LibraryRules.displayName(game.fileName)
        game.year = record.flatMap { $0.count > 1 ? $0[1] : nil }
        game.maker = record.flatMap { $0.count > 2 ? $0[2] : nil }
        let family = game.system.isArcade ? "arcade" : game.system.rawValue
        game.summary = descriptions[family + "|" + Self.normalise(game.title)]
        return game
    }
    func search(_ query: String, system: GameSystem) -> [(id: String, title: String)] {
        guard system.isArcade, query.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        let key = Self.normalise(query)
        let records = system == .fbneo ? fbneo : mame.compactMapValues(\.first)
        return records.filter { $0.key == query.lowercased() || Self.normalise($0.value).contains(key) }
            .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }.prefix(40).map { ($0.key, $0.value) }
    }
    static func normalise(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    static func artworkNames(_ game: Game) -> [String] {
        let names = [game.customTitle, game.catalogueTitle, Optional(game.romStem), Optional(game.title)].compactMap { $0 }
        let regional = game.system.isArcade ? [] : names.filter { !$0.contains("(") }.prefix(2).flatMap { name in ["\(name) (USA)", "\(name) (Europe)", "\(name) (Japan)"] }
        var seen = Set<String>()
        return (names + regional).map { $0.replacingOccurrences(of: #"[&*/:`<>?\\|\"]"#, with: "_", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count < 240 && seen.insert($0).inserted }
    }
    static func artworkSystems(_ system: GameSystem) -> [String] {
        switch system {
        case .arcade, .fbneo: return system == .arcade ? ["MAME", "FBNeo - Arcade Games"] : ["FBNeo - Arcade Games", "MAME"]
        case .nes: return ["Nintendo - Nintendo Entertainment System"]
        case .n64: return ["Nintendo - Nintendo 64"]
        case .snes: return ["Nintendo - Super Nintendo Entertainment System"]
        case .mega: return ["Sega - Mega Drive - Genesis"]
        case .pce: return ["NEC - PC Engine - TurboGrafx 16"]
        case .pcecd: return ["NEC - PC Engine CD - TurboGrafx-CD"]
        case .scumm: return []
        }
    }
    static func artworkURLs(_ game: Game) -> [URL] {
        let kinds = game.system.isArcade ? ["Named_Boxarts", "Named_Titles", "Named_Snaps"] : ["Named_Boxarts"]
        return kinds.flatMap { kind in artworkSystems(game.system).flatMap { system in artworkNames(game).map { name in
            URL(string: "https://thumbnails.libretro.com")!.appendingPathComponent(system).appendingPathComponent(kind).appendingPathComponent(name + ".png")
        } } }
    }
}
