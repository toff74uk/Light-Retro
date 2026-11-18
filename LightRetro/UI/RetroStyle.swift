import SwiftUI

struct RetroPalette {
    let profile: PlayerProfile
    static let colours: [(String, String)] = [("Retro orange", "FF6025"), ("Light blue", "008CDA"), ("Pink", "FFD9E9"), ("Yellow", "FFF1A6"), ("Red", "EF5350"), ("Rose", "EC407A"), ("Purple", "AB47BC"), ("Violet", "7E57C2"), ("Indigo", "5C6BC0"), ("Sky blue", "42A5F5"), ("Azure", "29B6F6"), ("Cyan", "26C6DA"), ("Teal", "26A69A"), ("Green", "66BB6A"), ("Lime", "9CCC65"), ("Chartreuse", "D4E157"), ("Lemon", "FFEE58"), ("Gold", "FFCA28"), ("Coral", "FF7043"), ("Cocoa", "8D6E63"), ("Slate", "78909C"), ("Silver", "B0BEC5"), ("Pearl", "EEEEEE"), ("Charcoal", "555555"), ("Soft rose", "F8BBD0"), ("Lavender", "E1BEE7"), ("Lilac", "D1C4E9"), ("Ice blue", "BBDEFB"), ("Ice cyan", "B2EBF2"), ("Mint", "B2DFDB"), ("Sage", "C8E6C9"), ("Peach", "FFE0B2")]
    var base: UIColor {
        let defaults = ["orange": "FF6025", "blue": "008CDA", "pink": "FFD9E9", "yellow": "FFF1A6"]
        let rgb = UInt32(profile.colourHex ?? defaults[profile.theme] ?? "FF6025", radix: 16) ?? 0xFF6025
        return UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
    func tone(_ value: CGFloat = 1, saturation: CGFloat = 1) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(min(1, s * CGFloat(profile.colourStrength ?? 1) * saturation)), brightness: Double(min(1, b * CGFloat(profile.brightness ?? 1) * value)))
    }
    var text: Color { profile.darkText == true ? Color(white: 0.06) : .white }
    var background: LinearGradient { LinearGradient(colors: [tone(), tone(0.98, saturation: 1.25)], startPoint: .topLeading, endPoint: .bottomTrailing) }
    var tile: Color { tone(0.85, saturation: 2.2) }
    var selected: Color { tone(0.74, saturation: 3) }
}

struct GameArtwork: View {
    let game: Game
    @EnvironmentObject private var store: LibraryStore
    @State private var picture: UIImage?
    var body: some View {
        Group {
            if let picture { Image(uiImage: picture).resizable().scaledToFit() }
            else { Image("system_\(game.system.rawValue)").resizable().scaledToFit().padding(7).opacity(0.85) }
        }
        .accessibilityLabel("\(game.displayTitle) artwork")
        .task(id: "\(game.id)|\(game.customTitle ?? "")|\(game.artwork ?? "")|\(store.artworkRevision)|\(store.data.downloadArtwork ?? true)") {
            picture = nil
            let data = await ArtworkLoader.shared.load(game, root: store.artworkRoot(for: game), manual: game.artwork.map { store.artworkURL.appendingPathComponent($0) }, downloads: store.data.downloadArtwork ?? true)
            if !Task.isCancelled { picture = data.flatMap { UIImage(data: $0) } }
        }
    }
}

struct RetroTile: View {
    var title: String
    var symbol: String
    var selected = false
    var action: () -> Void
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        let palette = RetroPalette(profile: store.profile)
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(.orange)
                    .frame(width: 43, height: 43).background(Color(red: 0.08, green: 0.14, blue: 0.19), in: RoundedRectangle(cornerRadius: 8))
                Text(title).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2).frame(height: 31)
            }.frame(maxWidth: .infinity).padding(.vertical, 9).foregroundStyle(palette.text)
                .background(selected ? palette.selected : palette.tile)
                .overlay(Rectangle().stroke(selected ? palette.text : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityIdentifier("settings-" + title)
    }
}
