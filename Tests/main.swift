import Foundation
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
check(GameSystem.recognises("Super Mario.nes",for:.nes), "NES recognition")
check(GameSystem.recognises("NES.zip",for:.nes), "Single-ROM console ZIPs supported")
check(!GameSystem.recognises("BIOS/syscard3.pce",for:.pce), "BIOS exclusion")
check(!GameSystem.recognises("syscard3.pce",for:.pce), "Loose BIOS exclusion")
check(GameSystem.recognises("games/disc.CHD",for:.pcecd), "CD extension")
check(!GameSystem.recognises("tracks/track.bin",for:.pcecd), "Do not index CD tracks")
check(!LibraryRules.safeRelativePath("../../outside.nes"), "Traversal rejection")
check(!LibraryRules.safeRelativePath("/etc/passwd"), "Absolute path rejection")
check(LibraryRules.safeRelativePath("NES/game.nes"), "Valid relative path")
let folder = UUID()
let game = Game(title:"Game",system:.nes,relativePath:"game.nes",folderID:folder)
var games = [game]
LibraryRules.upsert(Game(title:"Game",system:.nes,relativePath:"game.nes",folderID:folder),in:&games)
check(games.count==1 && games[0].id==game.id,"Rescan must preserve save identity")
LibraryRules.upsert(Game(title:"Game",system:.nes,relativePath:"game.nes",folderID:UUID()),in:&games)
check(games.count==2,"Different roots must not collide")
var data=LibraryData();data.games=games;data.profiles[0].favourites.insert(game.id)
data.profiles.append(PlayerProfile(name:"Player 2"))
let bytes=try JSONEncoder().encode(data)
let restored=try JSONDecoder().decode(LibraryData.self,from:bytes)
check(restored.profiles[0].favourites.contains(game.id),"Favourites persist")
check(restored.profiles[1].favourites.isEmpty,"Profiles stay isolated")
check(restored.games[0].id==game.id,"Stable game identity")
check(GameSystem.arcade.core == "mamearcade", "MAME must use its own engine")
check(GameSystem.n64.core == "mupen64plus_next", "N64 engine selected")
check(GameSystem.scumm.core == nil, "SCUMM remains deferred")
check(GameSystem.recognises("sf2.ZIP",for:.arcade), "MAME compressed set")
check(!GameSystem.recognises("kinst/kinst.chd",for:.arcade), "CHDs are companions to MAME ZIPs")
for ext in ["n64","z64","v64"] { check(GameSystem.recognises("game."+ext,for:.n64), "N64 byte orders") }
check(GameSystem.recognises("game.zip",for:.n64), "N64 single-ROM ZIP supported")
print("Library regression tests passed")

let catalogue = GameCatalogue(directory: URL(fileURLWithPath: "LightRetro/Resources/Catalogue"))
check(catalogue.mame.count == 31122 && catalogue.fbneo.count == 8436, "Bundle the full Android arcade title catalogues")
let streetFighter = catalogue.identify(Game(title: "sf2", system: .arcade, relativePath: "sf2.zip"))
check(streetFighter.title == "Street Fighter II: The World Warrior", "MAME shortnames get real display titles")
check(streetFighter.year == "1991" && streetFighter.maker == "Capcom", "MAME year and maker")
check(streetFighter.fileName == "sf2.zip", "Never rename the ROM")
check(catalogue.identify(Game(title: "", system: .fbneo, relativePath: "sf2.zip")).title.hasPrefix("Street Fighter II"), "FBNeo catalogue lookup")
check(LibraryRules.displayName("Super_Mario_64 (USA) [!].z64") == "Super Mario 64", "Console tags and underscores cleaned")
check(LibraryRules.displayName("Example (Special Edition).nes") == "Example (Special Edition)", "Keep meaningful title parentheses")
check(catalogue.identify(Game(title: "", system: .arcade, relativePath: "unknown_game.zip")).title == "unknown game", "Unknown ROM fallback")
check(GameSystem.detect(rootName: "ROMs", relativePath: "SNES/RPG/game.zip") == .snes, "Nested console ZIP detection")
check(GameSystem.detect(rootName: "N64", relativePath: "Mario.zip") == .n64, "Root system detection")
check(GameSystem.detect(rootName: "ROMs", relativePath: "FBNeo/sf2.zip") == .fbneo, "FBNeo distinct from MAME")
check(GameSystem.detect(rootName: "ROMs", relativePath: "MAME/kinst/kinst.chd") == nil, "Do not scan arcade CHD companions as console games")
check(GameSystem.detect(rootName: "ROMs", relativePath: "track.bin") == nil, "Unlabelled BIN is ambiguous")
check(GameSystem.detect(rootName: "Mega Drive", relativePath: "Sonic.bin") == .mega, "System override handles BIN")
check(!GameSystem.recognises("neogeo.zip", for: .arcade), "Known BIOS not displayed as games")
check(catalogue.collections.count == 9, "Android curated collections")
check(catalogue.collections.contains { $0.contains(streetFighter) }, "Curated collections use ROM identity")
let urls = GameCatalogue.artworkURLs(streetFighter)
check(!urls.isEmpty && urls.allSatisfy { $0.host == "thumbnails.libretro.com" && $0.scheme == "https" }, "Artwork requests only the cover host")
check(GameCatalogue.artworkNames(streetFighter).contains { $0.contains("Fighter II_") }, "Libretro punctuation mapping")

