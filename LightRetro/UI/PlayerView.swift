import SwiftUI
import AVFoundation
import GameController

@MainActor final class GameSession: ObservableObject {
    let engine = RetroEngine()
    @Published var paused = true
    @Published var loaded = false
    @Published var message: String?
    @Published var slot = 1
    @Published var hasResume = false
    @Published var fbneoInputs: [Int] = []
    @Published var megaButtons = 6
    private var access: GameAccess?
    private var saves: URL?
    func open(_ game: Game, store: LibraryStore, input: ControllerHub) {
        guard !loaded else { return }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-preview") && arguments.contains("--paused-game") { loaded = true; return }
        #endif
        do {
            guard let core = game.system.core else { throw StoreError.message(game.system.help) }
            let access = try store.accessGame(game)
            let saves = try store.saveDirectory(for: game)
            if game.system == .mega { megaButtons = TouchPad.megaDriveButtonCount(rom: access.url) }
            if game.system == .fbneo {
                engine.arcadeInputsChanged = { [weak self] ids in self?.fbneoInputs = ids.map(\.intValue) }
            }
            engine.messageHandler = { [weak self] text in self?.message = text }
            if let error = engine.loadCore(core, game: access.url.path, system: store.biosURL.path, save: saves.path) { throw StoreError.message(error) }
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
    func resume() { guard loaded else { return }; hasResume = false; paused = false; engine.start(); UIApplication.shared.isIdleTimerDisabled = true }
    func pause() { engine.pause(); paused = true; UIApplication.shared.isIdleTimerDisabled = false; if !engine.saveRAM() { message = "Could not save battery progress. Check your iPhone's free space." } }
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
    @State private var controlsVisible = true
    @State private var lastControlActivity = Date()
    private let idleClock = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var confirmReset = false
    @State private var confirmDiscard = false
    private var automaticButtons: Int {
        if game.system == .mega { return session.megaButtons }
        if game.system == .fbneo && !session.fbneoInputs.isEmpty { return min(6, max(2, session.fbneoInputs.count)) }
        return GameCatalogue.shared.arcadeButtonCount(for: game)
    }
    private var buttons: Int { store.profile.touchButtonOverride(for: game) ?? automaticButtons }
    private var layoutMenu: some View {
        let selected = store.profile.touchButtonOverride(for: game)
        return Menu {
            ForEach([0, 2, 3, 4, 5, 6], id: \.self) { count in
                let title = count == 0 ? "Automatic (\(automaticButtons) buttons)" : "\(count) buttons"
                Button {
                    input.clear()
                    session.engine.clearButtons()
                    store.updateProfile { $0.setTouchButtonOverride(count == 0 ? nil : count, for: game) }
                    showControls = true
                } label: {
                    if count == (selected ?? 0) { Label(title, systemImage: "checkmark") }
                    else { Text(title) }
                }
            }
        } label: {
            Label("Layout · \(buttons)", systemImage: "circle.grid.2x2.fill")
                .font(.subheadline.bold()).fixedSize().frame(minHeight: 38)
        }.accessibilityLabel("Button layout for this game").accessibilityValue("\(buttons) buttons")
            .accessibilityIdentifier("arcade-layout")
    }
    private var touchPad: some View {
        TouchControls(system: game.system, count: buttons, fbneoInputs: session.fbneoInputs, onInteraction: { revealControls() })
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()
                // Gameplay uses the whole screen. The HUD and on-screen
                // controls are overlays, so portrait has no controls strip.
                GameScreen(engine: session.engine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .accessibilityHidden(session.paused)

                if !session.paused {
                    if !controlsVisible {
                        // Screen taps wake the virtual pad while the pause and
                        // settings controls stay available at all times.
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { revealControls() }
                            .accessibilityLabel("Show on-screen controls")
                    }
                    if showControls && controlsVisible {
                        touchPad
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .accessibilityIdentifier("touch-controls-overlay")
                    }
                    VStack {
                        HStack(spacing: 14) {
                            Button { input.clear(); session.pause() } label: {
                                Image(systemName: "pause.circle.fill").font(.title)
                            }
                            .accessibilityLabel("Pause game")
                            Spacer()
                            if game.system.isArcade { layoutMenu }
                            Button { showControls.toggle(); input.clear(); revealControls() } label: {
                                Image(systemName: "gamecontroller").font(.title2)
                            }
                            .accessibilityLabel("Show or hide touch controls")
                            Button { input.clear(); session.pause() } label: {
                                Image(systemName: "gearshape.fill").font(.title2)
                            }
                            .accessibilityLabel("Game settings")
                            .accessibilityIdentifier("game-settings")
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.black.opacity(controlsVisible ? 0.25 : 0.12))
                        Spacer()
                    }
                }

                if session.paused {
                    pauseMenu.padding(12).frame(maxWidth: 450, maxHeight: 480)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .padding(8)
                }
            }
        }.statusBarHidden()
            .onAppear {
                showControls = input.names.isEmpty
                revealControls()
                session.open(game, store: store, input: input)
            }
            .onChange(of: session.paused) { _, paused in if !paused { revealControls() } }
            .onReceive(idleClock) { now in
                guard !session.paused, controlsVisible,
                      now.timeIntervalSince(lastControlActivity) >= 5,
                      input.pressed.isEmpty, input.pressedC.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.25)) { controlsVisible = false }
            }
            .onDisappear { if session.loaded { session.pause(); session.automaticSave() }; session.stop(input: input) }
            .onChange(of: phase) { value in
                if value == .inactive {
                    input.clear(); session.pause(); session.automaticSave(); session.engine.finishGraphics()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in input.clear(); session.pause() }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in input.clear(); session.pause(); showControls = true }
            .alert("Light Retro", isPresented: Binding(get: { session.message != nil }, set: { if !$0 { session.message = nil } })) { Button("OK") { session.message = nil } } message: { Text(session.message ?? "") }
            .confirmationDialog("Restart this game? Unsaved progress will be lost.", isPresented: $confirmReset, titleVisibility: .visible) { Button("Restart", role: .destructive) { session.engine.resetGame(); session.hasResume = false; session.resume() } }
            .confirmationDialog("Exit without saving a new state?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Exit", role: .destructive) { session.stop(input: input); dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your previous automatic state and in-game battery saves are kept.") }
    }
    private func revealControls() {
        lastControlActivity = Date()
        if !controlsVisible {
            withAnimation(.easeIn(duration: 0.2)) { controlsVisible = true }
        }
    }

