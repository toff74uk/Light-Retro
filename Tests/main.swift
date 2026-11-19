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
data.profiles[0].systemOrder = ["n64", "removed", "n64", "arcade", "scumm"]
let bytes=try JSONEncoder().encode(data)
let restored=try JSONDecoder().decode(LibraryData.self,from:bytes)
check(restored.profiles[0].favourites.contains(game.id),"Favourites persist")
check(restored.profiles[1].favourites.isEmpty,"Profiles stay isolated")
check(restored.games[0].id==game.id,"Stable game identity")
check(restored.profiles[0].orderedSystems == [.n64, .arcade] + GameSystem.playable.filter { $0 != .n64 && $0 != .arcade }, "Restore custom order, skip unavailable and duplicate systems, and append new ones")
check(restored.profiles[1].orderedSystems == GameSystem.playable, "System order is per player")
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
check(snes.title == "My proper title" && snes.summary == "A & B" && snes.localArtworkPath == "SNES/images/cover.png", "Read local gamelist metadata: \(snes); parsed: \(GamelistReader.read(temp.appendingPathComponent("SNES/gamelist.xml"), root: temp))")
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
legacy["profiles"] = (legacy["profiles"] as! [[String: Any]]).map { record in record.filter { !["compactTiles", "colourHex", "colourStrength", "brightness", "darkText", "hiddenSystems", "systemOrder", "screensaverMinutes"].contains($0.key) } }
let migrated = try JSONDecoder().decode(LibraryData.self, from: JSONSerialization.data(withJSONObject: legacy))
check(migrated.profiles[0].favourites.contains(game.id) && migrated.games[0].id == game.id, "Old library compatibility preserves favourites and saves")
print("Folder, title, artwork matching and migration tests passed")

check(LibraryRules.displayName("Example (Ultimate Edition).nes") == "Example (Ultimate Edition)", "A title word starting with a region letter is not a dump tag")

let boardExamples = ["sf2": "CPS-1", "sf2ce": "CPS-1", "ssf2t": "CPS-2", "sfiii3": "CPS-3",
                     "mslug": "Neo Geo", "tnzs": "Other", "ddonpach": "Other"]
for (stem, board) in boardExamples {
    let candidate = Game(title: "Custom title", system: .fbneo, relativePath: "nested/" + stem.uppercased() + ".7Z")
    check(catalogue.isListed(candidate) && catalogue.fbneoBoard(for: candidate) == board, "Android board and clone routing")
}
check(catalogue.fbneo["pacman"] != nil, "The FBNeo title catalogue includes games outside Android's preferred list")
let allPreferred = catalogue.fbneo.keys.filter { stem in
    catalogue.isListed(Game(title: "", system: .fbneo, relativePath: stem + ".zip"))
}
check(allPreferred.count == 1839, "Use Android's preferred set list")
let arcadeRoot = temp.appendingPathComponent("Shared arcade")
for name in ["SF2CE.7Z", "tnzs.zip", "pacman.zip", "sf2_unknown.zip", "neogeo.zip"] {
    try fixture("Shared arcade/" + name)
}
let fbFolder = GameFolder(name: "FinalBurn", system: .fbneo, bookmark: Data())
let fbScan = try FolderScanner.scan(folder: fbFolder, root: arcadeRoot, catalogue: catalogue)
check(Set(fbScan.games.map(\.fileName)) == ["SF2CE.7Z", "tnzs.zip"] && fbScan.ignored == 3, "Explicit FBNeo folder shows exact Android matches only")
let mameFolder = GameFolder(name: "MAME", system: .arcade, bookmark: Data())
let mameScan = try FolderScanner.scan(folder: mameFolder, root: arcadeRoot, catalogue: catalogue)
check(mameScan.games.count == 4 && mameScan.games.allSatisfy { $0.system == .arcade }, "Explicit MAME selection is preserved")
let autoScan = try FolderScanner.scan(folder: linked, root: arcadeRoot, catalogue: catalogue)
check(Set(autoScan.games.filter { $0.system == .fbneo }.map(\.fileName)) == Set(fbScan.games.map(\.fileName)), "Shared folders route preferred archives to FBNeo")
check(Set(autoScan.games.filter { $0.system == .arcade }.map(\.fileName)) == ["pacman.zip", "sf2_unknown.zip"], "Remaining archives use MAME")

