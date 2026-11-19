import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var controllers: ControllerHub
    @State private var section = "all"
    @State private var category = "all"
    @State private var search = ""
    @State private var selected: UUID?
    @State private var playing: Game?
    @State private var details: Game?
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var showPlayers = false
    @State private var expanded = false
    @State private var page = 0
    @State private var focus = 2
    @State private var columns = 6
    @State private var lastInteraction = Date()
    @State private var asleep = false
    private let clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    private var palette: RetroPalette { RetroPalette(profile: store.profile) }
    private var system: GameSystem? { GameSystem(rawValue: section) }
    private var compact: Bool { store.profile.compactTiles ?? true }
    private var systems: [GameSystem] { GameSystem.playable.filter { !(store.profile.hiddenSystems ?? []).contains($0) } }
    private var sections: [(String, String)] { systems.map { ($0.rawValue, $0.title) } + [("all", "All games"), ("favourites", "Favourites"), ("recent", "Recently played"), ("profiles", "Profiles"), ("settings", "Settings")] }
    private var baseGames: [Game] {
        store.data.games.filter { game in
            (system == nil || game.system == system) && GameCatalogue.shared.isListed(game) && !(store.profile.hiddenSystems ?? []).contains(game.system) &&
            (section != "favourites" || store.profile.favourites.contains(game.id)) &&
            (section != "recent" || store.profile.recent[game.id] != nil)
        }
    }
    private var categories: [(String, String)] {
        var result = [("all", "All ROMs")]
        if let system {
            if system == .fbneo {
                result += GameCatalogue.fbneoBoards.map { ("board:" + $0, $0) }
            } else {
                result += GameCatalogue.shared.collections.filter { $0.systems.contains(system) }.map { ("collection:" + $0.id, $0.title) }
            }
            result += Set(baseGames.map(\.collectionFolder)).sorted().map { ("folder:" + $0, $0) }
        } else {
            let present = Set(baseGames.map(\.system))
            result += systems.filter { present.contains($0) }.map { ("system:" + $0.rawValue, $0.title) }
        }
        return result
    }
    private var games: [Game] {
        let collection = GameCatalogue.shared.collections.first { "collection:" + $0.id == category }
        let board = category.hasPrefix("board:") ? String(category.dropFirst(6)) : nil
        return baseGames.filter { game in
            (search.isEmpty || game.displayTitle.localizedCaseInsensitiveContains(search) || game.fileName.localizedCaseInsensitiveContains(search)) &&
            (category == "all" || category == "folder:" + game.collectionFolder || category == "system:" + game.system.rawValue || collection?.contains(game) == true ||
             (board != nil && GameCatalogue.shared.fbneoBoard(for: game) == board))
        }.sorted {
            if section == "recent" { return (store.profile.recent[$0.id] ?? .distantPast) > (store.profile.recent[$1.id] ?? .distantPast) }
            return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height
            let count = wide ? (expanded ? 9 : (compact ? 6 : 4)) : (compact ? 3 : 2)
            let results = games
            let visible = LibraryPage(results, index: page)
            VStack(spacing: 7) {
                if !expanded { header(wide: wide, width: geometry.size.width, game: visible.games.first { $0.id == selected } ?? visible.games.first) }
                if wide {
                    HStack(alignment: .top, spacing: 8) {
                        if !expanded && !store.profile.leftHanded { rails(width: geometry.size.width) }
                        collection(columns: count, results: results, visible: visible)
                        if !expanded && store.profile.leftHanded { rails(width: geometry.size.width) }
                    }
                } else {
                    if !expanded { portraitRails }
                    collection(columns: count, results: results, visible: visible)
                }
                footer
            }.padding(.horizontal, 10).padding(.top, 5).padding(.bottom, 3)
                .foregroundStyle(palette.text).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.background.ignoresSafeArea()).tint(palette.text)
                .onAppear { columns = count }
                .onChange(of: count) { columns = $0 }
        }
        .sheet(isPresented: $showAdd, onDismiss: installMenuControls) { AddGamesView(initialSystem: system) }
        .sheet(item: $details, onDismiss: installMenuControls) { GameDetailsView(game: $0) }
        .fullScreenCover(isPresented: $showSettings, onDismiss: installMenuControls) { SettingsView() }
        .fullScreenCover(isPresented: $showPlayers, onDismiss: installMenuControls) {
            NavigationStack {
                ProfilesView()
                    .navigationTitle("Profiles")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPlayers = false } } }
            }
        }
        .fullScreenCover(item: $playing, onDismiss: installMenuControls) { PlayerView(game: $0) }
        .alert("Light Retro", isPresented: Binding(get: { store.error != nil && !showAdd && !showSettings && details == nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onAppear(perform: installMenuControls)
        .onChange(of: section) { _ in resetSelection() }
        .onChange(of: category) { _ in resetSelection() }
        .onChange(of: search) { _ in resetSelection() }
        .onChange(of: store.data.games) { _ in reconcileSelection() }
        .onChange(of: store.data.currentProfile) { _ in resetSelection() }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in lastInteraction = Date() })
        .onReceive(clock) { _ in
            let minutes = store.profile.screensaverMinutes ?? 0
            if minutes > 0, !store.busy, playing == nil, details == nil, !showAdd, !showSettings, !showPlayers,
               Date().timeIntervalSince(lastInteraction) > Double(minutes * 60) { asleep = true }
        }
        .overlay {
            if asleep { ScreensaverView { asleep = false; lastInteraction = Date() } }
        }
    }
    private func header(wide: Bool, width: CGFloat, game: Game?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 5) {
                Image("Brand").resizable().scaledToFit().frame(maxHeight: 57).accessibilityLabel("Light Retro")
                Button { showPlayers = true } label: { Label(store.profile.name, systemImage: "person.crop.circle").lineLimit(1) }.font(.system(size: 11))
            }.frame(width: wide ? width * 0.155 : 82)
            if let game {
                GameArtwork(game: game).frame(width: wide ? width * 0.15 : 64, height: wide ? 90 : 76)
                VStack(alignment: .leading, spacing: 5) {
                    Text(game.displayTitle).font(.system(size: wide ? 21 : 17, weight: .bold)).lineLimit(2).accessibilityIdentifier("selected-title")
                    Text([game.system.title, game.year, game.maker].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 11)).lineLimit(1).opacity(0.8)
                    if wide { Text(game.summary ?? "Select a game to browse. Play to start, or hold a tile for names, artwork and favourites.").font(.system(size: 12)).lineLimit(2).opacity(0.9) }
                    HStack(spacing: 15) {
                        Button { launch(game) } label: { Label("Play", systemImage: "play.fill") }.accessibilityIdentifier("play-selected")
                        Button { details = game } label: { Label("Details", systemImage: "info.circle") }
                    }.font(.system(size: 12, weight: .semibold)).buttonStyle(.bordered).tint(palette.text)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your games. Your way.").font(.title3.bold())
                    Text("Add a ROM folder to start your collection.").font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(height: wide ? 112 : 105)
    }
    private func rails(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) { ForEach(sections, id: \.0) { item in railButton(item.1, selected: section == item.0, focused: focus == 0) { chooseSection(item.0) }.id(item.0) } }
                }.onChange(of: section) { proxy.scrollTo($0, anchor: .center) }
            }.frame(width: width * 0.16)
            VStack(spacing: 6) {
                searchField
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) { ForEach(categories, id: \.0) { item in railButton(item.1, selected: category == item.0, focused: focus == 1) { category = item.0; focus = 1 }.id(item.0) } }
                    }.onChange(of: category) { proxy.scrollTo($0, anchor: .center) }
                }
            }.frame(width: width * 0.17)
        }
    }
    private var portraitRails: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) { ForEach(sections, id: \.0) { item in railButton(item.1, selected: section == item.0, focused: focus == 0) { chooseSection(item.0) }.fixedSize(horizontal: true, vertical: false) } }
            }
            HStack {
                searchField
                Picker("Category", selection: $category) { ForEach(categories, id: \.0) { Text($0.1).tag($0.0) } }.tint(palette.text)
            }
        }
    }
    private func railButton(_ title: String, selected: Bool, focused: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: selected ? .bold : .regular)).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 9)
                .background(selected ? palette.selected : palette.tile)
                .overlay(Rectangle().stroke(selected && focused ? palette.text : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityIdentifier("nav-" + title)
    }
    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
            TextField("Search ROMs", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") } }
        }.font(.system(size: 12)).padding(.horizontal, 8).frame(height: 44).background(palette.tile)
    }
    private func collection(columns: Int, results: [Game], visible: LibraryPage) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(results.count) games").font(.system(size: 11))
                Spacer(minLength: 3)
                Button { showAdd = true } label: { Label("Add folder", systemImage: "folder.badge.plus") }.accessibilityIdentifier("add-folder")
                Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings").accessibilityIdentifier("open-settings")
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }.accessibilityLabel(expanded ? "Show menus" : "Full screen library")
            }.font(.system(size: 12, weight: .semibold)).frame(minHeight: 30)
            if results.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus").font(.largeTitle)
                    Text(search.isEmpty ? "No games in this collection" : "No matching ROMs").font(.headline)
                    Text("Add a folder with your ROMs and subfolders, or import individual files.").font(.caption).multilineTextAlignment(.center)
                    Button("Add folder or files") { showAdd = true }.buttonStyle(.bordered)
                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.tile.opacity(0.4))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                            ForEach(visible.games) { game in gameCard(game).id(game.id) }
                        }.padding(2)
                    }.onChange(of: selected) { value in if let value { proxy.scrollTo(value, anchor: .center) } }
                }
            }
            HStack {
                Button { changePage(-1, in: results) } label: { Label("Previous", systemImage: "chevron.left") }.disabled(visible.index == 0)
                Spacer()
                Text("\(visible.index + 1) / \(visible.count)").monospacedDigit()
                Spacer()
                Button { changePage(1, in: results) } label: { Label("Next", systemImage: "chevron.right") }.disabled(visible.index == visible.count - 1)
            }.font(.system(size: 11, weight: .semibold)).frame(height: 30)
        }.frame(maxWidth: .infinity)
    }
    private func gameCard(_ game: Game) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                GameArtwork(game: game).frame(height: compact ? 55 : 96).frame(maxWidth: .infinity)
                if store.profile.favourites.contains(game.id) { Image(systemName: "heart.fill").font(.system(size: 11)).padding(4).background(.black.opacity(0.4)) }
            }
            Text(game.displayTitle).font(.system(size: compact ? 10 : 12, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2).frame(height: compact ? 29 : 34)
        }.padding(5).background(selected == game.id ? palette.selected : palette.tile)
            .overlay(Rectangle().stroke(selected == game.id && focus == 2 ? palette.text : .clear, lineWidth: 2))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { selected = game.id; launch(game) }
            .onTapGesture { selected = game.id; focus = 2 }
            .accessibilityElement(children: .ignore).accessibilityLabel(game.displayTitle).accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("game-" + game.romStem)
            .accessibilityAction { selected = game.id; focus = 2 }
            .contextMenu {
                Button("Play", systemImage: "play.fill") { launch(game) }
                Button("Names, artwork & details", systemImage: "info.circle") { details = game }
                Button(store.profile.favourites.contains(game.id) ? "Remove favourite" : "Favourite", systemImage: "heart") { store.toggleFavourite(game) }
            }
    }
    private var footer: some View {
        HStack(spacing: 6) {
            if store.busy { ProgressView().tint(palette.text).scaleEffect(0.7) }
            Text(store.scanStatus.isEmpty ? (controllers.names.isEmpty ? "Tap to select · Double-tap to play · Hold for options" : "D-pad: browse · A: play · X: favourite · Y: full screen · L/R: page") : store.scanStatus).lineLimit(1)
            Spacer(minLength: 2)
            Text("Light Retro 0.3").lineLimit(1)
        }.font(.system(size: 9)).opacity(0.85).frame(height: 18)
    }
    private func chooseSection(_ value: String) {
        lastInteraction = Date()
        if value == "settings" { showSettings = true; return }
        if value == "profiles" { showPlayers = true; return }
        section = value; category = "all"; focus = 0
    }
    private func resetSelection() { page = 0; selected = games.first?.id; lastInteraction = Date() }
    private func reconcileSelection() {
        let results = games
        let index = results.firstIndex { $0.id == selected } ?? 0
        page = index / LibraryPage.size
        selected = results.isEmpty ? nil : results[index].id
    }
    private func changePage(_ delta: Int, in results: [Game]) {
        let next = LibraryPage(results, index: page + delta)
        page = next.index
        selected = next.games.first?.id
        focus = 2
    }
    private func launch(_ game: Game) { guard game.system.core != nil else { store.error = game.system.help; return }; controllers.onMenuInput = nil; playing = game }
    private func installMenuControls() {
        lastInteraction = Date(); reconcileSelection()
        controllers.onGameInput = nil; controllers.onPause = nil; controllers.analogueGameplay = false
        controllers.onMenuInput = { button in
            lastInteraction = Date()
            if asleep { asleep = false; return }
            guard playing == nil, details == nil, !showAdd, !showSettings, !showPlayers else { return }
            if button == 3 { showSettings = true; return }
            if button == 9 { expanded.toggle(); focus = 2; return }
            if button == 8 { focus = max(0, focus - 1); expanded = false; return }
            if button == 10 || button == 11 { changePage(button == 10 ? -1 : 1, in: games); return }
            if button == 1 {
                let results = games
                if let game = results.first(where: { $0.id == selected }) ?? results.first { store.toggleFavourite(game); reconcileSelection() }
                return
            }
            if focus == 0 {
                let items = sections.filter { $0.0 != "settings" && $0.0 != "profiles" }
                let i = items.firstIndex { $0.0 == section } ?? 0
                if button == 4 || button == 5 { chooseSection(items[min(items.count - 1, max(0, i + (button == 4 ? -1 : 1)))].0) }
                if button == 0 || button == 7 { focus = 1 }
            } else if focus == 1 {
                let i = categories.firstIndex { $0.0 == category } ?? 0
                if button == 4 || button == 5 { category = categories[min(categories.count - 1, max(0, i + (button == 4 ? -1 : 1)))].0 }
                if button == 6 { focus = 0 }
                if button == 0 || button == 7 { focus = 2 }
            } else {
                let list = games
                guard !list.isEmpty else { if button == 6 { focus = 1 }; return }
                let i = list.firstIndex { $0.id == selected } ?? 0
                if button == 0 { launch(list[i]); return }
                if button == 2 { details = list[i]; return }
                if button == 6 && (i % LibraryPage.size) % columns == 0 && !expanded { focus = 1; return }
                let delta = [4: -columns, 5: columns, 6: -1, 7: 1][button] ?? 0
                let next = min(list.count - 1, max(0, i + delta))
                selected = list[next].id; page = next / LibraryPage.size
            }
        }
    }
}
