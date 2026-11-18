import Foundation

struct FolderScanResult {
    var games: [Game]
    var ignored: Int
}

enum FolderScanner {
    static func scan(folder: GameFolder, root: URL, catalogue: GameCatalogue = .shared) throws -> FolderScanResult {
        let fm = FileManager.default
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        var failure: Error?
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, error in failure = error; return false }) else {
            throw NSError(domain: "FolderScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open this folder. Choose it again in Files."])
        }
        var games: [Game] = [], lists: [URL] = [], ignored = 0, visited = 0
        for case let file as URL in enumerator {
            visited += 1
            if visited > 200_000 { throw NSError(domain: "FolderScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "This folder is too large to scan at once. Add individual system folders instead."]) }
            let values = try file.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isDirectory == true && ["bios", "system", "support", "artwork", "covers", "images", "media", "saves"].contains(file.lastPathComponent.lowercased()) { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            if file.lastPathComponent.lowercased() == "gamelist.xml" { lists.append(file); continue }
            let rootParts = root.standardizedFileURL.pathComponents
            let fileParts = file.standardizedFileURL.pathComponents
            guard fileParts.starts(with: rootParts) else { continue }
            let relative = fileParts.dropFirst(rootParts.count).joined(separator: "/")
            guard LibraryRules.safeRelativePath(relative) else { continue }
            let system = folder.detectSystems == true ? GameSystem.detect(rootName: root.lastPathComponent, relativePath: relative) : folder.system
            guard let system, GameSystem.recognises(relative, for: system) else { ignored += 1; continue }
            games.append(catalogue.identify(Game(title: "", system: system, relativePath: relative, folderID: folder.id)))
        }
        if let failure { throw failure }
        var metadata: [String: GamelistEntry] = [:]
        for list in lists {
            for entry in GamelistReader.read(list, root: root) { metadata[entry.path] = entry }
        }
        for i in games.indices {
            guard let entry = metadata[games[i].relativePath] else { continue }
            if !entry.name.isEmpty { games[i].title = entry.name; games[i].catalogueTitle = entry.name }
            if !entry.summary.isEmpty { games[i].summary = String(entry.summary.prefix(2000)) }
            if !entry.maker.isEmpty { games[i].maker = entry.maker }
            if !entry.year.isEmpty { games[i].year = String(entry.year.prefix(4)) }
            games[i].localArtworkPath = entry.image
        }
        return FolderScanResult(games: games, ignored: ignored)
    }
    static func merge(_ scanned: [Game], into existing: inout [Game]) -> Int {
        // O(n), preserving save IDs, favourites and manually chosen titles/covers.
        func key(_ game: Game) -> String { "\(game.folderID?.uuidString ?? "")|\(game.system.rawValue)|\(game.relativePath)" }
        var index = Dictionary(existing.enumerated().map { (key($0.element), $0.offset) }, uniquingKeysWith: { a, _ in a })
        var added = 0
        for var game in scanned {
            if let i = index[key(game)] {
                let old = existing[i]
                game.id = old.id; game.customTitle = old.customTitle; game.artwork = old.artwork
                existing[i] = game
            } else { index[key(game)] = existing.count; existing.append(game); added += 1 }
        }
        return added
    }
}

struct GamelistEntry {
    var path = "", name = "", summary = "", maker = "", year = ""
    var image: String?
}

final class GamelistReader: NSObject, XMLParserDelegate {
    private var entries: [GamelistEntry] = []
    private var values: [String: String] = [:]
    private var tag = ""
    private var inside = false
    private let directory: URL
    private let root: URL
    init(directory: URL, root: URL) { self.directory = directory; self.root = root }
    static func read(_ file: URL, root: URL) -> [GamelistEntry] {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 10_000_000,
              let data = try? Data(contentsOf: file) else { return [] }
        let reader = GamelistReader(directory: file.deletingLastPathComponent(), root: root)
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = reader
        return parser.parse() ? reader.entries : []
    }
    private func relative(_ text: String) -> String? {
        guard !text.isEmpty, !text.hasPrefix("/"), !text.contains("://"), !text.contains("\\") else { return nil }
        let target = directory.appendingPathComponent(text).standardizedFileURL.resolvingSymlinksInPath()
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard target.pathComponents.starts(with: base) else { return nil }
        let path = target.pathComponents.dropFirst(base.count).joined(separator: "/")
        return LibraryRules.safeRelativePath(path) ? path : nil
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        tag = elementName
        if tag == "game" { inside = true; values = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inside { values[tag, default: ""] += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "game" {
            if let path = relative(values["path", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)) {
                entries.append(GamelistEntry(path: path, name: values["name", default: ""].trimmingCharacters(in: .whitespacesAndNewlines), summary: values["desc", default: ""], maker: values["publisher"] ?? values["developer"] ?? "", year: values["releasedate", default: ""], image: relative(values["image", default: ""].trimmingCharacters(in: .whitespacesAndNewlines))))
            }
            inside = false
        }
        tag = ""
    }
}
