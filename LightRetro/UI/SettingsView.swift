import SwiftUI

private enum SettingsPage: String, CaseIterable, Hashable {
    case appearance = "Appearance", profiles = "Profiles", browsing = "Customise browsing", folders = "Folder setup", artwork = "Artwork & descriptions", bios = "BIOS & resources", controller = "Controller test", screensaver = "Screensaver", updates = "Updates", about = "About"
    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .profiles: return "person.2"
        case .browsing: return "square.grid.3x3"
        case .folders: return "folder"
        case .artwork: return "photo"
        case .bios: return "opticaldisc"
        case .controller: return "gamecontroller"
        case .screensaver: return "moon.stars"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var controllers: ControllerHub
    @Environment(\.dismiss) private var dismiss
    @State private var path: [SettingsPage] = []
    @State private var selected = 0
    @State private var columns = 5
    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                let count = geometry.size.width > geometry.size.height ? 5 : 3
                let palette = RetroPalette(profile: store.profile)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 24) {
                        Image("Brand").resizable().scaledToFit().frame(width: 100, height: 54)
                        VStack(alignment: .leading, spacing: 4) { Text("Settings").font(.title2.bold()); Text("Make Light Retro yours.").font(.caption) }
                        Spacer()
                    }
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: count), spacing: 8) {
                            ForEach(Array(SettingsPage.allCases.enumerated()), id: \.element) { index, page in
                                RetroTile(title: page.rawValue, symbol: page.icon, selected: selected == index) { selected = index; path.append(page) }
                            }
                        }.padding(2)
                    }
                    Button { store.persist(); dismiss() } label: { Label("Save & Exit", systemImage: "checkmark").font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44).background(palette.selected) }
                        .buttonStyle(.plain).accessibilityIdentifier("save-exit")
                }.padding(14).foregroundStyle(palette.text).background(palette.background.ignoresSafeArea())
                    .onAppear { columns = count }.onChange(of: count) { columns = $0 }
            }.toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: SettingsPage.self) { page in
                    destination(page).navigationTitle(page.rawValue).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
                }
        }.onAppear {
            controllers.onMenuInput = { button in
                if !path.isEmpty { if button == 8 { path.removeLast() }; return }
                if button == 8 || button == 3 { store.persist(); dismiss(); return }
                if button == 0 { path.append(SettingsPage.allCases[selected]); return }
                let delta = [4: -columns, 5: columns, 6: -1, 7: 1][button] ?? 0
                selected = min(SettingsPage.allCases.count - 1, max(0, selected + delta))
            }
        }
        .alert("Light Retro", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    @ViewBuilder private func destination(_ page: SettingsPage) -> some View {
        switch page {
        case .appearance: AppearanceView()
        case .profiles: ProfilesView()
        case .folders: FolderSetupView()
        case .browsing:
            Form {
                Section("Game tiles") {
                    Toggle("Compact tiles", isOn: profileBinding(\.compactTiles, default: true))
                    Toggle("Show categories column", isOn: profileBinding(\.showCategoryColumn, default: true))
                    Text("Turn the second column off to give your game tiles more room. Search remains available above the games.").font(.footnote)
                }
                Section("System order") {
                    ForEach(Array(store.profile.orderedPlayableSystems.enumerated()), id: \.element) { index, system in
                        HStack {
                            Text(system.title)
                            Spacer()
                            Button { store.updateProfile { $0.moveSystem(system, by: -1) } } label: { Image(systemName: "arrow.up.circle") }
                                .disabled(index == 0).accessibilityLabel("Move \(system.title) up")
                            Button { store.updateProfile { $0.moveSystem(system, by: 1) } } label: { Image(systemName: "arrow.down.circle") }
                                .disabled(index == store.profile.orderedPlayableSystems.count - 1)
                                .accessibilityLabel("Move \(system.title) down")
                        }.buttonStyle(.borderless)
                    }
                }
                Section("Visible systems") {
                    ForEach(store.profile.orderedPlayableSystems) { system in
                        Toggle(system.title, isOn: Binding(get: { !(store.profile.hiddenSystems ?? []).contains(system) }, set: { visible in
                            store.updateProfile { profile in var hidden = profile.hiddenSystems ?? []; if visible { hidden.remove(system) } else { hidden.insert(system) }; profile.hiddenSystems = hidden }
                        }))
                    }
                }
                Section { Text("System order and column layout are saved for each profile. Hidden systems keep their games and saves.").font(.footnote) }
            }
        case .artwork:
            Form {
                Section {
                    Toggle("Download missing artwork", isOn: Binding(get: { store.data.downloadArtwork ?? true }, set: { store.data.downloadArtwork = $0; store.persist() }))
                    Button("Refresh ROM names and folder metadata") { store.refreshTitles() }.disabled(store.busy)
                    Button("Retry missing covers") { Task { await ArtworkLoader.shared.retryMissing(); store.artworkRevision += 1 } }
                    if store.busy { ProgressView() }
                    if !store.scanStatus.isEmpty { Text(store.scanStatus).font(.caption) }
                }
                Section("Your own artwork") {
                    Text("Use gamelist.xml image paths, or put same-named PNG/JPEG files beside ROMs or in covers, images or artwork folders. Hold any game tile to change its title or choose a cover.").font(.footnote)
                }
                Section("Automatic matching") {
                    Text("MAME and FBNeo names come from the Android 2.10 catalogues stored in the app. Console names are cleaned from their filenames, or read from gamelist.xml. Unknown abbreviated names can be edited in Game details.").font(.footnote)
                    Text("Artwork requests send system names and title candidates to thumbnails.libretro.com. Your ROM files are never sent. Successful downloads are cached for offline use; unmatched games keep their system logo. Turn downloads off to use only local and already cached art.").font(.footnote)
                    Link("Libretro thumbnail project", destination: URL(string: "https://github.com/libretro-thumbnails/libretro-thumbnails")!)
                }
            }
        case .bios: BIOSView()
        case .controller:
            Form {
                Section("Gameplay controls") { ControlOptions() }
                Section("Connected controllers") {
                    if controllers.names.isEmpty { Text("Pair a controller in iPhone Settings → Bluetooth, or connect it by USB.") }
                    ForEach(Array(controllers.names.enumerated()), id: \.offset) { index, name in Text("Player \(index + 1): \(name)") }
                    Text(controllers.pressed.isEmpty ? "Press a button to test" : "Pressed: \(controllers.pressed.sorted().map(String.init).joined(separator: ", "))").font(.caption.monospaced())
                }
                Section("Library controls") {
                    Text("D-pad: move between systems, categories and game tiles. A / Cross: enter or play. B / Circle: back. X / Square: favourite. Y / Triangle: full screen library. L1 / R1: page. Start: settings. Select: game details.").font(.footnote)
                    Text("During play, L1 + R1 + Start opens the pause menu. Touch remains available in settings forms and Apple’s file picker.").font(.footnote)
                }
            }
        case .screensaver: ScreensaverOptionsView()
        case .updates:
            Form {
                Text("Updates to this iPhone beta arrive through TestFlight.")
                Link("Open TestFlight", destination: URL(string: "itms-beta://")!)
                Link("Build status on GitHub", destination: URL(string: "https://github.com/toff74uk/Light-Retro/actions")!)
            }
        case .about:
            Form {
                Section {
                    Text("Light Retro · iPhone \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                    Text("Native iPhone port with the Android 2.10 library layout, catalogues and collections. No ROMs or BIOS files included. MAME 0.289 and Nintendo 64 support are experimental; N64 runs without JIT. SCUMM is deferred.").font(.footnote)
                    NavigationLink("Open-source licences") { LicensesView() }
                    Link("Source code & build instructions", destination: URL(string: "https://github.com/toff74uk/Light-Retro")!)
                }
                Section("Your saves") {
                    Text("Each profile has separate battery saves and save states. Save & Exit writes an automatic state; the pause menu has three manual slots. Back up Saves in Files → On My iPhone → Light Retro.").font(.footnote)
                    ShareLink("Share saves folder", item: store.savesURL)
                }
            }
        }
    }
    private func profileBinding<T>(_ key: WritableKeyPath<PlayerProfile, T?>, default value: T) -> Binding<T> {
        Binding(get: { store.profile[keyPath: key] ?? value }, set: { new in store.updateProfile { $0[keyPath: key] = new } })
    }
}

struct ControlOptions: View {
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stick and D-pad sensitivity").font(.subheadline)
            Picker("Stick and D-pad sensitivity", selection: Binding(get: { store.profile.controlResponse ?? .standard }, set: { value in
                store.updateProfile { $0.controlResponse = value }
            })) {
                ForEach(ControlResponse.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Text("Steady needs more thumb movement. Quick responds closer to the centre.").font(.caption).foregroundStyle(.secondary)
        }
        Toggle("Larger touch buttons", isOn: Binding(get: { store.profile.largeTouchButtons ?? false }, set: { value in
            store.updateProfile { $0.largeTouchButtons = value }
        }))
    }
}

private struct AppearanceView: View {
    @EnvironmentObject private var store: LibraryStore
    private var palette: RetroPalette { RetroPalette(profile: store.profile) }
    private var compact: Bool { store.profile.compactTiles ?? true }
    private var showCategories: Bool { store.profile.showCategoryColumn ?? true }
    private var shownSystems: [GameSystem] {
        store.profile.orderedPlayableSystems.filter { !(store.profile.hiddenSystems ?? []).contains($0) }
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            Group {
                if landscape {
                    HStack(alignment: .top, spacing: 14) {
                        options.frame(width: max(240, geometry.size.width * 0.42))
                        livePreview
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            options.frame(height: 420)
                            livePreview.frame(height: 310)
                        }
                    }
                }
            }
            .padding(12)
        }
        .foregroundStyle(palette.text)
        .background(palette.background.ignoresSafeArea())
    }

    private var options: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Colours").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 8), spacing: 7) {
                    ForEach(RetroPalette.colours, id: \.1) { name, hex in
                        Button {
                            store.updateProfile { $0.colourHex = hex }
                        } label: {
                            var sample = store.profile
                            let _ = sample.colourHex = hex
                            RoundedRectangle(cornerRadius: 5)
                                .fill(RetroPalette(profile: sample).tone())
                                .frame(height: 33)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(store.profile.colourHex == hex ? .white : .clear, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                    }
                }
                HStack {
                    Text("Strength").frame(width: 80, alignment: .leading)
                    Slider(value: binding(\.colourStrength), in: 0...1)
                }
                HStack {
                    Text("Brightness").frame(width: 80, alignment: .leading)
                    Slider(value: binding(\.brightness), in: 0.3...1)
                }
                Toggle("Dark text", isOn: Binding(
                    get: { store.profile.darkText ?? false },
                    set: { value in store.updateProfile { $0.darkText = value } }
                ))
                Divider()
                Text("Library layout").font(.headline)
                Toggle("Left-handed navigation", isOn: Binding(
                    get: { store.profile.leftHanded },
                    set: { value in store.updateProfile { $0.leftHanded = value } }
                ))
                Toggle("Compact game tiles", isOn: Binding(
                    get: { store.profile.compactTiles ?? true },
                    set: { value in store.updateProfile { $0.compactTiles = value } }
                ))
                Toggle("Show categories column", isOn: Binding(
                    get: { showCategories },
                    set: { value in store.updateProfile { $0.showCategoryColumn = value } }
                ))
                Text("Changes appear in the library preview on the right and are saved to this profile.")
                    .font(.caption)
                    .opacity(0.8)
            }
            .padding(10)
        }
        .background(palette.tile.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live library preview").font(.headline)
            HStack(alignment: .top, spacing: 6) {
                if !store.profile.leftHanded { previewRails }
                previewGames
                if store.profile.leftHanded { previewRails }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.text.opacity(0.3), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewRails: some View {
        HStack(alignment: .top, spacing: 5) {
            VStack(spacing: 5) {
                ForEach(shownSystems.prefix(7), id: \.self) { system in
                    Text(system.title)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
                        .padding(.horizontal, 5)
                        .background(system == shownSystems.first ? palette.selected : palette.tile)
                }
            }.frame(maxWidth: 105)
            if showCategories {
                VStack(spacing: 5) {
                    ForEach(["All ROMs", "Collections", "Favourites", "Recently played"], id: \.self) { category in
                        Text(category)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
                            .padding(.horizontal, 5)
                            .background(category == "All ROMs" ? palette.selected : palette.tile)
                    }
                }.frame(maxWidth: 98)
            }
        }
        .frame(maxWidth: showCategories ? 209 : 105, alignment: .leading)
    }

    private var previewGames: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Games").font(.system(size: 11, weight: .bold))
                Spacer()
                Image(systemName: "magnifyingglass")
                Image(systemName: "gearshape")
            }.font(.system(size: 11))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: compact ? 3 : 2), spacing: 5) {
                ForEach(Array(store.data.games.lazy.filter { game in
                    !(store.profile.hiddenSystems ?? []).contains(game.system) &&
                    GameCatalogue.shared.isListed(game)
                }.prefix(6))) { game in
                    VStack(spacing: 3) {
                        GameArtwork(game: game).frame(maxWidth: .infinity, maxHeight: compact ? 45 : 62)
                        Text(game.displayTitle)
                            .font(.system(size: compact ? 8 : 10))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: compact ? 61 : 80)
                    .padding(3)
                    .background(palette.tile)
                }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .top)
    }

    private func binding(_ key: WritableKeyPath<PlayerProfile, Double?>) -> Binding<Double> {
        Binding(get: { store.profile[keyPath: key] ?? 1 }, set: { value in store.updateProfile { $0[keyPath: key] = value } })
    }
}

