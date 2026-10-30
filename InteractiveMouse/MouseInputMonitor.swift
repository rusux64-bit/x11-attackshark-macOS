// MouseInputMonitor.swift
// Listen-only mouse input source. No UI, no WebKit. Never posts, modifies, or swallows events.

import AppKit

enum MouseControl: Int, CaseIterable {
    // Raw values match NSEvent.buttonNumber / the bit index in NSEvent.pressedMouseButtons.
    case left = 0, right = 1, middle = 2, back = 3, forward = 4

    /// Name used by the SVG's `data-btn` attributes.
    var svgName: String {
        switch self {
        case .left: "left"
        case .right: "right"
        case .middle: "middle"
        case .back: "back"
        case .forward: "forward"
        }
    }
}

enum ScrollDirection: Int { case up = -1, down = 1 }

final class MouseInputMonitor {
    /// Called on the main thread whenever the set of held buttons changes.
    var onPressedChange: ((Set<MouseControl>) -> Void)?
    /// Called on the main thread for every physical wheel notch/step.
    var onScrollStep: ((ScrollDirection) -> Void)?
    /// Decides (from the screen-space mouse location) whether a press/scroll should be visualized.
    /// Default: accept everything (global). The dashboard narrows it to the test panel.
    var acceptsLocation: (NSPoint) -> Bool = { _ in true }

    private(set) var isRunning = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var healTimer: Timer?
    private var missedTicks: [MouseControl: Int] = [:]

    private var pressed: Set<MouseControl> = [] {
        didSet {
            guard pressed != oldValue else { return }
            onPressedChange?(pressed)
            updateHealTimer()
        }
    }

    private static let mask: NSEvent.EventTypeMask = [
        .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp,
        .scrollWheel,
    ]

    deinit { stop() }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Events delivered to OTHER apps (the "physical mouse, anywhere" case).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.mask) { [weak self] event in
            self?.handle(event)
        }
        // Global monitors never see events sent to this app, so cover our own windows too.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.mask) { [weak self] event in
            self?.handle(event)
            return event // pass through untouched
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        healTimer?.invalidate()
        healTimer = nil
        missedTicks.removeAll()
        pressed = [] // never leave a highlight stuck on teardown
    }

    // MARK: - Event handling

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // Presses outside the test zone (toolbar, theme button, other windows/apps) are ignored.
            guard acceptsLocation(NSEvent.mouseLocation) else { return }
            if let control = MouseControl(rawValue: event.buttonNumber) { pressed.insert(control) }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            // Releases are always honored so a highlight can never get stuck.
            if let control = MouseControl(rawValue: event.buttonNumber) { pressed.remove(control) }
        case .scrollWheel:
            guard acceptsLocation(NSEvent.mouseLocation) else { return }
            handleScroll(event)
        default:
            break
        }
    }

    private func handleScroll(_ event: NSEvent) {
        // Trackpads and Magic Mouse report gesture phases; a classic wheel does not.
        guard event.phase.isEmpty, event.momentumPhase.isEmpty else { return }
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return } // ignore horizontal/tilt
        // Undo "natural scrolling" so we report which way the wheel was physically rolled.
        let wheelRolledUp = (dy > 0) != event.isDirectionInvertedFromDevice
        onScrollStep?(wheelRolledUp ? .up : .down)
    }

    // MARK: - Stuck-highlight protection

    // Events drive the UI (lowest latency). While something is held, we also compare against the
    // system's live button state (needs no permission) and drop a control only after ~100 ms of
    // disagreement, so a missed release self-heals without flicker on fast clicks.

    private func updateHealTimer() {
        if pressed.isEmpty {
            healTimer?.invalidate()
            healTimer = nil
            missedTicks.removeAll()
            return
        }
        guard healTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.reconcile()
        }
        RunLoop.main.add(timer, forMode: .common)
        healTimer = timer
    }

    private func reconcile() {
        let live = NSEvent.pressedMouseButtons
        for control in pressed {
            if live & (1 << control.rawValue) != 0 {
                missedTicks[control] = nil
            } else {
                let misses = (missedTicks[control] ?? 0) + 1
                if misses >= 3 {
                    missedTicks[control] = nil
                    pressed.remove(control)
                } else {
                    missedTicks[control] = misses
                }
            }
        }
    }
}
