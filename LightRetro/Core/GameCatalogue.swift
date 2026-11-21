import Foundation

struct GameCollection: Codable, Identifiable {
    var title: String
    var systems: [GameSystem]
    var roms: Set<String>
    var names: [String]
    // Optional so the original Android collections continue to decode unchanged.
    var titlePrefixes: [String]?
    var publisherPrefixes: [String]?
    var id: String { title }
    func contains(_ game: Game) -> Bool {
        guard systems.contains(game.system) else { return false }
        let title = GameCatalogue.normalise(game.displayTitle)
        let publisher = GameCatalogue.normalise(game.maker ?? "")
        return roms.contains(game.romStem.lowercased()) ||
            names.contains { GameCatalogue.normalise($0) == title } ||
            (titlePrefixes?.contains {
                let prefix = GameCatalogue.normalise($0)
                return title == prefix || title.hasPrefix(prefix + " ")
            } ?? false) ||
            (publisherPrefixes?.contains {
                let prefix = GameCatalogue.normalise($0)
                return !publisher.isEmpty && (publisher == prefix || publisher.hasPrefix(prefix + " "))
            } ?? false)
    }
}

struct ArcadeDiscSet: Decodable {
    let parents: [String]?
    // Filename without extension to MAME combined SHA-1. Clones can have aliases.
    let discs: [String: String]

    func locations(for name: String, beside archive: URL) -> [URL] {
        let stem = archive.deletingPathExtension().lastPathComponent
        let folders = [stem] + (stem == stem.lowercased() ? [] : [stem.lowercased()]) + (parents ?? [])
        let base = archive.deletingLastPathComponent()
        return folders.map { base.appendingPathComponent($0).appendingPathComponent(name + ".chd") }
    }
    func find(_ name: String, beside archive: URL) -> URL? {
        locations(for: name, beside: archive).first {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
    func hasCompanion(beside archive: URL) -> Bool {
        discs.keys.contains { find($0, beside: archive) != nil }
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
    let arcadeDiscs: [String: ArcadeDiscSet]
    private let discNamesByFolder: [String: Set<String>]
    let collections: [GameCollection]
    private let descriptions: [String: String]
    init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Catalogue")) {
        func read<T: Decodable>(_ name: String, as: T.Type, fallback: T) -> T {
            guard let url = directory?.appendingPathComponent(name), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
            return value
        }
        mame = read("mame-titles.json", as: [String: [String]].self, fallback: [:])
        fbneo = read("fbneo-titles.json", as: [String: String].self, fallback: [:])
        let discSets = read("arcade-discs.json", as: [String: ArcadeDiscSet].self, fallback: [:])
        arcadeDiscs = discSets
        var discNames: [String: Set<String>] = [:]
        for (stem, set) in discSets {
            for folder in [stem] + (set.parents ?? []) {
                discNames[folder, default: []].formUnion(set.discs.keys.map { $0.lowercased() + ".chd" })
            }
        }
        discNamesByFolder = discNames
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
    func discSet(for game: Game) -> ArcadeDiscSet? {
        game.system.isArcade ? arcadeDiscs[game.romStem.lowercased()] : nil
    }
    func isArcadeDisc(_ file: URL) -> Bool {
        let folder = file.deletingLastPathComponent().lastPathComponent.lowercased()
        return discNamesByFolder[folder]?.contains(file.lastPathComponent.lowercased()) == true
    }

    func arcadeButtonCount(for game: Game) -> Int { buttonCountBySet[game.romStem.lowercased()] ?? 6 }

    func fbneoBoard(for game: Game) -> String? { boardBySet[game.romStem.lowercased()] }

    func isListed(_ game: Game) -> Bool {
        game.isArcadeDiscCompanion != true && (game.system != .fbneo || fbneoBoard(for: game) != nil)
    }

    func routeAutomaticArcade(_ game: inout Game) {
        guard game.system.isArcade, !boardBySet.isEmpty else { return }
        game.system = game.hasMAMEDisc == true || fbneoBoard(for: game) == nil ? .arcade : .fbneo
    }

    func updateExistingArcadeRoutes(in library: inout LibraryData) {
        let automatic = Dictionary(library.folders.filter { $0.detectSystems == true }.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for index in library.games.indices {
            var game = library.games[index]
            guard let folder = game.folderID, let root = automatic[folder] else { continue }
            if game.system == .pcecd, game.fileName.lowercased().hasSuffix(".chd") {
                // Older mixed scans listed loose arcade discs as playable PC Engine CD titles.
                let path = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(game.relativePath)
                let named = GameSystem.namedFolder(rootName: root, relativePath: game.relativePath)
                if named != .pcecd && isArcadeDisc(path) { library.games[index].isArcadeDiscCompanion = true }
                continue
            }
            guard game.system.isArcade else { continue }
            let previous = game.system
            routeAutomaticArcade(&game)
            if game.system != previous {
                game.originalSaveSystem = game.originalSaveSystem ?? previous
                library.games[index] = game
            }
        }
    }
    static func displayTitle(canonical: String?, fileName: String) -> String {
        // Canonical arcade names are labels, not paths: they can contain "/" (e.g. dates).
        guard let canonical, !canonical.isEmpty else { return LibraryRules.displayName(fileName) }
        return LibraryRules.cleanTitle(canonical)
    }

    static func repairLegacyArcadeTitle(_ source: Game) -> Game {
        // Previously the catalogue title was passed through NSString.lastPathComponent.
        // Repair only that exact legacy result, leaving custom titles and imported metadata alone.
        var game = source
        guard game.system.isArcade, let canonical = game.catalogueTitle,
              canonical.contains("/"),
              game.title == LibraryRules.displayName(canonical + ".rom") else { return game }
        game.title = displayTitle(canonical: canonical, fileName: game.fileName)
        return game
    }

    func identify(_ source: Game) -> Game {
        var game = source
        let key = game.romStem.lowercased()
        let record = game.system.isArcade ? mame[key] : nil
        let canonical = game.system == .fbneo ? (fbneo[key] ?? record?.first) : record?.first
        game.catalogueTitle = canonical
        // Keep revision information in catalogueTitle for artwork and the details page.
        game.title = Self.displayTitle(canonical: canonical, fileName: game.fileName)
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