private struct ScreensaverOptionsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var previewing = false

    var body: some View {
        Form {
            Section("Start after") {
                Picker("Idle time", selection: Binding(
                    get: { store.profile.screensaverMinutes ?? 0 },
                    set: { value in store.updateProfile { $0.screensaverMinutes = value } }
                )) {
                    Text("Off").tag(0)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                }
            }
            Section("Animated screensaver preview") {
                RetroScreensaver(preview: true)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .allowsHitTesting(false)
                Button("Preview full screen") { previewing = true }
                    .accessibilityIdentifier("screensaver-preview")
                Text("The Light logo moves across the screen. The clock remains centred; the exit message stays at the bottom.")
                    .font(.footnote)
            }
            Section {
                Text("Tap the screen or use your controller to return from the active screensaver. Your iPhone’s Auto-Lock setting still applies.")
                    .font(.footnote)
            }
        }
        .fullScreenCover(isPresented: $previewing) {
            RetroScreensaver(onExit: { previewing = false })
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button { previewing = false } label: {
                        Label("Close preview", systemImage: "xmark.circle.fill").labelStyle(.iconOnly).font(.title2)
                    }
                    .tint(.white)
                    .padding(20)
                }
        }
    }
}

private struct BIOSView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var picker = false
    var body: some View {
        Form {
            Button("Import BIOS file") { picker = true }
            Label(FileManager.default.fileExists(atPath: store.biosURL.appendingPathComponent("syscard3.pce").path) ? "PC Engine CD BIOS present" : "PC Engine CD needs syscard3.pce", systemImage: "opticaldisc")
            Text("Use your own BIOS files. Keep arcade BIOS, parent and game ZIPs together in a linked folder. Keep each CHD in its matching game subfolder. Scans skip BIOS and track files.").font(.footnote)
        }.sheet(isPresented: $picker) { DocumentPicker(multiple: false) { if let url = $0.first { store.importBIOS(url) } } }
    }
}
struct ProfilesView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    // Settings already has a NavigationStack. Only the library's full-screen
    // profile editor needs its own; nesting stacks broke destination handling.
    var standalone = false
    @State private var name = ""
    @State private var rename = ""

    var body: some View {
        Group {
            if standalone {
                NavigationStack {
                    editor
                        .navigationTitle("Profiles")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            } else {
                editor
            }
        }
        .onAppear { rename = store.profile.name }
        .onChange(of: store.data.currentProfile) { _, _ in
            rename = store.profile.name
        }
    }

    private var editor: some View {
        Form {
            Section("Who's playing?") {
                ForEach(store.data.profiles) { player in
                    Button {
                        store.selectProfile(player.id)
                        rename = store.profile.name
                    } label: {
                        HStack {
                            Label(player.name, systemImage: "person.crop.circle")
                            Spacer()
                            if player.id == store.profile.id {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("profile-\(player.id)")
                }
            }
            Section("New player") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("profile-new-name")
                Button("Add player") {
                    store.addProfile(name)
                    name = ""
                    rename = store.profile.name
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("profile-add")
            }
            Section("Rename current player") {
                TextField("Name", text: $rename)
                    .accessibilityIdentifier("profile-rename")
                Button("Save name") {
                    let trimmed = rename.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        store.updateProfile { $0.name = String(trimmed.prefix(40)) }
                    }
                }
                .disabled(rename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section {
                Text("Players share the game library. Favourites, recently played games, colours, layouts, system order and saves are separate.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Profiles")
    }
}

struct LicensesView: View {
    private var files: [URL] { (Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "Licenses") ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent } }
    var body: some View {
        List {
            Text("Light Retro application: GPL-3.0-or-later. Emulator cores retain their own licences. Exact core revisions and corresponding source links are in the repository's ci/cores.json.").font(.footnote)
            ForEach(files, id: \.self) { url in
                NavigationLink(url.lastPathComponent) { ScrollView { Text((try? String(contentsOf: url, encoding: .utf8)) ?? "See the source repository.").font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading).padding() }.navigationTitle(url.lastPathComponent) }
            }
        }.navigationTitle("Licences")
    }
}
