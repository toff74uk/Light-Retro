import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class LibraryStore: ObservableObject {
    @Published var data = LibraryData()
    @Published var error: String?
    @Published var busy = false
    @Published var scanStatus = ""
    @Published var artworkRevision = 0
    let root: URL
    private let fm = FileManager.default
    private var writable = true
    var gamesURL: URL { root.appendingPathComponent("Games", isDirectory: true) }
    var biosURL: URL { root.appendingPathComponent("BIOS", isDirectory: true) }
    var savesURL: URL { root.appendingPathComponent("Saves", isDirectory: true) }
    var artworkURL: URL { root.appendingPathComponent("Artwork", isDirectory: true) }
    var profileIndex: Int { data.profiles.firstIndex { $0.id == data.currentProfile } ?? 0 }
    var profile: PlayerProfile { data.profiles[profileIndex] }
    var tint: Color {
        switch profile.theme { case "blue": return .cyan; case "pink": return .pink; case "yellow": return .yellow; default: return Color(red: 1, green: 0.38, blue: 0.15) }
    }
    init() {
        #if DEBUG
        let preview = ProcessInfo.processInfo.arguments.contains("--ui-preview")
        root = preview ? fm.temporaryDirectory.appendingPathComponent("LightRetro-UITests") : fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #else
        root = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        do {
            for folder in [gamesURL, biosURL, savesURL, artworkURL] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
            let file = root.appendingPathComponent("library.json")
            if fm.fileExists(atPath: file.path) {
                let decoded = try JSONDecoder().decode(LibraryData.self, from: Data(contentsOf: file))
                guard decoded.version == 1 else { throw StoreError.message("This library needs a newer version of Light Retro.") }
                var restored = decoded
                if restored.profiles.isEmpty { restored.profiles = [PlayerProfile(name: "Player 1")] }
                if !restored.profiles.contains(where: { $0.id == restored.currentProfile }) {
                    restored.currentProfile = restored.profiles[0].id
                }
                data = restored
                GameCatalogue.shared.updateExistingArcadeRoutes(in: &data)
                for i in data.games.indices {
                    if data.games[i].catalogueTitle == nil {
                        data.games[i] = GameCatalogue.shared.identify(data.games[i])
                    } else {
                        data.games[i] = GameCatalogue.repairLegacyArcadeTitle(data.games[i])
                    }
                }
            }
        } catch { writable = false; self.error = "Could not read your library. Your files are still in Files → Light Retro. \(error.localizedDescription)" }
        #if DEBUG
        if preview {
            writable = false // The UI fixture never writes a real user library.
            data = LibraryData(); data.downloadArtwork = false
            data.games = [Game(title: "", system: .arcade, relativePath: "sf2.zip"), Game(title: "", system: .arcade, relativePath: "dkong.zip"), Game(title: "", system: .n64, relativePath: "Super Mario 64 (USA).z64"), Game(title: "", system: .snes, relativePath: "Super Mario World (USA).sfc"), Game(title: "", system: .mega, relativePath: "Sonic the Hedgehog (USA).md")].map { GameCatalogue.shared.identify($0) }
            data.profiles[0].name = "Player 1"
            data.profiles[0].favourites.insert(data.games[0].id)
        }
        #endif
    }
    func persist() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") { return }
        #endif
        guard writable else { error = "Your existing library could not be read. Back up library.json in Files before repairing it; it has not been overwritten."; return }
        do { try JSONEncoder().encode(data).write(to: root.appendingPathComponent("library.json"), options: .atomic) }
        catch { self.error = "Could not save the library: \(error.localizedDescription)" }
    }
    func updateProfile(_ change: (inout PlayerProfile) -> Void) {
        let index = profileIndex
        change(&data.profiles[index])
        persist()
    }
    func selectProfile(_ id: UUID) {
        guard data.profiles.contains(where: { $0.id == id }) else { return }
        data.currentProfile = id
        persist()
    }
    func addProfile(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let p = PlayerProfile(name: String(clean.prefix(40)))
        data.profiles.append(p); data.currentProfile = p.id; persist()
    }
    func toggleFavourite(_ game: Game) {
        updateProfile { p in if p.favourites.contains(game.id) { p.favourites.remove(game.id) } else { p.favourites.insert(game.id) } }
    }
    func played(_ game: Game) { updateProfile { $0.recent[game.id] = Date() } }
    func importFiles(_ urls: [URL], system: GameSystem) {
        do {
            guard system != .pcecd else { throw StoreError.message("Use Link folder for CD games so their companion tracks stay together.") }
            var skipped = 0
            for url in urls {
                let id = UUID()
                let relative = "\(system.rawValue)/\(id.uuidString)/\(url.lastPathComponent)"
                let game = Game(id: id, title: "", system: system, relativePath: relative)
                guard GameSystem.recognises(game.fileName, for: system), GameCatalogue.shared.isListed(game) else {
                    if system == .fbneo { skipped += 1; continue }
                    throw StoreError.message("\(game.fileName) is not a supported \(system.title) file. \(system.help)")
                }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let destination = gamesURL.appendingPathComponent(relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                var coordinationError: NSError?
                var copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                    do { try fm.copyItem(at: readable, to: destination) } catch { copyError = error }
                }
                if let e = coordinationError { throw e }
                if let e = copyError { throw e }
                data.games.append(GameCatalogue.shared.identify(game))
                persist()
            }
            if system == .fbneo { scanStatus = "\(urls.count - skipped) imported · \(skipped) unsupported FBNeo files skipped" }
        } catch { self.error = error.localizedDescription }
    }
    func linkFolder(_ url: URL, system: GameSystem?) {
        guard !busy else { return }
        do {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            let existing = data.folders.first { folder in
                guard (folder.detectSystems == true) == (system == nil), system == nil || folder.system == system else { return false }
                var stale = false
                return (try? URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))?.standardizedFileURL == url.standardizedFileURL
            }
            let folder = existing ?? GameFolder(name: url.lastPathComponent, system: system ?? .arcade, bookmark: bookmark, detectSystems: system == nil)
            busy = true; scanStatus = "Scanning \(folder.name)…"
            Task {
                defer { busy = false }
                do {
                    let result = try await Task.detached(priority: .userInitiated) { try FolderScanner.scan(folder: folder, root: url) }.value
                    let added = FolderScanner.merge(result.games, into: &data.games)
                    if existing == nil { data.folders.append(folder) }
                    await ArtworkLoader.shared.retryMissing(); artworkRevision += 1
                    persist()
                    scanStatus = "\(result.games.count) games found · \(added) added · \(result.ignored) support or unsupported files skipped"
                    if result.games.isEmpty { scanStatus += ". Try selecting a specific system, or make cloud files available in Files first." }
                } catch { self.error = "Could not scan \(folder.name): \(error.localizedDescription)"; scanStatus = "Scan failed · existing games and saves kept" }
            }
        } catch { self.error = error.localizedDescription }
    }
    func rescan() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            var added = 0, found = 0, failures: [String] = []
            for folder in data.folders {
                scanStatus = "Scanning \(folder.name)…"
                do {
                    let url = try resolve(folder)
                    let result = try await Task.detached(priority: .userInitiated) { try FolderScanner.scan(folder: folder, root: url) }.value
                    added += FolderScanner.merge(result.games, into: &data.games); found += result.games.count
                } catch { failures.append(folder.name + ": " + error.localizedDescription) }
            }
            await ArtworkLoader.shared.retryMissing(); artworkRevision += 1
            persist(); scanStatus = "\(found) games found · \(added) added"
            if !failures.isEmpty { error = "Some folders are unavailable. Existing games and saves have been kept.\n" + failures.joined(separator: "\n") }
        }
    }
    func refreshTitles() {
        for i in data.games.indices {
            // Linked metadata is refreshed by rescanning, preserving gamelist.xml titles.
            if data.games[i].folderID == nil { data.games[i] = GameCatalogue.shared.identify(data.games[i]) }
        }
        persist(); rescan()
    }
    func artworkRoot(for game: Game) -> URL? {
        if let id = game.folderID, let folder = data.folders.first(where: { $0.id == id }) { return try? resolve(folder) }
        return gamesURL
    }
    func editTitle(_ game: Game, title: String) {
        guard let index = data.games.firstIndex(where: { $0.id == game.id }) else { return }
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        data.games[index].customTitle = value.isEmpty ? nil : String(value.prefix(160))
        persist(); artworkRevision += 1
    }
    func importArtwork(_ url: URL, for game: Game) {
        guard let index = data.games.firstIndex(where: { $0.id == game.id }) else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20_000_000,
                  let image = ArtworkLoader.thumbnail(try Data(contentsOf: url)) else { throw StoreError.message("Choose a PNG, JPEG or HEIC image smaller than 20 MB.") }
            let name = UUID().uuidString + ".jpg"
            try image.write(to: artworkURL.appendingPathComponent(name), options: .atomic)
            data.games[index].artwork = name; persist(); artworkRevision += 1
        } catch { self.error = error.localizedDescription }
    }
    private func resolve(_ folder: GameFolder) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let index = data.folders.firstIndex(where: { $0.id == folder.id }) {
                data.folders[index].bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil); persist()
            }
        }
        return url
    }
    func accessGame(_ game: Game) throws -> GameAccess {
        guard LibraryRules.safeRelativePath(game.relativePath) else { throw StoreError.message("Invalid game path.") }
        let base: URL
        if let id = game.folderID {
            guard let folder = data.folders.first(where: { $0.id == id }) else { throw StoreError.message("Link the game's folder again in Settings.") }
            base = try resolve(folder)
        } else { base = gamesURL }
        let access = GameAccess(root: base, path: game.relativePath)
        guard fm.fileExists(atPath: access.url.path) else { throw StoreError.message("This game is unavailable. Reconnect its drive or download it in Files, then try again.") }
        try access.prepareConsoleZIP(for: game.system)
        return access
    }
    // Existing mixed-folder libraries can play a newly added disc immediately, before a rescan.
    func resolveArcadeRoute(_ original: Game, archive: URL) -> Game {
        guard let disc = GameCatalogue.shared.discSet(for: original), let folderID = original.folderID,
              data.folders.contains(where: { $0.id == folderID && $0.detectSystems == true }) else { return original }
        var game = original
        game.hasMAMEDisc = disc.hasCompanion(beside: archive)
        GameCatalogue.shared.routeAutomaticArcade(&game)
        game.preserveSaves(from: original)
        if game != original, let index = data.games.firstIndex(where: { $0.id == game.id }) {
            data.games[index] = game
            persist()
        }
        return game
    }
    func saveDirectory(for game: Game) throws -> URL {
        var path = savesURL.appendingPathComponent(profile.id.uuidString).appendingPathComponent(game.id.uuidString)
        if let folder = game.alternateSaveFolder { path.appendPathComponent(folder) }
        try fm.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
    func importBIOS(_ url: URL) {
        do {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let target = biosURL.appendingPathComponent(url.lastPathComponent)
            try Data(contentsOf: url).write(to: target, options: .atomic)
            objectWillChange.send()
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ game: Game) {
        // Library removal preserves both original ROMs and saves; no external file is deleted.
        data.games.removeAll { $0.id == game.id }
        for i in data.profiles.indices { data.profiles[i].favourites.remove(game.id); data.profiles[i].recent.removeValue(forKey: game.id) }
        persist()
    }
}

final class GameAccess {
    let root: URL
    private(set) var url: URL
    private var temporary: URL?
    private let scoped: Bool
    init(root: URL, path: String) { self.root = root; url = root.appendingPathComponent(path); scoped = root.startAccessingSecurityScopedResource() }
    func prepareConsoleZIP(for system: GameSystem) throws {
        guard !system.isArcade, url.pathExtension.lowercased() == "zip" else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LightRetro-" + UUID().uuidString, isDirectory: true)
        do { url = try ConsoleArchive.extract(url, system: system, destination: directory); temporary = directory }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    deinit { if scoped { root.stopAccessingSecurityScopedResource() }; if let temporary { try? FileManager.default.removeItem(at: temporary) } }
}
enum StoreError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
