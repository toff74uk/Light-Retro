import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject private var store: LibraryStore
    let previewScreensaver: () -> Void
    @State private var strength: Double?
    @State private var brightness: Double?

    private var previewProfile: PlayerProfile {
        var profile = store.profile
        if let strength { profile.colourStrength = strength }
        if let brightness { profile.brightness = brightness }
        return profile
    }

    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 600
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Brand colour").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 2)], spacing: 2) {
                            ForEach(RetroPalette.colours, id: \.1) { name, hex in
                                swatch(name: name, hex: hex)
                            }
                        }
                        adjustment("Strength", key: \.colourStrength, draft: $strength, range: 0...1)
                        adjustment("Brightness", key: \.brightness, draft: $brightness, range: 0.3...1)
                        Toggle("Dark text", isOn: Binding(get: { store.profile.darkText ?? false }, set: { value in
                            store.updateProfile { $0.darkText = value }
                        }))
                        Divider()
                        Text("Layout").font(.headline)
                        Toggle("Left-handed navigation", isOn: Binding(get: { store.profile.leftHanded }, set: { value in
                            store.updateProfile { $0.leftHanded = value }
                        }))
                        Toggle("Compact game tiles", isOn: Binding(get: { store.profile.compactTiles ?? true }, set: { value in
                            store.updateProfile { $0.compactTiles = value }
                        }))
                    }
                    .padding(narrow ? 10 : 16)
                }
                .frame(width: geometry.size.width * (narrow ? 0.50 : 0.45))
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Library preview").font(.headline)
                        LibraryAppearancePreview(profile: previewProfile, games: store.data.games, narrow: narrow)
                        Button(action: previewScreensaver) {
                            Label("Preview screensaver", systemImage: "moon.stars")
                                .frame(minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(narrow ? 8 : 16)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func swatch(name: String, hex: String) -> some View {
        let selected = RetroPalette(profile: store.profile).baseHex == hex
        return Button { store.updateProfile { $0.colourHex = hex } } label: {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(uiColor: RetroPalette.swatch(hex)))
                .frame(height: 36)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette).foregroundStyle(.white, .black)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func adjustment(_ title: String, key: WritableKeyPath<PlayerProfile, Double?>,
                            draft: Binding<Double?>, range: ClosedRange<Double>) -> some View {
        let value = Binding<Double>(get: { draft.wrappedValue ?? store.profile[keyPath: key] ?? 1 },
                                    set: { newValue in
            if draft.wrappedValue != nil { draft.wrappedValue = newValue }
            else { store.updateProfile { $0[keyPath: key] = newValue } }
        })
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Slider(value: value, in: range, onEditingChanged: { editing in
                if editing { draft.wrappedValue = value.wrappedValue }
                else if let final = draft.wrappedValue {
                    store.updateProfile { $0[keyPath: key] = final }
                    draft.wrappedValue = nil
                }
            })
            .accessibilityLabel(title)
        }
    }
}

private struct LibraryAppearancePreview: View {
    let profile: PlayerProfile
    let games: [Game]
    let narrow: Bool
    private var palette: RetroPalette { RetroPalette(profile: profile) }

    // Bundled system artwork keeps the preview instant, including with an empty library.
    private var tiles: [(title: String, system: GameSystem)] {
        if games.isEmpty {
            return [("Street Fighter II", .arcade), ("Super Mario World", .snes),
                    ("Sonic the Hedgehog", .mega), ("Super Mario 64", .n64)]
        }
        return games.prefix(4).map { ($0.displayTitle, $0.system) }
    }

    var body: some View {
        let compact = profile.compactTiles ?? true
        let columns = compact ? (narrow ? 2 : 3) : (narrow ? 1 : 2)
        return VStack(alignment: .leading, spacing: 9) {
            Image("Brand").resizable().scaledToFit().frame(height: narrow ? 26 : 36)
            Text("All games").font(.subheadline.bold())
            HStack(alignment: .top, spacing: 5) {
                if !profile.leftHanded { navigation }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                        VStack(spacing: 2) {
                            Image("system_" + tile.system.rawValue).resizable().scaledToFit()
                                .frame(height: compact ? 20 : 32)
                            Text(tile.title).font(.system(size: narrow ? 9 : 11, weight: .semibold))
                                .lineLimit(2).multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: narrow ? 22 : 28)
                        }
                        .padding(3)
                        .background(index == 0 ? palette.selected : palette.tile)
                        .overlay { if index == 0 { Rectangle().strokeBorder(palette.text, lineWidth: 1) } }
                    }
                }
                if profile.leftHanded { navigation }
            }
        }
        .padding(narrow ? 6 : 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .foregroundStyle(palette.text)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Library preview")
        .accessibilityValue("\(RetroPalette.colours.first { $0.1 == palette.baseHex }?.0 ?? profile.theme), \(profile.leftHanded ? "navigation right" : "navigation left"), \(compact ? "compact tiles" : "large tiles")")
        .accessibilityIdentifier("appearance-preview")
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([("All games", "square.grid.2x2"), ("Favourites", "heart"), ("Recent", "clock")], id: \.0) { name, symbol in
                HStack(spacing: 3) {
                    Image(systemName: symbol)
                    if !narrow { Text(name).lineLimit(1) }
                }
                .font(.caption2)
                .padding(4)
                .frame(maxWidth: .infinity, minHeight: 23, alignment: narrow ? .center : .leading)
                .background(name == "All games" ? palette.selected : palette.tile)
            }
        }
        .frame(width: narrow ? 23 : 77)
    }
}
