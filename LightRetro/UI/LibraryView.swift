import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var controllers: ControllerHub
    @State private var system: GameSystem?
    @State private var filter = "All games"
    @State private var search = ""
    @State private var selected: UUID?
    @State private var playing: Game?
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var showPlayers = false
    @State private var pendingRemoval: Game?
    private let filters = ["All games", "Favourites", "Recent"]
    private var games: [Game] {
        store.data.games.filter { game in
            (system == nil || game.system == system) && (search.isEmpty || game.title.localizedCaseInsensitiveContains(search)) &&
            (filter != "Favourites" || store.profile.favourites.contains(game.id)) &&
            (filter != "Recent" || store.profile.recent[game.id] != nil)
        }.sorted {
            if filter == "Recent" { return (store.profile.recent[$0.id] ?? .distantPast) > (store.profile.recent[$1.id] ?? .distantPast) }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height
            VStack(spacing: 0) {
                header
                if wide {
                    HStack(spacing: 0) {
                        if !store.profile.leftHanded { sidebar.frame(width: 190) }
                        collection
                        if store.profile.leftHanded { sidebar.frame(width: 190) }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { systemChip(nil); ForEach(GameSystem.allCases) { systemChip($0) } }.padding(.horizontal)
                    }.padding(.bottom, 10)
                    collection
                }
            }.background(Color(red: 0.025, green: 0.035, blue: 0.07))
        }
        .sheet(isPresented: $showAdd) { AddGamesView(initialSystem: system ?? .nes) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPlayers) { ProfilesView() }
        .fullScreenCover(item: $playing, onDismiss: { installMenuControls() }) { PlayerView(game: $0) }
        .alert("Light Retro", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("Remove from your library? Game files and saves will be kept.", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let game = pendingRemoval { store.remove(game) }; pendingRemoval = nil }
        }
        .onAppear { installMenuControls() }
        .onChange(of: system) { _ in selected = games.first?.id }
        .onChange(of: filter) { _ in selected = games.first?.id }
    }
    private var header: some View {
        HStack(spacing: 14) {
            Image("Brand").resizable().scaledToFit().frame(width: 102, height: 52).accessibilityLabel("Light Retro")
            Spacer()
            Button { showPlayers = true } label: { Label(store.profile.name, systemImage: "person.crop.circle") }.lineLimit(1)
            Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }.accessibilityLabel("Add games")
            Button { showSettings = true } label: { Image(systemName: "gearshape.fill").font(.title3) }.accessibilityLabel("Settings")
        }.padding(.horizontal, 20).padding(.vertical, 8)
    }
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR SYSTEMS").font(.caption2.weight(.bold)).foregroundStyle(.secondary).padding(.vertical, 12)
                systemRow(nil)
                ForEach(GameSystem.allCases) { systemRow($0) }
                Divider().padding(.vertical, 12)
                Label(controllers.names.isEmpty ? "Touch controls" : controllers.names.joined(separator: ", "), systemImage: "gamecontroller")
                    .font(.caption).foregroundStyle(.secondary)
                Text("iPHONE BETA 0.1").font(.caption2.monospaced()).foregroundStyle(.secondary).padding(.top)
            }.padding(14)
        }.background(.white.opacity(0.025))
    }
    private func systemRow(_ item: GameSystem?) -> some View {
        Button { system = item } label: {
            HStack {
                Text(item?.title ?? "All systems").font(.subheadline.weight(system == item ? .semibold : .regular))
                Spacer(minLength: 2)
                if let item, item.core == nil { Image(systemName: "clock").font(.caption2) }
            }.foregroundStyle(system == item ? .white : .white.opacity(0.65)).padding(.horizontal, 12).padding(.vertical, 12)
                .background(system == item ? store.tint.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
    private func systemChip(_ item: GameSystem?) -> some View {
        Button(item?.title ?? "All systems") { system = item }.font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(system == item ? store.tint.opacity(0.25) : .white.opacity(0.05), in: Capsule())
    }
    private var collection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(system?.title ?? "Your games").font(.title2.bold())
                Spacer()
                Text("\(games.count) games").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your collection", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") } }
            }.padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            Picker("Collection", selection: $filter) { ForEach(filters, id: \.self) { Text($0) } }.pickerStyle(.segmented)
            if let system, system.core == nil {
                Label(system.help, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            }
            if games.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller").font(.system(size: 52)).foregroundStyle(store.tint)
                    Text(search.isEmpty ? "Your next adventure starts here." : "No games found.").font(.title3.bold()).multilineTextAlignment(.center)
                    Text("Add your games from Files, or link a folder on your iPhone or USB drive.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Add games") { showAdd = true }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 138, maximum: 200), spacing: 12)], spacing: 14) {
                            ForEach(games) { game in gameCard(game).id(game.id) }
                        }.padding(.vertical, 4)
                    }.onChange(of: selected) { id in if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } } }
                }
            }
        }.padding(.horizontal, 18).padding(.bottom, 12)
    }
    private func gameCard(_ game: Game) -> some View {
        Button { selected = game.id; launch(game) } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [store.tint.opacity(0.18), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image("system_\(game.system.rawValue)").resizable().scaledToFit().padding(18)
                    if store.profile.favourites.contains(game.id) { Image(systemName: "heart.fill").foregroundStyle(store.tint).padding(9) }
                    if game.system.core == nil { Image(systemName: "clock.fill").foregroundStyle(.secondary).padding(9) }
                }.frame(height: 112)
                Text(game.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2).frame(height: 38, alignment: .topLeading)
                Text(game.system.title).font(.caption2).foregroundStyle(.secondary)
            }.padding(8).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected == game.id ? store.tint : .clear, lineWidth: 2))
        }.buttonStyle(.plain).contextMenu {
            Button("Play", systemImage: "play.fill") { launch(game) }
            Button(store.profile.favourites.contains(game.id) ? "Remove favourite" : "Favourite", systemImage: "heart") { store.toggleFavourite(game) }
            Button("Remove from library", systemImage: "minus.circle", role: .destructive) { pendingRemoval = game }
        }
    }
    private func launch(_ game: Game) {
        guard game.system.core != nil else { store.error = game.system.help; return }
        controllers.onMenuInput = nil; playing = game
    }
    private func installMenuControls() {
        controllers.onGameInput = nil; controllers.onPause = nil
        controllers.onMenuInput = { button in
            guard playing == nil, !showAdd, !showSettings, !showPlayers else { return }
            let index = games.firstIndex { $0.id == selected } ?? 0
            switch button {
            case 4,6: if !games.isEmpty { selected = games[max(0,index-1)].id }
            case 5,7: if !games.isEmpty { selected = games[min(games.count-1,index+1)].id }
            case 0: if !games.isEmpty { launch(games[index]) }
            case 1: if !games.isEmpty { store.toggleFavourite(games[index]) }
            case 8: system = nil; filter = "All games"
            case 3: showSettings = true
            case 10,11:
                let choices: [GameSystem?] = [nil] + GameSystem.allCases.map(Optional.some)
                let current = choices.firstIndex { $0 == system } ?? 0
                system = choices[(current + (button == 11 ? 1 : choices.count-1)) % choices.count]
            default: break
            }
        }
    }
}

struct AddGamesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LibraryStore
    @State private var system: GameSystem
    @State private var pickFiles = false
    @State private var pickFolder = false
    init(initialSystem: GameSystem) { _system = State(initialValue: initialSystem) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Choose a system") {
                    Picker("System", selection: $system) { ForEach(GameSystem.allCases) { Text($0.title).tag($0) } }
                    Text(system.help).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Copy games from Files", systemImage: "doc.badge.plus") { pickFiles = true }.disabled(system == .pcecd)
                    Button("Link a folder / USB drive", systemImage: "folder.badge.plus") { pickFolder = true }
                } footer: { Text("Copied games stay on your iPhone. Linked folders stay where they are; connect the drive or make cloud files available offline before playing. Your games are never uploaded.") }
            }.navigationTitle("Add your games").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $pickFiles) { DocumentPicker { store.importFiles($0, system: system) } }
                .sheet(isPresented: $pickFolder) { DocumentPicker(folder: true) { if let url = $0.first { store.linkFolder(url, system: system) } } }
        }
    }
}
