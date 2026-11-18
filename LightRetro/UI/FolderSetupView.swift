import SwiftUI

struct AddGamesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LibraryStore
    @State private var system: GameSystem?
    @State private var pickFiles = false
    @State private var pickFolder = false
    init(initialSystem: GameSystem? = nil) { _system = State(initialValue: initialSystem) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Add a complete folder") {
                    Picker("System", selection: $system) {
                        Text("Automatic · mixed systems").tag(Optional<GameSystem>.none)
                        ForEach(GameSystem.playable) { Text($0.title).tag(Optional($0)) }
                    }.accessibilityIdentifier("folder-system")
                    Button { pickFolder = true } label: { Label("Choose folder…", systemImage: "folder.badge.plus").font(.headline).padding(.vertical, 7) }
                        .disabled(store.busy).accessibilityIdentifier("choose-folder")
                    Text("Includes subfolders and keeps the ROMs in their original location. Select the folder in Files, then tap Open.").font(.footnote)
                    if let system { Text(system.help).font(.footnote).foregroundStyle(.secondary) }
                    else { Text("Name system folders MAME, FBNeo, NES, N64, SNES, Mega Drive, PC Engine or PCE CD. ZIPs without a recognised system folder are treated as MAME. For a differently named folder, select its system above.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Or add individual files") {
                    Button("Import files…", systemImage: "doc.badge.plus") { pickFiles = true }.disabled(system == nil || system == .pcecd || store.busy)
                    Text(system == nil ? "Choose a system above to import individual ROM files." : "Imported files are copied into Light Retro. CD games and arcade sets with companions work best from a linked folder.").font(.footnote).foregroundStyle(.secondary)
                }
                if !store.scanStatus.isEmpty {
                    Section("Scan progress") { if store.busy { ProgressView() }; Text(store.scanStatus).font(.footnote) }
                }
                Section("Names and artwork") {
                    Text("MAME and FBNeo names are matched from the Android app’s bundled catalogue. Console names are cleaned up. Existing gamelist.xml titles, descriptions and images are read automatically.").font(.footnote)
                    Text("Put covers beside a ROM using the same filename with .png or .jpg, or in a covers, images or artwork folder. Missing art can be downloaded and cached. Hold a game tile to change its name or choose a cover.").font(.footnote)
                }
                Section {
                    Text("For linked cloud folders, make the games available offline in Files first. Reconnect external drives before playing. Your ROMs are never uploaded.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Add games")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $pickFiles) { DocumentPicker { urls in if let system { store.importFiles(urls, system: system) } } }
                .sheet(isPresented: $pickFolder) { DocumentPicker(folder: true) { if let url = $0.first { store.linkFolder(url, system: system) } } }
                .alert("Could not add games", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        }
    }
}

struct FolderSetupView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var add = false
    var body: some View {
        Form {
            Section {
                Button("Add folder or files", systemImage: "folder.badge.plus") { add = true }
                Button("Rescan all folders", systemImage: "arrow.clockwise") { store.rescan() }.disabled(store.busy || store.data.folders.isEmpty)
                if store.busy { ProgressView() }
                if !store.scanStatus.isEmpty { Text(store.scanStatus).font(.footnote) }
            }
            Section("Linked folders") {
                if store.data.folders.isEmpty { Text("No folders linked yet") }
                ForEach(store.data.folders) { folder in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(folder.name, systemImage: "folder")
                        Text(folder.subtitle).font(.caption).foregroundStyle(.secondary)
                        Text("\(store.data.games.filter { $0.folderID == folder.id }.count) games").font(.caption)
                    }
                }
            }
            Section { Text("Rescans refresh names and covers and add new games. Existing favourites, manual edits and saves are kept. Unavailable drives never cause games to be removed.").font(.footnote) }
        }.navigationTitle("Folder setup").sheet(isPresented: $add) { AddGamesView() }
    }
}
