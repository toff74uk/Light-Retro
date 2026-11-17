import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var controllers: ControllerHub
    @Environment(\.dismiss) private var dismiss
    @State private var biosPicker = false
    @State private var addFolder = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Make it yours") {
                    Picker("Colour", selection: Binding(get: { store.profile.theme }, set: { value in store.updateProfile { $0.theme = value } })) {
                        Text("Retro orange").tag("orange"); Text("Light blue").tag("blue"); Text("Pink").tag("pink"); Text("Yellow").tag("yellow")
                    }
                    Toggle("Left-handed navigation", isOn: Binding(get: { store.profile.leftHanded }, set: { value in store.updateProfile { $0.leftHanded = value } }))
                    NavigationLink("Players") { ProfilesView() }
                }
                Section("Folder setup") {
                    ForEach(store.data.folders) { folder in
                        VStack(alignment: .leading) { Text(folder.name); Text(folder.system.title).font(.caption).foregroundStyle(.secondary) }
                    }
                    Button("Add games or link a folder") { addFolder = true }
                    Button("Rescan linked folders") { store.rescan() }
                    Text("A rescan adds new games and keeps your existing saves and favourites. It does not remove games from disconnected drives.").font(.caption).foregroundStyle(.secondary)
                }
                Section("BIOS & resources") {
                    Button("Import BIOS file") { biosPicker = true }
                    Label(FileManager.default.fileExists(atPath: store.biosURL.appendingPathComponent("syscard3.pce").path) ? "PC Engine CD BIOS present" : "PC Engine CD needs syscard3.pce", systemImage: "opticaldisc")
                    Text("Use your own BIOS files. For arcade games, keep BIOS and parent ZIPs beside the game ZIP in a linked folder.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Controllers") {
                    if controllers.names.isEmpty { Text("Pair a controller in iPhone Settings → Bluetooth, or connect it by USB.") }
                    ForEach(Array(controllers.names.enumerated()), id: \.offset) { index, name in Text("Player \(index+1): \(name)") }
                    Text(controllers.pressed.isEmpty ? "Press a button to test" : "Pressed: \(controllers.pressed.sorted().map(String.init).joined(separator: ", "))").font(.caption.monospaced())
                    Text("Library: D-pad moves, A / Cross plays, X / Square favourites, shoulders switch systems. During play: L1 + R1 + Start opens the pause menu. Touch remains available in settings and file pickers.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Your saves") {
                    Text("Each player has separate battery saves and save states. Save & Exit writes an automatic state; the pause menu also has three manual slots. Back up the Saves folder in Files → On My iPhone → Light Retro.").font(.footnote)
                    ShareLink("Share saves folder", item: store.savesURL)
                }
                Section("About") {
                    Text("Light Retro · iPhone 0.2 (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                    Text("Native iPhone port based on Android 2.10. No ROMs or BIOS files included. MAME 0.289 and N64 support are experimental. SCUMM is planned for later.").font(.footnote)
                    NavigationLink("Open-source licences") { LicensesView() }
                    Link("Source code & build instructions", destination: URL(string: "https://github.com/toff74uk/Light-Retro")!)
                }
            }.navigationTitle("Settings")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save & close") { store.persist(); dismiss() } } }
                .sheet(isPresented: $biosPicker) { DocumentPicker(multiple: false) { if let url = $0.first { store.importBIOS(url) } } }
                .sheet(isPresented: $addFolder) { AddGamesView(initialSystem: .nes) }
        }
    }
}

struct ProfilesView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var rename = ""
    var body: some View {
        NavigationStack {
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
            }.navigationTitle("Players").onAppear { rename = store.profile.name }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
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