    private var pauseMenu: some View {
        VStack(spacing: 8) {
            Text(game.displayTitle).font(.headline).lineLimit(1)
            if session.loaded {
                ScrollView {
                    VStack(spacing: 12) {
                        if session.hasResume { Button("Resume saved game") { session.restoreAutomatic() }.buttonStyle(.borderedProminent) }
                        Button(session.hasResume ? "Start fresh" : "Continue playing") { session.hasResume = false; input.clear(); session.resume() }.buttonStyle(.borderedProminent)
                        Picker("Save slot", selection: $session.slot) { ForEach(1...3, id: \.self) { Text("Slot \($0)").tag($0) } }.pickerStyle(.segmented)
                        HStack { Button("Save state") { session.saveSlot() }; Spacer(); Button("Load state") { session.loadSlot() } }.buttonStyle(.bordered)
                        Toggle("Touch controls", isOn: $showControls)
                        if game.system.isArcade { layoutMenu }
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
    let onInteraction: () -> Void
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        let face = TouchPad.face(system: system, count: count, fbneoInputs: fbneoInputs)
        GeometryReader { area in
            let width = area.size.width
            let height = area.size.height
            let pad = min(148, width * 0.32, max(88, height * 0.34))
            let columns = (face.map(\.column).max() ?? 0) + 1
            let rows = (face.map(\.row).max() ?? 0) + 1
            let step = min(store.profile.largeTouchButtons == true ? CGFloat(60) : CGFloat(50),
                           (width - pad - 26) / max(CGFloat(columns), 1),
                           min(215, height * 0.37) / max(CGFloat(rows), 1))
            TouchLayout(system: system, count: count, face: face, step: max(1, step),
                        padWidth: pad, response: store.profile.controlResponse ?? .standard,
                        onInteraction: onInteraction)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TouchLayout: View {
    let system: GameSystem
    let count: Int
    let face: [PadButton]
    let step: CGFloat
    let padWidth: CGFloat
    let response: ControlResponse
    let onInteraction: () -> Void
    @State private var dpadMode = false
    @EnvironmentObject private var input: ControllerHub

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top) {
                // Arcade Coin and Start stay on the upper-left edge, never in
                // the centre of the game. Console Select/Start stay here too.
                VStack(alignment: .leading, spacing: 6) {
                    if system != .n64 && (system != .mega || count == 6) {
                        key(system.isArcade ? "COIN" : (system == .mega ? "MODE" : "SELECT"),
                            2, width: 64)
                    }
                    key(system == .pce || system == .pcecd ? "RUN" : "START", 3, width: 64)
                }
                Spacer(minLength: 8)
                if system == .snes || system == .n64 {
                    HStack(spacing: 6) {
                        key("L", 10, width: 45)
                        if system == .n64 {
                            key("Z", 12, width: 45)
                            Button(dpadMode ? "D-PAD" : "STICK") {
                                onInteraction(); dpadMode.toggle(); input.clear()
                            }
                            .font(.caption2.bold()).buttonStyle(.bordered).tint(.white)
                        }
                        key("R", 11, width: 45)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 8) {
                movement
                    .frame(width: padWidth, height: padWidth)
                Spacer(minLength: 0)
                // Preserve the native cabinet / console cluster rather than
                // stacking A/B/C or arcade buttons into a single column.
                faceButtons
            }
        }
    }

    @ViewBuilder private var movement: some View {
        if system == .n64 && !dpadMode {
            TouchStick(response: response, onInteraction: onInteraction)
        } else {
            dpad
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
            switch button.label {
            case "X": return .blue
            case "Y": return .green
            case "A": return .red
            default: return .yellow
            }
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
            change = { down in if down { onInteraction() }; input.setTouch(id, down: down) }
        case .cDirection(let id):
            down = input.pressedC.contains(id)
            change = { down in if down { onInteraction() }; input.setTouchC(id, down: down) }
        }
        let tint = colour(button)
        return Text(button.label)
            .font(.system(size: min(19, step * 0.4), weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: max(1, step - 4), height: max(1, step - 4))
            .background {
                Circle().fill(.black.opacity(0.5))
                Circle().fill(tint.opacity(down ? 0.90 : 0.38))
                Circle().strokeBorder(tint.opacity(0.95), lineWidth: down ? 3 : 1.5)
            }
            .frame(width: step, height: step)
            .overlay { TouchButtonSurface(change: change) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(system.isArcade ? "Button " + button.label : button.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("pad-" + button.label)
            .onDisappear { change(false) }
    }

    private var dpad: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let centre = width / 2
            ZStack {
                Circle().fill(.black.opacity(0.42))
                Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) * .pi / 4 - .pi / 2
                    let radius = Double(width) * 0.34
                    Text(["↑","↗","→","↘","↓","↙","←","↖"][i])
                        .font(.system(size: width * 0.13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .position(x: centre + CGFloat(cos(angle) * radius),
                                  y: centre + CGFloat(sin(angle) * radius))
                }
                Circle().fill(.white.opacity(0.30)).frame(width: width * 0.27)
            }
            .frame(width: width, height: width)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { event in
                        onInteraction()
                        let x = Float(event.location.x * 2 / width - 1)
                        let y = Float(event.location.y * 2 / width - 1)
                        if max(abs(x), abs(y)) <= 1 {
                            input.setTouchDirections(response.touchDirections(x: x, y: y))
                        } else {
                            input.setTouchDirections([])
                        }
                    }
                    .onEnded { _ in input.setTouchDirections([]); onInteraction() }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eight-way directional joystick")
        .onDisappear { input.setTouchDirections([]) }
    }

    private func key(_ label: String, _ id: Int, width: CGFloat) -> some View {
        Text(label).font(.caption2.bold())
            .foregroundStyle(.white).frame(width: width, height: min(step, 36))
            .background(.black.opacity(0.52), in: Capsule())
            .background(input.pressed.contains(id) ? .orange : .gray.opacity(0.8), in: Capsule())
            .overlay { TouchButtonSurface { down in if down { onInteraction() }; input.setTouch(id, down: down) } }
            .accessibilityLabel(label).accessibilityAddTraits(.isButton)
            .onDisappear { input.setTouch(id, down: false) }
    }
}

private struct TouchButtonSurface: UIViewRepresentable {
    let change: (Bool) -> Void
    final class Surface: UIControl {
        var change: ((Bool) -> Void)?
        @objc func press() { change?(true) }
        @objc func releaseButton() { change?(false) }
    }
    func makeUIView(context: Context) -> Surface {
        let surface = Surface()
        surface.isAccessibilityElement = false
        surface.addTarget(surface, action: #selector(Surface.press), for: [.touchDown, .touchDragEnter])
        surface.addTarget(surface, action: #selector(Surface.releaseButton), for: [.touchDragExit, .touchUpInside, .touchUpOutside, .touchCancel])
        return surface
    }
    func updateUIView(_ surface: Surface, context: Context) { surface.change = change }
    static func dismantleUIView(_ surface: Surface, coordinator: ()) { surface.releaseButton(); surface.change = nil }
}

struct TouchStick: View {
    let response: ControlResponse
    var onInteraction: () -> Void = {}
    @EnvironmentObject private var input: ControllerHub
    @State private var offset = CGSize.zero
    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width,proxy.size.height) / 2
            ZStack {
                Circle().fill(.white.opacity(0.10))
                Circle().strokeBorder(.white.opacity(0.25),lineWidth: 1)
                Circle().fill(.white.opacity(0.35)).frame(width: 48,height: 48).offset(offset)
            }.contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    onInteraction()
                    let dx = value.location.x-radius, dy = value.location.y-radius
                    let distance = sqrt(dx*dx+dy*dy), travel = max(1,radius-24)
                    let scale = max(1,distance/travel)
                    offset = CGSize(width: dx/scale,height: dy/scale)
                    let (x, y) = response.stick(x: Float(offset.width/travel), y: Float(offset.height/travel))
                    input.setTouchStick(0, x: x, y: y)
                }.onEnded { _ in offset = .zero; input.setTouchStick(0, x: 0,y: 0) })
                .accessibilityLabel("N64 analogue stick")
                .onDisappear { offset = .zero; input.setTouchStick(0, x: 0,y: 0) }
        }
    }
}
