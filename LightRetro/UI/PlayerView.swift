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
    @State private var confirmReset = false
    @State private var confirmDiscard = false
    var body: some View {
        GeometryReader { geometry in
            let portrait = geometry.size.height > geometry.size.width
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Button { input.clear(); session.pause() } label: { Image(systemName: "pause.circle.fill").font(.title) }.accessibilityLabel("Pause game")
                        Spacer()
                        Text(game.displayTitle).font(.caption).lineLimit(1)
                        Spacer()
                        Button { showControls.toggle(); input.clear() } label: { Image(systemName: "gamecontroller").font(.title2) }.accessibilityLabel("Show or hide touch controls")
                    }.foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 6)
                    ZStack {
                        GameScreen(engine: session.engine)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if showControls && !portrait && !session.paused { TouchControls(system: game.system).environmentObject(input).padding(.horizontal, 14).padding(.bottom, 12) }
                    }
                    if showControls && portrait && !session.paused { TouchControls(system: game.system).environmentObject(input).frame(height: 220).padding(.horizontal, 20) }
                }.allowsHitTesting(!session.paused).accessibilityHidden(session.paused)
                if session.paused {
                    pauseMenu.padding(12).frame(maxWidth: 450, maxHeight: 480)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)).padding(8)
                }
            }
        }.statusBarHidden()
            .onAppear { showControls = input.names.isEmpty; session.open(game, store: store, input: input) }
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

struct TouchControls: View {
    let system: GameSystem
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        GeometryReader { area in
            let padWidth = min(138, area.size.width * 0.36)
            let requested: CGFloat = store.profile.largeTouchButtons == true ? 54 : 44
            let widthLimit = (area.size.width - padWidth - 72) / (system == .n64 ? 3 : 2.4)
            let heightLimit = (min(area.size.height, 220) - 15) / 4
            TouchLayout(system: system, padWidth: padWidth, size: max(1, min(requested, widthLimit, heightLimit)),
                        response: store.profile.controlResponse ?? .standard)
        }
    }
}

private struct TouchLayout: View {
    let system: GameSystem
    let padWidth: CGFloat
    let size: CGFloat
    let response: ControlResponse
    @State private var dpadMode = false
    @EnvironmentObject private var input: ControllerHub
    var body: some View {
        VStack {
            HStack {
                key("L", 10)
                if system == .n64 { key("Z", 12) }
                Spacer()
                if system == .n64 { Button(dpadMode ? "D-PAD" : "STICK") { dpadMode.toggle(); input.clear() }.font(.caption2.bold()).buttonStyle(.bordered).tint(.white) }
                key("R", 11)
            }
            Spacer(minLength: 4)
            HStack(alignment: .center, spacing: 0) {
                if system == .n64 && !dpadMode { TouchStick(response: response).frame(width: padWidth, height: padWidth) }
                else { dpad }
                Spacer(minLength: 2)
                VStack(spacing: 8) {
                    if system != .n64 { key(system == .arcade || system == .fbneo ? "COIN" : "SELECT",2,small:true) }
                    key("START",3,small:true)
                }
                Spacer(minLength: 2)
                if system == .n64 {
                    VStack(spacing: 4) {
                        HStack(spacing: 3) { cKey("C←",6); VStack(spacing: 3) { cKey("C↑",4); cKey("C↓",5) }; cKey("C→",7) }
                        HStack(spacing: 10) { key("B",1); key("A",0) }
                    }
                } else {
                    VStack(spacing: 3) {
                        key("X",9)
                        HStack(spacing: 3) { key("Y",1); Color.clear.frame(width: 10,height: 42); key("A",8) }
                        key("B",0)
                    }
                }
            }
        }.frame(maxHeight: 220).frame(maxHeight: .infinity, alignment: .bottom)
    }
    private var dpad: some View {
        let tile = (padWidth - 6) / 3
        return ZStack {
            ForEach(4...7, id: \.self) { id in
                Text(["↑", "↓", "←", "→"][id - 4]).font(.headline).foregroundStyle(.white)
                    .frame(width: tile, height: tile)
                    .background(input.pressed.contains(id) ? .orange.opacity(0.8) : .white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    .offset(x: id == 6 ? -tile-3 : (id == 7 ? tile+3 : 0), y: id == 4 ? -tile-3 : (id == 5 ? tile+3 : 0))
            }
        }.frame(width: padWidth, height: padWidth).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                let x = Float(event.location.x * 2 / padWidth - 1)
                let y = Float(event.location.y * 2 / padWidth - 1)
                if max(abs(x), abs(y)) <= 1 { input.setTouchDirections(response.touchDirections(x: x, y: y)) }
                else { input.setTouchDirections([]) }
            }.onEnded { _ in input.setTouchDirections([]) })
            .accessibilityElement(children: .ignore).accessibilityLabel("Directional pad")
            .onDisappear { input.setTouchDirections([]) }
    }
    private func cKey(_ label: String, _ id: Int) -> some View {
        Text(label).font(.caption.bold()).foregroundStyle(.yellow).frame(width: size, height: size)
            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .overlay { TouchButtonSurface { input.setTouchC(id, down: $0) } }
            .accessibilityLabel(label).accessibilityAddTraits(.isButton)
            .onDisappear { input.setTouchC(id, down: false) }
    }
    private func key(_ label: String, _ id: Int, small: Bool = false) -> some View {
        Text(label).font(small ? .system(size: 10, weight: .bold) : .headline)
            .foregroundStyle(.white).frame(width: small ? 58 : size, height: size)
            .background(input.pressed.contains(id) ? .orange.opacity(0.8) : .white.opacity(0.18), in: RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
            .overlay { TouchButtonSurface { input.setTouch(id, down: $0) } }
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
