import SwiftUI
import AVFoundation
import GameController

@MainActor final class GameSession: ObservableObject {
    let engine = RetroEngine()
    @Published private(set) var configuring = false
    @Published private(set) var options: [LREmulatorOption] = []
    @Published var paused = true
    @Published var loaded = false
    @Published var message: String?
    @Published var slot = 1
    @Published var hasResume = false
    @Published var fbneoInputs: [Int] = []
    @Published var megaButtons = 6
    @Published var activeSystem: GameSystem?
    @Published var displayAspect = 4.0 / 3.0
    private var access: GameAccess?
    private var saves: URL?
    func open(_ original: Game, store: LibraryStore, input: ControllerHub, useMAME: Bool = false) {
        guard !loaded else { return }
        engine.displayAspectChanged = { [weak self] aspect in self?.displayAspect = aspect }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-preview") && arguments.contains("--paused-game") { loaded = true; return }
        #endif
        do {
            let access = try store.accessGame(original)
            var game = store.resolveArcadeRoute(original, archive: access.url)
            if useMAME && game.system == .fbneo {
                let previous = game
                game.system = .arcade
                game.preserveSaves(from: previous)
            }
            activeSystem = game.system
            guard let core = game.system.core else { throw StoreError.message(game.system.help) }
            let saves = try store.saveDirectory(for: game)
            if game.system == .mega { megaButtons = TouchPad.megaDriveButtonCount(rom: access.url) }
            if game.system == .fbneo {
                engine.arcadeInputsChanged = { [weak self] ids in self?.fbneoInputs = ids.map(\.intValue) }
            }
            engine.messageHandler = { [weak self] text in self?.message = text }
            if let error = engine.loadCore(core, game: access.url.path, system: store.biosURL.path, save: saves.path) {
                if let set = GameCatalogue.shared.discSet(for: game) {
                    throw StoreError.message(error + "\n\n" + ArcadeFileCheck.report(game: game, archive: access.url, set: set))
                }
                throw StoreError.message(error)
            }
            self.access = access; self.saves = saves; loaded = true
            hasResume = FileManager.default.fileExists(atPath: saves.appendingPathComponent("auto.state").path)
            input.onMenuInput = nil
            input.analogueGameplay = game.system == .n64
            input.onPause = { [weak self] in self?.pause() }
            input.onGameInput = { [weak self] ports in
                guard let self, !self.paused else { return }
                for port in 0..<4 {
                    for button in 0..<16 { self.engine.setButton(button, pressed: ports[port].buttons[button] ?? false, port: port) }
                    for stick in 0..<2 { for axis in 0..<2 {
                        self.engine.setAxis(axis, value: ports[port].sticks[stick][axis], stick: stick, port: port)
                    } }
                }
            }
            store.played(game)
            if !hasResume { resume() }
        } catch { message = error.localizedDescription }
    }
    func openSetup(for system: GameSystem) {
        if system == .arcade {
            engine.clearButtons()
            if engine.toggleMAMEMenu() { return }
        }
        pause()
        refreshOptions()
        configuring = true
    }
    private func refreshOptions() {
        options = engine.emulatorOptions().sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func setOption(_ key: String, value: String) {
        if !engine.setOption(key, value: value) { message = "This setting is no longer available." }
        refreshOptions()
    }
    func resume() { guard loaded else { return }; configuring = false; hasResume = false; paused = false; engine.start(); UIApplication.shared.isIdleTimerDisabled = true }
    func pause() { configuring = false; engine.pause(); paused = true; UIApplication.shared.isIdleTimerDisabled = false; if !engine.saveRAM() { message = "Could not save battery progress. Check your iPhone's free space." } }
    func restoreAutomatic() { guard let saves else { return }; if engine.loadState(saves.appendingPathComponent("auto.state").path) { hasResume = false; resume() } else { message = "This automatic save could not be loaded. It may belong to an older engine build." } }
    func saveSlot() { guard let saves else { return }; message = engine.saveState(saves.appendingPathComponent("slot-\(slot).state").path) ? "Saved to slot \(slot)." : "The state could not be saved. Check free space; this game may not support save states." }
    func loadSlot() { guard let saves else { return }; if engine.loadState(saves.appendingPathComponent("slot-\(slot).state").path) { resume() } else { message = "Slot \(slot) is empty or incompatible with this game engine." } }
    @discardableResult func automaticSave() -> Bool {
        // Preserve the existing automatic state until the player chooses to play.
        guard loaded, !hasResume, let saves else { return true }
        let ram = engine.saveRAM()
        let state = engine.saveState(saves.appendingPathComponent("auto.state").path)
        if !ram || !state { message = "Some progress could not be saved. Check your free space. You can retry, or exit without an automatic state." }
        return ram && state
    }
    func stop(input: ControllerHub) {
        input.onGameInput = nil; input.onPause = nil; input.analogueGameplay = false; input.clear()
        engine.stop(); access = nil; loaded = false; UIApplication.shared.isIdleTimerDisabled = false
    }
}

struct PlayerView: View {
    let game: Game
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var input: ControllerHub
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var session = GameSession()
    @State private var showControls = true
    @State private var overlayVisible = true
    @State private var pendingHide: Task<Void, Never>?
    @State private var dpadMode = false
    @State private var confirmReset = false
    @State private var confirmDiscard = false
    private var activeSystem: GameSystem { session.activeSystem ?? game.system }
    private var automaticButtons: Int {
        switch activeSystem {
        case .mega: return session.megaButtons
        case .nes, .pce, .pcecd: return 2
        case .snes: return 4
        case .n64: return 6
        default: break
        }
        if activeSystem == .fbneo && !session.fbneoInputs.isEmpty { return min(6, max(2, session.fbneoInputs.count)) }
        return GameCatalogue.shared.arcadeButtonCount(for: game)
    }
    private var buttons: Int { store.profile.touchButtonOverride(for: game) ?? automaticButtons }
    private func changeControls(_ update: () -> Void) {
        input.clear()
        session.engine.clearButtons()
        update()
        showControls = true
        revealOverlay()
    }