var previous = LibraryData()
previous.folders = [linked, fbFolder, mameFolder]
let oldMame = Game(title: "Custom", system: .arcade, relativePath: "SF2CE.7Z", folderID: linked.id, artwork: "custom.png", customTitle: "My SF2")
let oldFB = Game(title: "Pac-Man", system: .fbneo, relativePath: "pacman.zip", folderID: linked.id)
let rejected = Game(title: "Street Fighter II", system: .fbneo, relativePath: "sf2_unknown.zip", folderID: fbFolder.id)
let manual = Game(title: "Street Fighter II", system: .arcade, relativePath: "sf2.zip", folderID: mameFolder.id)
previous.games = [oldMame, oldFB, rejected, manual]
previous.profiles[0].favourites = [oldMame.id, rejected.id]
catalogue.updateExistingArcadeRoutes(in: &previous)
catalogue.updateExistingArcadeRoutes(in: &previous)
check(previous.games[0].system == .fbneo && previous.games[0].alternateSaveFolder == "fbneo", "Old MAME saves kept apart from FBNeo")
check(previous.games[1].system == .arcade && previous.games[1].alternateSaveFolder == "arcade", "Old FBNeo saves kept apart from MAME")
check(previous.games[2] == rejected && !catalogue.isListed(rejected), "Existing unsupported FBNeo entries are hidden without deleting their records")
check(previous.games[3] == manual && manual.alternateSaveFolder == nil, "Keep explicit MAME choices and save paths")
check(FolderScanner.merge(autoScan.games, into: &previous.games) == 2, "Rescan reuses both rerouted entries")
let updated = previous.games[0]
check(updated.id == oldMame.id && updated.artwork == oldMame.artwork && updated.customTitle == oldMame.customTitle && updated.alternateSaveFolder == "fbneo", "Rescan preserves IDs, customisations and per-core saves")
check(previous.profiles[0].favourites.contains(updated.id), "Favourites survive arcade routing")

for count in [0, 1, 199, 200, 201, 400, 401] {
    let items = (0..<count).map { Game(title: "Game \($0)", system: .nes, relativePath: "\($0).nes") }
    let pages = LibraryPage(items, index: -1).count
    check(pages == max(1, (count + 199) / 200), "200 games per page")
    let slices = (0..<pages).map { LibraryPage(items, index: $0) }
    check(slices.dropLast().allSatisfy { $0.games.count == 200 }, "Full pages hold 200 games")
    check(slices.flatMap { $0.games.map(\.id) } == items.map(\.id), "Every game appears exactly once across pages")
    check(LibraryPage(items, index: pages).index == pages - 1, "Clamp page after filtering")
}
print("Android arcade routing, existing libraries and 200-game pagination passed")

for response in ControlResponse.allCases {
    let rest = response.stick(x: 0.03, y: 0)
    check(rest.0 == 0 && rest.1 == 0, "Small stick drift stays neutral")
    let full = response.stick(x: 0, y: -1)
    check(full.0 == 0 && full.1 == -1, "Full stick travel is always available")
    check(response.touchDirections(x: 1, y: -1) == [4, 7], "Touch pad supports diagonals")
    check(response.touchDirections(x: -1, y: 0) == [6], "Sliding to another direction releases the previous one")
    check(response.touchDirections(x: 0, y: 0).isEmpty, "Touch pad centre releases all directions")
}
let steady = ControlResponse.steady.stick(x: 0.5, y: 0).0
let standard = ControlResponse.standard.stick(x: 0.5, y: 0).0
let quick = ControlResponse.quick.stick(x: 0.5, y: 0).0
check(steady < standard && standard < quick, "Sensitivity changes movement on sticks")
check(ControlResponse.quick.touchDirections(x: 0.15, y: 0) == [7] && ControlResponse.steady.touchDirections(x: 0.15, y: 0).isEmpty, "Sensitivity changes touch pad activation distance")
var tuned = PlayerProfile(name: "Player 2")
tuned.controlResponse = .steady
tuned.largeTouchButtons = true
let restoredTuning = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(tuned))
check(restoredTuning.controlResponse == .steady && restoredTuning.largeTouchButtons == true && migrated.profiles[0].controlResponse == nil, "Controls are saved per profile and older profiles use defaults")

