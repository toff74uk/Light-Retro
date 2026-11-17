import Foundation
import GameController
import Combine

struct GamepadState {
    var buttons: [Int: Bool] = [:]
    // libretro convention: X right is positive, Y down is positive.
    var sticks: [[Float]] = [[0,0],[0,0]]
}

@MainActor final class ControllerHub: ObservableObject {
    @Published var names: [String] = []
    @Published var pressed: Set<Int> = []
    var onMenuInput: ((Int) -> Void)?
    var onGameInput: (([GamepadState]) -> Void)?
    var analogueGameplay = false
    var onPause: (() -> Void)?
    private var timer: Timer?
    private var previous: Set<Int> = []
    private var touch: Set<Int> = []
    private var touchSticks: [Int: [Float]] = [:]
    private var touchC: Set<Int> = []
    private var repeatedAt = Date.distantPast
    private var pauseHeld = false
    init() {
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func setTouch(_ button: Int, down: Bool) { if down { touch.insert(button) } else { touch.remove(button) }; poll() }
    func setTouchStick(_ stick: Int, x: Float, y: Float) {
        guard (0..<2).contains(stick) else { return }
        touchSticks[stick] = [x,y]; poll()
    }
    func setTouchC(_ direction: Int, down: Bool) {
        if down { touchC.insert(direction) } else { touchC.remove(direction) }
        setTouchStick(1, x: Float((touchC.contains(7) ? 1 : 0) - (touchC.contains(6) ? 1 : 0)),
                      y: Float((touchC.contains(5) ? 1 : 0) - (touchC.contains(4) ? 1 : 0)))
    }
    func clear() { touch.removeAll(); touchSticks.removeAll(); touchC.removeAll(); previous.removeAll(); pressed.removeAll() }
    private func poll() {
        let controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        let updated = controllers.map { $0.vendorName ?? "Controller" }
        if names != updated { names = updated }
        var ports = Array(repeating: GamepadState(), count: 4)
        for (index, controller) in controllers.prefix(4).enumerated() {
            guard let g = controller.extendedGamepad else { continue }
            let map: [(Int, Bool)] = [
                (0,g.buttonA.isPressed),(1,g.buttonX.isPressed),(8,g.buttonB.isPressed),(9,g.buttonY.isPressed),
                (10,g.leftShoulder.isPressed),(11,g.rightShoulder.isPressed),(12,g.leftTrigger.isPressed),(13,g.rightTrigger.isPressed),
                (3,g.buttonMenu.isPressed),(2,g.buttonOptions?.isPressed ?? false),
                (14,g.leftThumbstickButton?.isPressed ?? false),(15,g.rightThumbstickButton?.isPressed ?? false),
                (4,g.dpad.up.isPressed || !analogueGameplay && g.leftThumbstick.yAxis.value > 0.5),
                (5,g.dpad.down.isPressed || !analogueGameplay && g.leftThumbstick.yAxis.value < -0.5),
                (6,g.dpad.left.isPressed || !analogueGameplay && g.leftThumbstick.xAxis.value < -0.5),
                (7,g.dpad.right.isPressed || !analogueGameplay && g.leftThumbstick.xAxis.value > 0.5)
            ]
            ports[index].buttons = Dictionary(uniqueKeysWithValues: map)
            for (stick, value) in [g.leftThumbstick, g.rightThumbstick].enumerated() {
                let x = value.xAxis.value, y = -value.yAxis.value
                ports[index].sticks[stick] = x*x+y*y < 0.015 ? [0,0] : [x,y]
            }
        }
        for button in touch { ports[0].buttons[button] = true }
        for (stick, value) in touchSticks {
            if value.contains(where: { $0 != 0 }) { ports[0].sticks[stick] = value }
        }
        let now = Set(ports[0].buttons.filter { $0.value }.map(\.key))
        if pressed != now { pressed = now }
        let combo = now.isSuperset(of: [10, 11, 3])
        if combo && !pauseHeld { clear(); onPause?() }
        pauseHeld = combo
        if !combo {
            onGameInput?(ports)
            let rising = now.subtracting(previous)
            for button in rising { onMenuInput?(button) }
            if rising.isEmpty, Date().timeIntervalSince(repeatedAt) > 0.22,
               let direction = now.intersection([4,5,6,7]).sorted().first { onMenuInput?(direction); repeatedAt = Date() }
            if !rising.isEmpty { repeatedAt = Date().addingTimeInterval(0.15) }
        }
        previous = now
    }
}