    private var layoutMenu: some View {
        Menu {
            Picker("Joypad type", selection: Binding(
                get: { store.profile.touchJoypadType ?? .joystick },
                set: { value in changeControls { store.updateProfile { $0.touchJoypadType = value } } }
            )) {
                ForEach(TouchJoypadType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }.pickerStyle(.inline)
            if activeSystem.isArcade {
                Picker("Number of buttons", selection: Binding(
                    get: { buttons },
                    set: { count in
                        changeControls {
                            store.updateProfile { $0.setTouchButtonOverride(count == automaticButtons ? nil : count, for: game) }
                        }
                    }
                )) {
                    ForEach(2...6, id: \.self) { count in Text("\(count) buttons").tag(count) }
                }.pickerStyle(.inline)
            }
            if activeSystem == .n64 {
                Picker("N64 direction control", selection: $dpadMode) {
                    Text("Analogue stick").tag(false)
                    Text("D-pad").tag(true)
                }.pickerStyle(.inline)
            }
        } label: {
            Image(systemName: "circle.grid.2x2.fill")
                .font(.title2).frame(width: 44, height: 44)
        }
        .menuActionDismissBehavior(.enabled)
        .accessibilityLabel("Button layout for this game")
        .accessibilityValue("\(buttons) buttons")
        .accessibilityIdentifier("arcade-layout")
        .simultaneousGesture(TapGesture().onEnded { revealOverlay() })
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            if overlayVisible && showControls { systemKeys }
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                layoutMenu
                Button {
                    revealOverlay()
                    showControls.toggle()
                    input.clear()
                    session.engine.clearButtons()
                } label: {
                    Image(systemName: "gamecontroller").font(.title2).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Show or hide touch controls")
                .accessibilityIdentifier("touch-controls-toggle")
                Button { input.clear(); session.pause() } label: {
                    Image(systemName: "pause.circle.fill").font(.title2).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Pause game").accessibilityIdentifier("game-pause")
                Button {
                    input.clear()
                    revealOverlay()
                    session.openSetup(for: activeSystem)
                } label: {
                    Image(systemName: "gearshape.fill").font(.title2).frame(width: 44, height: 44)
                }
                .accessibilityLabel(activeSystem == .arcade ? "MAME setup" : "Emulator setup")
                .accessibilityIdentifier("emulator-setup")
            }
            .accessibilityElement(children: .contain)
        }
        .foregroundStyle(.white.opacity(overlayVisible ? 0.85 : 0.62))
        .frame(height: 48)
        .padding(.horizontal, 6)
    }

    private func revealOverlay() { refreshOverlay(touching: input.touchingControls) }

    private func refreshOverlay(touching: Bool) {
        pendingHide?.cancel()
        guard !session.paused else { return }
        overlayVisible = true
        guard !touching, session.message == nil else { return }
        #if DEBUG
        // Geometry checks take multiple accessibility snapshots. Keep controls
        // present for that fixture; the separate idle test uses the real timer.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-preview") && arguments.contains("--ui-layout-check") { return }
        #endif
        pendingHide = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { overlayVisible = false }
        }
    }

