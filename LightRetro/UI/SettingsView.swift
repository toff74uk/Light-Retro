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
    @State private var previewingScreensaver = false
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
                if previewingScreensaver { previewingScreensaver = false; return }
                if !path.isEmpty { if button == 8 { path.removeLast() }; return }
                if button == 8 || button == 3 { store.persist(); dismiss(); return }
                if button == 0 { path.append(SettingsPage.allCases[selected]); return }
                let delta = [4: -columns, 5: columns, 6: -1, 7: 1][button] ?? 0
                selected = min(SettingsPage.allCases.count - 1, max(0, selected + delta))
            }
        }
        .fullScreenCover(isPresented: $previewingScreensaver) {
            ScreensaverView { previewingScreensaver = false }
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
                Section("Game tiles") { Toggle("Compact tiles", isOn: profileBinding(\.compactTiles, default: true)) }
                Section {
                    ForEach(store.profile.orderedSystems) { system in
                        Toggle(system.title, isOn: Binding(get: { !(store.profile.hiddenSystems ?? []).contains(system) }, set: { visible in
                            store.updateProfile { profile in var hidden = profile.hiddenSystems ?? []; if visible { hidden.remove(system) } else { hidden.insert(system) }; profile.hiddenSystems = hidden }
                        }))
                    }
                    .onMove { offsets, destination in
                        store.updateProfile { profile in
                            var systems = profile.orderedSystems
                            systems.move(fromOffsets: offsets, toOffset: destination)
                            profile.systemOrder = systems.map(\.rawValue)
                        }
                    }
                } header: {
                    Text("System order & visibility")
                } footer: {
                    Text("Drag the handles to reorder systems for this player. Switch a system off to hide it. Its games and saves are kept.")
                }
            }
            .environment(\.editMode, .constant(.active))
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
        case .screensaver:
            Form {
                Picker("Start after", selection: profileBinding(\.screensaverMinutes, default: 0)) {
                    Text("Off").tag(0); Text("2 minutes").tag(2); Text("5 minutes").tag(5); Text("10 minutes").tag(10)
                }
                Button("Preview screensaver") { previewingScreensaver = true }
                Text("Shows the Light Retro logo and clock while the library is idle. Tap or press a controller button to return. Your iPhone’s Auto-Lock setting still applies.").font(.footnote)
            }
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
    @State private var name = ""
    @State private var rename = ""
    var body: some View {
        Form {
            Section("Who's playing?") {
                ForEach(store.data.profiles) { p in
                    Button { store.data.currentProfile = p.id; store.persist(); rename = p.name } label: {
                        HStack { Label(p.name, systemImage: "person.crop.circle"); Spacer(); if p.id == store.profile.id { Image(systemName: "checkmark.circle.fill") } }
                    }
                }
            }
            Section("New player") {
                TextField("Name", text: $name)
                Button("Add player") { store.addProfile(name); name = ""; rename = store.profile.name }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Rename current player") {
                TextField("Name", text: $rename)
                Button("Save name") { let value = rename.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { store.updateProfile { $0.name = String(value.prefix(40)) } } }
            }
            Section { Text("Players share the game library. Favourites, recently played games, colours, handedness and saves are separate.").font(.footnote) }
        }.onAppear { rename = store.profile.name }
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