let fm = FileManager.default
let temp = fm.temporaryDirectory.appendingPathComponent("LightRetro-Scanner-" + UUID().uuidString)
try fm.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: temp) }
func fixture(_ path: String, _ text: String = "fixture, not a ROM") throws {
    let url = temp.appendingPathComponent(path)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}
try fixture("MAME/sf2.zip"); try fixture("MAME/neogeo.zip"); try fixture("MAME/kinst/kinst.chd")
try fixture("N64/Mario.zip"); try fixture("SNES/Platformers/game.sfc"); try fixture("BIOS/syscard3.pce")
try fixture("SNES/images/cover.png"); try fixture("SNES/covers/fake.sfc"); try fixture("unknown.txt")
try fixture("SNES/gamelist.xml", """
<gameList><game><path>./Platformers/game.sfc</path><name>My proper title</name><desc>A &amp; B</desc><publisher>Studio</publisher><releasedate>19901201T000000</releasedate><image>./images/cover.png</image></game><game><path>../../escape.nes</path><name>Unsafe</name></game></gameList>
""")
let linked = GameFolder(name: "ROMs", system: .arcade, bookmark: Data(), detectSystems: true)
let result = try FolderScanner.scan(folder: linked, root: temp, catalogue: catalogue)
check(result.games.count == 3, "Recursive scan skips artwork, BIOS, CHDs and unsupported files")
let snes = result.games.first { $0.system == .snes }!
check(snes.title == "My proper title" && snes.summary == "A & B" && snes.localArtworkPath == "SNES/images/cover.png", "Read local gamelist metadata")
check(snes.year == "1990" && snes.maker == "Studio", "Read gamelist maker and year")
var prior = result.games
prior[0].customTitle = "My saved edit"; prior[0].artwork = "custom.jpg"
let previousID = prior[0].id
check(FolderScanner.merge(result.games, into: &prior) == 0 && prior.count == 3, "Repeated scans do not duplicate")
check(prior[0].id == previousID && prior[0].customTitle == "My saved edit" && prior[0].artwork == "custom.jpg", "Rescans keep saves and manual choices")
check(GamelistReader.read(temp.appendingPathComponent("SNES/gamelist.xml"), root: temp).count == 1, "Reject metadata paths escaping selected root")
try fixture("SNES/unsafe.xml", "<gameList><game><path>./Platformers/game.sfc</path><image>../../outside.jpg</image></game></gameList>")
check(GamelistReader.read(temp.appendingPathComponent("SNES/unsafe.xml"), root: temp).first?.image == nil, "Reject image traversal")
try fm.createSymbolicLink(at: temp.appendingPathComponent("linked"), withDestinationURL: temp.appendingPathComponent("SNES"))
let withSymlink = try FolderScanner.scan(folder: linked, root: temp, catalogue: catalogue)
check(withSymlink.games.count == 3, "Do not follow symlink directories")
// Omitted optional fields are how 0.2 libraries actually look on disk.
var legacy = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
legacy.removeValue(forKey: "downloadArtwork")
legacy["profiles"] = (legacy["profiles"] as! [[String: Any]]).map { record in record.filter { !["compactTiles", "colourHex", "colourStrength", "brightness", "darkText", "hiddenSystems", "screensaverMinutes"].contains($0.key) } }
let migrated = try JSONDecoder().decode(LibraryData.self, from: JSONSerialization.data(withJSONObject: legacy))
check(migrated.profiles[0].favourites.contains(game.id) && migrated.games[0].id == game.id, "Old library compatibility preserves favourites and saves")
print("Folder, title, artwork matching and migration tests passed")