    private var touchPad: some View {
        TouchControls(system: activeSystem, count: buttons, fbneoInputs: session.fbneoInputs,
                      dpadMode: $dpadMode, onModeChange: revealOverlay)
            .id(store.profile.touchJoypadType ?? .joystick)
    }

    var body: some View {
        GeometryReader { geometry in
            let portrait = geometry.size.height > geometry.size.width
            // Reserve the pad and toolbar even when they fade so the game never jumps.
            let videoHeight = portrait
                ? min(geometry.size.width / max(0.1, session.displayAspect),
                      max(1, geometry.size.height - geometry.safeAreaInsets.bottom - 268))
                : geometry.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { revealOverlay() }
                VStack(spacing: 0) {
                    GameScreen(engine: session.engine)
                        .frame(width: geometry.size.width, height: videoHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .overlay {
                            if !session.paused {
                                Color.clear.contentShape(Rectangle())
                                    .onTapGesture { revealOverlay() }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Game screen")
                                    .accessibilityHint("Tap to show the game controls")
                                    .accessibilityIdentifier("game-viewport")
                            }
                        }
                    if portrait {
                        if !session.paused {
                            toolbar
                            if showControls && overlayVisible {
                                touchPad.frame(height: 212).padding(.horizontal, 12)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if !portrait && !session.paused {
                    VStack(spacing: 0) {
                        toolbar.padding(.horizontal, max(6, geometry.safeAreaInsets.leading))
                        Spacer(minLength: 0)
                        if showControls && overlayVisible {
                            touchPad.frame(height: min(220, max(0, geometry.size.height - 64)))
                                .padding(.horizontal, max(14, geometry.safeAreaInsets.leading))
                                .padding(.bottom, max(12, geometry.safeAreaInsets.bottom))
                        }
                    }
                }
                if session.configuring {
                    setupPanel
                } else if session.paused {
                    pauseMenu.padding(12).frame(maxWidth: 450, maxHeight: 480)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)).padding(8)
                }
            }
            .onChange(of: portrait) { _ in revealOverlay() }
        }.ignoresSafeArea().statusBarHidden()
            .onAppear { showControls = input.names.isEmpty; session.open(game, store: store, input: input) }
            .onChange(of: dpadMode) { _ in input.clear(); session.engine.clearButtons(); revealOverlay() }
            .onChange(of: session.paused) { _ in revealOverlay() }
            .onChange(of: session.message) { _ in revealOverlay() }
            .onReceive(input.$touchingControls.dropFirst()) { held in refreshOverlay(touching: held) }
            .onDisappear {
                pendingHide?.cancel()
                if session.loaded { session.pause(); session.automaticSave() }
                session.stop(input: input)
            }
            .onChange(of: phase) { value in
                if value == .inactive {
                    input.clear(); session.pause(); session.automaticSave(); session.engine.finishGraphics()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in input.clear(); session.pause() }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in input.clear(); session.pause(); showControls = true }
            .alert("Light Retro", isPresented: Binding(get: { session.message != nil }, set: { if !$0 { session.message = nil } })) { Button("OK") { session.message = nil } } message: { Text(session.message ?? "") }
            .confirmationDialog("Restart this game? Unsaved progress will be lost.", isPresented: $confirmReset, titleVisibility: .visible) { Button("Restart", role: .destructive) { session.engine.resetGame(); session.hasResume = false; session.resume() } }
            .alert("Exit without saving a new state?", isPresented: $confirmDiscard) {
                Button("Exit", role: .destructive) { session.stop(input: input); dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your previous automatic state and in-game battery saves are kept.") }
    }
    private var systemKeys: some View {
        HStack(spacing: 2) {
            if activeSystem != .n64 && (activeSystem != .mega || buttons == 6) {
                let label = activeSystem.isArcade ? "COIN" : (activeSystem == .mega ? "MODE" : "SELECT")
                SystemKey(label: label, id: 2, width: 52)
            }
            SystemKey(label: activeSystem == .pce || activeSystem == .pcecd ? "RUN" : "START", id: 3, width: 52)
        }
        .accessibilityIdentifier("game-system-keys")
    }

    private var setupPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(activeSystem.title) setup").font(.headline)
                Spacer()
                Button("Done") { input.clear(); session.resume() }
                    .frame(minHeight: 44).accessibilityIdentifier("setup-done")
            }.padding(.horizontal)
            if session.options.isEmpty {
                ContentUnavailableView("No emulator options", systemImage: "gearshape",
                    description: Text("This emulator has no adjustable settings for this game."))
            } else {
                List {
                    Section {
                        ForEach(session.options, id: \.key) { option in
                            VStack(alignment: .leading, spacing: 4) {
                                Picker(option.title, selection: Binding(
                                    get: { option.value },
                                    set: { session.setOption(option.key, value: $0) }
                                )) {
                                    ForEach(option.values.indices, id: \.self) { index in
                                        Text(option.labels[index]).tag(option.values[index])
                                    }
                                }.pickerStyle(.menu)
                                if !option.helpText.isEmpty {
                                    Text(option.helpText).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Saved for this game. Some changes take effect when you reopen it.").textCase(nil)
                    }
                }.listStyle(.plain)
            }
        }
        .frame(maxWidth: 600, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(8)
    }

    private var pauseMenu: some View {
        VStack(spacing: 8) {
            Text(game.displayTitle).font(.headline).lineLimit(1)
            if let set = GameCatalogue.shared.discSet(for: game) {
                HStack {
                    Button("Check game files") {
                        do {
                            let access = try store.accessGame(game)
                            var selected = game
                            selected.system = activeSystem
                            session.message = ArcadeFileCheck.report(game: selected, archive: access.url, set: set)
                        } catch { session.message = error.localizedDescription }
                    }
                    if activeSystem == .fbneo {
                        Button("Play with MAME") {
                            if session.loaded { session.stop(input: input) }
                            session.open(game, store: store, input: input, useMAME: true)
                        }
                    }
                }.buttonStyle(.bordered)
            }
            if session.loaded {
                ScrollView {
                    VStack(spacing: 12) {
                        if session.hasResume { Button("Resume saved game") { session.restoreAutomatic() }.buttonStyle(.borderedProminent) }
                        Button(session.hasResume ? "Start fresh" : "Continue playing") { session.hasResume = false; input.clear(); session.resume() }.buttonStyle(.borderedProminent)
                        Picker("Save slot", selection: $session.slot) { ForEach(1...3, id: \.self) { Text("Slot \($0)").tag($0) } }.pickerStyle(.segmented)
                        HStack { Button("Save state") { session.saveSlot() }; Spacer(); Button("Load state") { session.loadSlot() } }.buttonStyle(.bordered)
                        Toggle("Touch controls", isOn: $showControls)
                        layoutMenu
                        ControlOptions()
                        Button("Restart game") { confirmReset = true }
                    }.padding(4)
                }
                Divider()
                HStack(spacing: 8) {
                    Button { session.pause(); if session.automaticSave() { session.stop(input: input); dismiss() } } label: {
                        Text("Save & exit").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("pause-save-exit")
                    Button(role: .destructive) { confirmDiscard = true } label: {
                        Text("Exit without saving").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered).accessibilityIdentifier("pause-exit-without-saving")
                }
            } else {
                Button("Back to games") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
    }
}

struct GameScreen: UIViewRepresentable {
    let engine: RetroEngine
    func makeUIView(context: Context) -> UIView { engine.videoView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct TouchControls: View {
    let system: GameSystem
    let count: Int
    let fbneoInputs: [Int]
    @Binding var dpadMode: Bool
    let onModeChange: () -> Void
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        let face = TouchPad.face(system: system, count: count, fbneoInputs: fbneoInputs)
        GeometryReader { area in
            let width = area.size.width
            let height = min(220, area.size.height)
            let pad = min(158, width * 0.36, height * 0.82)
            let spacingBudget: CGFloat = 8
            let columns = (face.map(\.column).max() ?? 0) + 1
            let rows = (face.map(\.row).max() ?? 0) + 1
            let shoulders = system == .snes || system == .n64
            let step = min(store.profile.largeTouchButtons == true ? 66 : 58,
                           (width - pad - spacingBudget - 10) / columns,
                           (height - (shoulders ? 48 : 0)) / rows)
            TouchLayout(system: system, face: face, step: max(1, step), padWidth: pad,
                        response: store.profile.controlResponse ?? .standard,
                        joypadType: store.profile.touchJoypadType ?? .joystick,
                        dpadMode: $dpadMode, onModeChange: onModeChange)
                .frame(maxHeight: height).frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct TouchLayout: View {
    let system: GameSystem
    let face: [PadButton]
    let step: CGFloat
    let padWidth: CGFloat
    let response: ControlResponse
    let joypadType: TouchJoypadType
    @Binding var dpadMode: Bool
    let onModeChange: () -> Void
    private var stickMode: TouchStickMode {
        if system.isArcade { return .arcade }
        return system == .n64 && !dpadMode ? .analogue : .directional
    }
    @EnvironmentObject private var input: ControllerHub

    var body: some View {
        VStack(spacing: 4) {
            if system == .snes || system == .n64 {
                HStack {
                    SystemKey(label: "L", id: 10, width: 48)
                    if system == .n64 { SystemKey(label: "Z", id: 12, width: 48) }
                    Spacer()
                    if system == .n64 {
                        Button(dpadMode ? "D-PAD" : "STICK") { onModeChange(); dpadMode.toggle(); input.clear() }
                            .font(.caption2.bold()).buttonStyle(.bordered).tint(.white)
                    }
                    SystemKey(label: "R", id: 11, width: 48)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 0) {
                TouchStick(response: response, mode: stickMode, joypadType: joypadType)
                    .frame(width: padWidth, height: padWidth)
                Spacer(minLength: 2)
                faceButtons
            }
        }
    }

    private var faceButtons: some View {
        let width = ((face.map(\.column).max() ?? 0) + 1) * step
        let height = ((face.map(\.row).max() ?? 0) + 1) * step
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: width, height: height).allowsHitTesting(false)
            ForEach(face, id: \.input) { button in
                faceKey(button).offset(x: button.column * step, y: button.row * step)
            }
        }
    }

    private func colour(_ button: PadButton) -> Color {
        switch system {
        case .nes, .pce, .pcecd: return .red
        case .snes:
            switch button.label { case "X": return .blue; case "Y": return .green; case "A": return .red; default: return .yellow }
        case .n64:
            switch button.label { case "A": return .blue; case "B": return .green; default: return .yellow }
        case .arcade, .fbneo: return .orange
        default: return .gray
        }
    }

    private func faceKey(_ button: PadButton) -> some View {
        let down: Bool
        let change: (Bool) -> Void
        switch button.input {
        case .digital(let id):
            down = input.pressed.contains(id)
            change = { input.setTouch(id, down: $0) }
        case .cDirection(let id):
            down = input.pressedC.contains(id)
            change = { input.setTouchC(id, down: $0) }
        }
        return PadKey(label: button.label, tint: colour(button), down: down,
                      width: step, height: step, fontSize: min(19, step * 0.4), change: change)
            .accessibilityLabel(system.isArcade ? "Button " + button.label : button.label)
            .accessibilityIdentifier("pad-" + button.label)
    }

}

private struct SystemKey: View {
    let label: String
    let id: Int
    let width: CGFloat
    @EnvironmentObject private var input: ControllerHub
    var body: some View {
        PadKey(label: label, tint: .gray, down: input.pressed.contains(id),
               width: width, height: 44, fontSize: label.count > 2 ? 12 : 17) {
            input.setTouch(id, down: $0)
        }
    }
}

// Every gameplay key uses the same full-cell contact area as the N64 face buttons.
private struct PadKey: View {
    let label: String
    let tint: Color
    let down: Bool
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat
    let change: (Bool) -> Void

    var body: some View {
        Text(label).font(.system(size: fontSize, weight: .bold, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.white)
            .frame(width: max(1, width - 4), height: max(1, height - 4))
            .background {
                Capsule().fill(.black.opacity(0.60))
                Capsule().fill(tint.opacity(down ? 0.95 : 0.43))
                Capsule().strokeBorder(tint.opacity(0.95), lineWidth: down ? 3 : 1.5)
            }
            .frame(width: width, height: height)
            .opacity(0.76)
            .overlay { TouchButtonSurface(change: change) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label).accessibilityAddTraits(.isButton)
            .onDisappear { change(false) }
    }
}

private struct TouchButtonSurface: UIViewRepresentable {
    let change: (Bool) -> Void

    final class Surface: UIView {
        var change: ((Bool) -> Void)?
        private var contacts = Set<UITouch>()

        private func setContacts(_ next: Set<UITouch>) {
            let wasDown = !contacts.isEmpty
            contacts = next
            let isDown = !next.isEmpty
            if wasDown != isDown { change?(isDown) }
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            setContacts(contacts.union(touches))
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            let inside = touches.filter { bounds.contains($0.location(in: self)) }
            setContacts(contacts.subtracting(touches).union(inside))
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            setContacts(contacts.subtracting(touches))
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            setContacts(contacts.subtracting(touches))
        }
        func reset() { setContacts([]) }
    }
    func makeUIView(context: Context) -> Surface {
        let surface = Surface()
        surface.isAccessibilityElement = false
        surface.isMultipleTouchEnabled = true
        surface.isExclusiveTouch = false
        return surface
    }
    func updateUIView(_ surface: Surface, context: Context) { surface.change = change }
    static func dismantleUIView(_ surface: Surface, coordinator: ()) { surface.reset(); surface.change = nil }
}

struct TouchStick: View {
    let response: ControlResponse
    let mode: TouchStickMode
    var joypadType: TouchJoypadType = .joystick
    @EnvironmentObject private var input: ControllerHub
    @State private var offset = CGSize.zero
    @State private var movement = FingerMovement()
    @GestureState private var stickDown = false
    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width,proxy.size.height) / 2
            ZStack {
                Circle().fill(.white.opacity(0.10))
                Circle().strokeBorder(.white.opacity(0.25),lineWidth: 1)
                Circle().fill(.white.opacity(0.35)).frame(width: 56,height: 56).offset(offset)
            }.opacity(0.76).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($stickDown) { _, down, _ in down = true }
                    .onChanged { value in
                        input.setStickContact(true)
                        if joypadType == .continuous {
                            let direction = movement.move(x: Float(value.location.x), y: Float(value.location.y))
                            offset = CGSize(width: CGFloat(direction.0) * radius * 0.55,
                                            height: CGFloat(direction.1) * radius * 0.55)
                            input.moveTouchStick(x: direction.0, y: direction.1, mode: mode, response: response)
                            return
                        }
                        let dx = value.location.x-radius, dy = value.location.y-radius
                        let distance = sqrt(dx*dx+dy*dy), travel = max(1,radius-28)
                        let scale = max(1,distance/travel)
                        offset = CGSize(width: dx/scale,height: dy/scale)
                        input.moveTouchStick(x: Float(offset.width / travel), y: Float(offset.height / travel),
                                             mode: mode, response: response)
                    }.onEnded { _ in centre() })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(joypadType == .continuous ? "Continuous finger movement" : (mode == .analogue ? "N64 analogue stick" : "Directional joystick"))
                .accessibilityIdentifier("pad-stick")
                .onChange(of: stickDown) { down in if !down { centre() } }
                .onChange(of: mode) { _ in centre() }
                .onChange(of: joypadType) { _ in centre() }
                .onDisappear { centre() }
        }
    }

    private func centre() {
        offset = .zero
        movement.reset()
        input.setStickContact(false)
        input.moveTouchStick(x: 0, y: 0, mode: mode, response: response)
    }
}