for (stem, count) in [("1942", 2), ("ffight", 3), ("mslug", 4), ("sfiii", 6), ("sfiii3", 6), ("unlisted", 6)] {
    let title = Game(title: "Renamed", system: .arcade, relativePath: "shared/" + stem.uppercased() + ".zip")
    check(catalogue.arcadeButtonCount(for: title) == count, "Choose MAME touch controls using the original set name")
}
var padProfile = migrated.profiles[0]
var fbGame = manual
fbGame.system = .fbneo
check(padProfile.touchButtonOverride(for: manual) == nil, "Older profiles start in automatic mode")
padProfile.setTouchButtonOverride(5, for: manual)
let reopened = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(padProfile))
check(reopened.touchButtonOverride(for: fbGame) == 5, "Remember the layout across arcade cores and relaunches")
check(PlayerProfile(name: "Other").touchButtonOverride(for: manual) == nil, "Layouts are per profile")
check(reopened.touchButtonOverride(for: oldFB) == nil, "One game's override does not affect other games")
padProfile.setTouchButtonOverride(nil, for: fbGame)
check(padProfile.touchButtonOverride(for: manual) == nil, "Automatic removes the saved override")
print("Arcade button counts and saved layouts passed")

// A matching disc takes precedence over the FBNeo filename list in automatic folders.
try fixture("Shared arcade/sfiii3.zip")
let beforeDisc = try FolderScanner.scan(folder: linked, root: arcadeRoot, catalogue: catalogue)
let oldSF3 = beforeDisc.games.first { $0.fileName == "sfiii3.zip" }!
check(oldSF3.system == .fbneo, "An FBNeo archive without a disc keeps its core")
try fixture("Shared arcade/sfiii3/cap-33s-2.chd")
try fixture("Shared arcade/sfiii3/cap-33s-1.chd")
try fixture("Shared arcade/sfiii3r1.zip")
try fixture("Shared arcade/sfrush.zip")
try fixture("Shared arcade/sfrush/sfrush.chd")
try fixture("Shared arcade/sfz3ugd.zip")
try fixture("Shared arcade/sfz3ugd/gdl-0002.chd")
try fixture("Shared arcade/PC Engine CD/My Disc.chd")
let discScan = try FolderScanner.scan(folder: linked, root: arcadeRoot, catalogue: catalogue)
for stem in ["sfiii3", "sfiii3r1", "sfrush", "sfz3ugd"] {
    let found = discScan.games.first { $0.romStem == stem && $0.system.isArcade }
    check(found?.system == .arcade && found?.hasMAMEDisc == true, "Find the right own or parent disc for " + stem)
}
check(discScan.games.filter { $0.system == .pcecd }.map(\.fileName) == ["My Disc.chd"], "Only the console disc is a standalone game")
let explicitFB = try FolderScanner.scan(folder: fbFolder, root: arcadeRoot, catalogue: catalogue)
check(explicitFB.games.first { $0.romStem == "sfiii3" }?.system == .fbneo, "Explicit core choice is respected")
var stored = LibraryData()
stored.folders = [linked]
stored.games = beforeDisc.games
stored.profiles[0].favourites.insert(oldSF3.id)
_ = FolderScanner.merge(discScan.games, into: &stored.games)
catalogue.updateExistingArcadeRoutes(in: &stored)
let changed = stored.games.filter { $0.fileName == "sfiii3.zip" }
check(changed.count == 1 && changed[0].system == .arcade && changed[0].id == oldSF3.id, "Re-route existing games without a duplicate")
check(changed[0].alternateSaveFolder == "arcade" && stored.profiles[0].favourites.contains(oldSF3.id), "Keep saves and favourites when a CHD appears")
try fm.removeItem(at: arcadeRoot.appendingPathComponent("sfiii3/cap-33s-2.chd"))
let wrongRevision = try FolderScanner.scan(folder: linked, root: arcadeRoot, catalogue: catalogue)
check(wrongRevision.games.first { $0.fileName == "sfiii3.zip" }?.system == .fbneo, "A different revision alone does not match the parent")
check(wrongRevision.games.first { $0.fileName == "sfiii3r1.zip" }?.system == .arcade, "Clone still finds its own revision in the parent folder")
print("MAME disc lookup, shared-folder routes and per-core save continuity passed")

let oldCompanion = Game(title: "Old scan", system: .pcecd, relativePath: "sfiii3/cap-33s-1.chd", folderID: linked.id)
let consoleDisc = Game(title: "My disc", system: .pcecd, relativePath: "PC Engine CD/sfiii3/cap-33s-1.chd", folderID: linked.id)
stored.games += [oldCompanion, consoleDisc]
catalogue.updateExistingArcadeRoutes(in: &stored)
check(!catalogue.isListed(stored.games.first { $0.id == oldCompanion.id }!), "Hide a disc that an older mixed scan listed as a game")
check(catalogue.isListed(stored.games.first { $0.id == consoleDisc.id }!), "Preserve explicit console disc folders")
