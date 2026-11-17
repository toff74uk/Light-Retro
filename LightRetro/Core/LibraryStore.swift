import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class LibraryStore: ObservableObject {
    @Published var data = LibraryData()
    @Published var error: String?
    @Published var busy = false
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
        root = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            for folder in [gamesURL, biosURL, savesURL, artworkURL] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
            let file = root.appendingPathComponent("library.json")
            if fm.fileExists(atPath: file.path) {
                let decoded = try JSONDecoder().decode(LibraryData.self, from: Data(contentsOf: file))
                guard decoded.version == 1 else { throw StoreError.message("This library needs a newer version of Light Retro.") }
                data = decoded
                if data.profiles.isEmpty { data.profiles = [PlayerProfile(name: "Player 1")] }
            }
        } catch { writable = false; self.error = "Could not read your library. Your files are still in Files → Light Retro. \(error.localizedDescription)" }
    }
    func persist() {
        guard writable else { error = "Your existing library could not be read. Back up library.json in Files before repairing it; it has not been overwritten."; return }
        do { try JSONEncoder().encode(data).write(to: root.appendingPathComponent("library.json"), options: .atomic) }
        catch { self.error = "Could not save the library: \(error.localizedDescription)" }
    }
    func updateProfile(_ change: (inout PlayerProfile) -> Void) { change(&data.profiles[profileIndex]); persist() }
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
            for url in urls {
                guard GameSystem.recognises(url.lastPathComponent, for: system) else { throw StoreError.message("\(url.lastPathComponent) is not a supported \(system.title) file. \(system.help)") }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let id = UUID()
                let relative = "\(system.rawValue)/\(id.uuidString)/\(url.lastPathComponent)"
                let destination = gamesURL.appendingPathComponent(relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                var coordinationError: NSError?
                var copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                    do { try fm.copyItem(at: readable, to: destination) } catch { copyError = error }
                }
                if let e = coordinationError { throw e }
                if let e = copyError { throw e }
                data.games.append(Game(id: id, title: LibraryRules.displayName(url.lastPathComponent), system: system, relativePath: relative))
                persist()
            }
        } catch { self.error = error.localizedDescription }
    }
    func linkFolder(_ url: URL, system: GameSystem) {
        do {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let existing = data.folders.first(where: { folder in
                guard folder.system == system else { return false }
                var stale = false
                return (try? URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))?.standardizedFileURL == url.standardizedFileURL
            }) { try scan(existing, url: url); persist(); return }
            let folder = GameFolder(name: url.lastPathComponent, system: system, bookmark: bookmark)
            try scan(folder, url: url); data.folders.append(folder); persist()
        } catch { self.error = error.localizedDescription }
    }
    private func scan(_ folder: GameFolder, url: URL) throws {
        var scanError: Error?
        guard let files = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { _, e in scanError = e; return false }) else { throw StoreError.message("Could not open this folder.") }
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            let relative = String(file.path.dropFirst(url.path.count + 1))
            guard LibraryRules.safeRelativePath(relative), GameSystem.recognises(relative, for: folder.system) else { continue }
            LibraryRules.upsert(Game(title: LibraryRules.displayName(file.lastPathComponent), system: folder.system, relativePath: relative, folderID: folder.id), in: &data.games)
        }
        if let scanError { throw scanError }
    }
    func rescan() {
        do {
            for folder in data.folders {
                let url = try resolve(folder)
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                try scan(folder, url: url)
            }
            persist()
        } catch { self.error = "Rescan stopped: \(error.localizedDescription)" }
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
        return access
    }
    func saveDirectory(for game: Game) throws -> URL {
        let path = savesURL.appendingPathComponent(profile.id.uuidString).appendingPathComponent(game.id.uuidString)
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
    let url: URL
    private let scoped: Bool
    init(root: URL, path: String) { self.root = root; url = root.appendingPathComponent(path); scoped = root.startAccessingSecurityScopedResource() }
    deinit { if scoped { root.stopAccessingSecurityScopedResource() } }
}
enum StoreError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
