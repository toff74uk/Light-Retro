import SwiftUI

struct GameDetailsView: View {
    let game: Game
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var query = ""
    @State private var cover = false
    @State private var remove = false
    private var current: Game { store.data.games.first { $0.id == game.id } ?? game }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 18) {
                        GameArtwork(game: current).frame(width: 110, height: 120)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(current.displayTitle).font(.headline)
                            Text(current.system.title).font(.subheadline)
                            if let year = current.year { Text(year).font(.caption) }
                            if let maker = current.maker { Text(maker).font(.caption) }
                        }
                    }
                    if let description = current.summary { Text(description).font(.footnote) }
                    LabeledContent("ROM file", value: current.fileName).font(.caption).textSelection(.enabled)
                    if let canonical = current.catalogueTitle { LabeledContent("Catalogue name", value: canonical).font(.caption) }
                    Button(store.profile.favourites.contains(game.id) ? "Remove favourite" : "Add favourite", systemImage: "heart") { store.toggleFavourite(game) }
                }
                Section("Display name") {
                    TextField("Game title", text: $title)
                    Button("Save title") { store.editTitle(game, title: title) }
                    Button("Restore automatic title") { store.editTitle(game, title: ""); title = current.displayTitle }
                    Text("Changes the displayed name only. The original ROM filename, folder and save files stay the same.").font(.caption).foregroundStyle(.secondary)
                }
                if game.system.isArcade {
                    Section("Match an arcade title") {
                        TextField("Search the ROM catalogue", text: $query).autocorrectionDisabled()
                        ForEach(GameCatalogue.shared.search(query, system: game.system), id: \.id) { match in
                            Button { title = match.title; store.editTitle(game, title: match.title); query = "" } label: {
                                VStack(alignment: .leading) { Text(match.title); Text(match.id).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section("Cover artwork") {
                    Button("Choose cover image…", systemImage: "photo") { cover = true }
                    Button("Use automatic artwork") {
                        if let index = store.data.games.firstIndex(where: { $0.id == game.id }) { store.data.games[index].artwork = nil; store.persist(); store.artworkRevision += 1 }
                    }
                    Text("Local images are preferred. Downloads use title matches; when no match exists, the system logo stays visible until you choose a cover.").font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("Remove from library", role: .destructive) { remove = true } }
            }.navigationTitle("Game details")
                .onAppear { title = current.displayTitle }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $cover) { DocumentPicker(multiple: false, contentTypes: [.image]) { if let url = $0.first { store.importArtwork(url, for: game) } } }
                .confirmationDialog("Remove this library entry? ROM files and saves will be kept.", isPresented: $remove, titleVisibility: .visible) { Button("Remove", role: .destructive) { store.remove(game); dismiss() } }
                .alert("Artwork", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        }
    }
}
