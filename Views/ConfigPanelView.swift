// ConfigPanelView.swift
// Configuration menu shown to the right of the live mouse test.
// UI only for now: everything is bound to `ConfigState`, which the HID backend can read/write later.

import SwiftUI
import AppKit
import Combine
import Foundation

// MARK: - DPI rules (same limits as Protocol/DPICodec.swift)

enum DPIRules {
    static let minDPI = 50
    static let maxDPI = 22_000
    /// Slider domain = the mouse's own "steps": 1...200 -> 50...10000 DPI (x50), 201...320 -> 10100...22000 DPI (x100).
    static let stepRange: ClosedRange<Double> = 1...320

    /// Snaps any number to a DPI value the mouse accepts.
    static func snap(_ value: Int) -> Int {
        let clamped = min(max(value, minDPI), maxDPI)
        if clamped <= 10_000 { return max(minDPI, ((clamped + 25) / 50) * 50) }
        return min(maxDPI, ((clamped + 50) / 100) * 100)
    }

    static func step(for dpi: Int) -> Double {
        let value = snap(dpi)
        return Double(value <= 10_000 ? value / 50 : value / 100 + 100)
    }

    static func dpi(forStep step: Double) -> Int {
        let s = Int(step.rounded())
        return s <= 200 ? 50 * max(s, 1) : 100 * (min(s, 320) - 100)
    }
}

// MARK: - Stage colour (HSB, convertible to the RGB bytes the mouse stores)

struct StageColor: Equatable, Hashable {
    var h: Double   // 0...1
    var s: Double   // 0...1
    var b: Double   // 0...1

    init(h: Double, s: Double, b: Double) {
        self.h = h
        self.s = s
        self.b = b
    }

    init(red: UInt8, green: UInt8, blue: UInt8) {
        let r = Double(red) / 255, g = Double(green) / 255, bl = Double(blue) / 255
        let mx = max(r, g, bl), mn = min(r, g, bl), d = mx - mn
        var hue = 0.0
        if d > 0 {
            if mx == r { hue = ((g - bl) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { hue = (bl - r) / d + 2 }
            else { hue = (r - g) / d + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        self.init(h: hue, s: mx == 0 ? 0 : d / mx, b: mx)
    }

    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: UInt8((value >> 16) & 0xFF), green: UInt8((value >> 8) & 0xFF), blue: UInt8(value & 0xFF))
    }

    var color: Color { Color(hue: h, saturation: s, brightness: b) }

    var rgb: (red: UInt8, green: UInt8, blue: UInt8) {
        let c = b * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = b - c
        let parts: (Double, Double, Double) = switch Int(hp) % 6 {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        func byte(_ v: Double) -> UInt8 { UInt8(min(max(((v + m) * 255).rounded(), 0), 255)) }
        return (byte(parts.0), byte(parts.1), byte(parts.2))
    }

    var hex: String {
        let v = rgb
        return String(format: "#%02X%02X%02X", Int(v.red), Int(v.green), Int(v.blue))
    }

    /// Slider/accent colour that stays visible on both light and dark panels.
    var tint: Color {
        ((s < 0.15 && b > 0.85) || b < 0.2) ? .accentColor : color
    }

    static func hex(_ value: String) -> StageColor { StageColor(hex: value) ?? StageColor(h: 0, s: 0, b: 1) }
}

// MARK: - Model (UI state only)

/// Snapshot of the DPI setup, used to tell "the user changed something" from "nothing to send".
fileprivate struct DPISignature: Equatable {
    struct Stage: Equatable {
        var enabled: Bool
        var dpi: Int
        var hex: String
    }
    var stages: [Stage]
    var active: Int
}

struct DPIStageState: Identifiable, Equatable {
    let id: Int
    var isEnabled: Bool
    var dpi: Int
    var color: StageColor
}

enum ConfigTab: Int, CaseIterable, Identifiable {
    case dpi, performance, buttons, lighting, power

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dpi: "DPI"
        case .performance: "Performance"
        case .buttons: "Buttons"
        case .lighting: "Lighting"
        case .power: "Power"
        }
    }
}

enum ButtonAction: String, CaseIterable, Identifiable {
    case leftClick = "Left click"
    case rightClick = "Right click"
    case middleClick = "Middle click"
    case forward = "Forward"
    case back = "Back"
    case dpiCycle = "DPI cycle"
    case disabled = "Disabled"
    /// A code the app doesn't know: shown as it is and never overwritten unless the user picks something else.
    case other = "Other (custom)"

    var id: String { rawValue }

    /// What the user can pick (`other` only appears when the mouse already holds an unknown code).
    static var selectable: [ButtonAction] { allCases.filter { $0 != .other } }

    /// Code stored in report 0x08. Back (0x05) and Forward (0x06) are confirmed on a real X11; the rest follows
    /// the factory layout of the report (left 0x02, right 0x03, middle 0x04, DPI 0x0D, unassigned 0x01).
    var code: UInt8? {
        switch self {
        case .leftClick: 0x02
        case .rightClick: 0x03
        case .middleClick: 0x04
        case .back: 0x05
        case .forward: 0x06
        case .dpiCycle: 0x0D
        case .disabled: 0x01
        case .other: nil
        }
    }

    init(code: UInt8) {
        self = Self.selectable.first { $0.code == code } ?? .other
    }
}

enum ButtonMap {
    /// Report 0x08 entry (0-based) of: left, right, middle, forward, back.
    static let entries = [0, 1, 2, 6, 7]
    static let factoryActions: [ButtonAction] = [.leftClick, .rightClick, .middleClick, .forward, .back]
}

enum LightMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case steady = "Steady"
    case breathing = "Breathing"
    case rainbow = "Rainbow"
    case colorBreathing = "Colour breathing"
    case dpiSteady = "DPI steady"
    case dpiBreathing = "DPI breathing"

    var id: String { rawValue }

    /// The mode code the mouse understands ("Rainbow" is the firmware's "neon" cycle).
    var hardware: LightingMode {
        switch self {
        case .off: .off
        case .steady: .steady
        case .breathing: .breathing
        case .rainbow: .neon
        case .colorBreathing: .colorBreathing
        case .dpiSteady: .dpiSteady
        case .dpiBreathing: .dpiBreathing
        }
    }

    init(_ mode: LightingMode) {
        switch mode {
        case .off: self = .off
        case .steady: self = .steady
        case .breathing: self = .breathing
        case .neon: self = .rainbow
        case .colorBreathing: self = .colorBreathing
        case .dpiSteady: self = .dpiSteady
        case .dpiBreathing: self = .dpiBreathing
        }
    }

    /// Modes that show the colour picked in the app.
    var usesColor: Bool { self == .steady || self == .breathing }
    /// Modes that animate, so the speed matters.
    var usesSpeed: Bool { self == .breathing || self == .rainbow || self == .colorBreathing || self == .dpiBreathing }
    /// Modes where the LED takes the colour of the active DPI stage.
    var followsDPIStage: Bool { self == .dpiSteady || self == .dpiBreathing }
}

/// LED colour as the three bytes the mouse stores, with helpers to go to and from SwiftUI's `Color`.
enum LEDColor {
    struct RGB: Hashable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8

        init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        var color: Color {
            Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
        }
    }

    static let presets: [RGB] = [
        RGB(255, 0, 0), RGB(255, 128, 0), RGB(255, 255, 0), RGB(0, 255, 0), RGB(0, 255, 255),
        RGB(0, 0, 255), RGB(160, 0, 255), RGB(255, 0, 128), RGB(255, 255, 255)
    ]

    static func rgb(of color: Color) -> RGB {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        func byte(_ value: CGFloat) -> UInt8 { UInt8(min(max((value * 255).rounded(), 0), 255)) }
        return RGB(byte(converted.redComponent), byte(converted.greenComponent), byte(converted.blueComponent))
    }
}

final class ConfigState: ObservableObject {
    // DPI
    @Published var dpiStages: [DPIStageState] = {
        let dpis = [800, 1600, 2400, 3200, 5000, 22000, 800, 800]
        let colors = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#00FFFF", "#FF00FF", "#FF8000", "#FFFFFF"]
        return (0..<8).map {
            DPIStageState(id: $0, isEnabled: $0 < 6, dpi: dpis[$0], color: StageColor.hex(colors[$0]))
        }
    }()
    @Published var activeStage = 1
    @Published var recentColors: [StageColor] = []

    // Performance (polling rate, debounce, angle snapping and ripple control are read from / written to the mouse)
    @Published var pollingRate = 1000
    @Published var rippleControl = false
    @Published var angleSnapping = false
    @Published var debounceMs: Double = 4

    // Buttons (left, right, middle, forward, back)
    @Published var buttonActions: [ButtonAction] = [.leftClick, .rightClick, .middleClick, .forward, .back]

    // Lighting (mode, brightness, speed, colour) and Power (sleep timer) are read from / written to the mouse (report 0x05)
    @Published var lightMode: LightMode = .steady
    /// 1...8, the mouse's own brightness levels.
    @Published var brightnessLevel: Double = 8
    /// 1...5, 5 is the fastest animation.
    @Published var lightSpeedLevel: Double = 3
    @Published var lightColor: Color = LEDColor.RGB(0, 255, 0).color

    // Power
    @Published var sleepAfterSeconds = 60
    // The low battery alert is a feature of this app (the mouse has no such setting), so it is stored on the Mac.
    @Published var lowBatteryAlert: Bool = (UserDefaults.standard.object(forKey: "lowBatteryAlertEnabled") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(lowBatteryAlert, forKey: "lowBatteryAlertEnabled")
            if lowBatteryAlert { requestNotificationAccess() }
        }
    }
    @Published var alertThreshold: Double = (UserDefaults.standard.object(forKey: "lowBatteryAlertThreshold") as? Double) ?? 20 {
        didSet { UserDefaults.standard.set(alertThreshold, forKey: "lowBatteryAlertThreshold") }
    }
    /// True when macOS notifications are switched off for the app, so the alert could never be seen.
    @Published var notificationsBlocked = false
    /// Result of the last "Send test alert" press (shown under the button).
    @Published var testAlertMessage: String?

    // MARK: Mouse sync (DPI only)

    private weak var device: DeviceViewModel?
    /// What the mouse is known to hold (nil until the first successful read).
    private var deviceSignature: DPISignature?
    private var hasPendingLocalEdits = false
    private var isApplyingMouse = false
    private var isWriting = false
    /// True while the ↻ button is reading the mouse; edits made in the meantime are discarded, not sent.
    private var isSyncingFromMouse = false

    // Performance sync (same scheme as DPI)
    private var performanceKnown: PerformanceSettings?
    private var hasPendingPerformanceEdits = false
    private var isApplyingPerformance = false
    private var isWritingPerformance = false
    private var isSyncingPerformance = false

    // Buttons sync (same scheme as DPI / Performance)
    private var buttonsKnown: [UInt8]?          // the 18 codes the mouse is known to hold
    private var hasPendingButtonEdits = false
    private var isApplyingButtons = false
    private var isWritingButtons = false
    private var isSyncingButtons = false

    // Lighting & power sync (same scheme again)
    private var lightingKnown: LightingSettings?
    private var hasPendingLightingEdits = false
    private var isApplyingLighting = false
    private var isWritingLighting = false
    private var isSyncingLighting = false
    /// How many times a failed lighting/sleep write was retried automatically (a sleeping mouse often misses the first try).
    private var lightingRetries = 0
    /// True once the low-battery notification went out; re-armed when the battery recovers or is charging.
    private var batteryAlertSent = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        let changes = Publishers.CombineLatest($dpiStages, $activeStage).dropFirst()
        // Immediately: remember that the user changed something (so a mouse update can't overwrite it).
        changes
            .sink { [weak self] stages, active in self?.noteLocalChange(stages: stages, active: active) }
            .store(in: &cancellables)
        // After the user stops dragging: send it to the mouse.
        changes
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushDPIIfNeeded() }
            .store(in: &cancellables)

        let performanceChanges = Publishers.CombineLatest4($pollingRate, $debounceMs, $angleSnapping, $rippleControl).dropFirst()
        performanceChanges
            .sink { [weak self] rate, debounce, angle, ripple in
                self?.notePerformanceChange(Self.performance(rate: rate, debounce: debounce, angle: angle, ripple: ripple))
            }
            .store(in: &cancellables)
        performanceChanges
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushPerformanceIfNeeded() }
            .store(in: &cancellables)

        let buttonChanges = $buttonActions.dropFirst()
        buttonChanges
            .sink { [weak self] actions in self?.noteButtonEdit(actions) }
            .store(in: &cancellables)
        buttonChanges
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushButtonsIfNeeded() }
            .store(in: &cancellables)

        let lightingChanges = Publishers.CombineLatest(
            Publishers.CombineLatest3($lightMode, $brightnessLevel, $lightSpeedLevel),
            Publishers.CombineLatest($lightColor, $sleepAfterSeconds)
        ).dropFirst()
        lightingChanges
            .sink { [weak self] left, right in
                self?.noteLightingChange(Self.makeLighting(mode: left.0, brightness: left.1, speed: left.2, color: right.0, sleep: right.1))
            }
            .store(in: &cancellables)
        lightingChanges
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushLightingIfNeeded() }
            .store(in: &cancellables)
    }

    /// Connects the DPI state to the mouse: mouse -> UI updates, UI edits -> mouse writes.
    func attach(_ device: DeviceViewModel) {
        guard self.device !== device else { return }
        self.device = device
        device.$mouseDPIConfiguration
            .compactMap { $0 }
            .sink { [weak self] configuration in self?.applyMouse(configuration) }
            .store(in: &cancellables)
        device.$mousePerformance
            .compactMap { $0 }
            .sink { [weak self] settings in self?.applyMousePerformance(settings) }
            .store(in: &cancellables)
        device.$buttonsReport
            .compactMap { $0 }
            .sink { [weak self] report in self?.applyMouseButtons(report) }
            .store(in: &cancellables)
        device.$mouseLighting
            .compactMap { $0 }
            .sink { [weak self] settings in self?.applyMouseLighting(settings) }
            .store(in: &cancellables)

        // Low battery alert: watches the battery heartbeat and the alert settings.
        Publishers.CombineLatest4(
            device.$batteryLevel,
            device.$hasBatteryReading,
            device.$isCharging,
            Publishers.CombineLatest($lowBatteryAlert, $alertThreshold)
        )
        .sink { [weak self] level, hasReading, charging, alert in
            self?.evaluateBattery(level: level, hasReading: hasReading, charging: charging, enabled: alert.0, threshold: alert.1)
        }
        .store(in: &cancellables)

        if lowBatteryAlert { requestNotificationAccess() }
    }

    /// ↻ button: drops unsent edits and loads whatever the mouse holds right now.
    func syncFromMouse() {
        guard let device, !isWriting, !isSyncingFromMouse else { return }
        hasPendingLocalEdits = false
        isSyncingFromMouse = true
        device.refreshDPI(userInitiated: true) { [weak self] configuration in
            guard let self else { return }
            self.isSyncingFromMouse = false
            if let configuration { self.applyMouse(configuration) }
        }
    }

    private func noteLocalChange(stages: [DPIStageState], active: Int) {
        guard !isApplyingMouse, let known = deviceSignature else { return }
        if Self.signature(stages: stages, active: active) != known { hasPendingLocalEdits = true }
    }

    private func pushDPIIfNeeded() {
        guard !isApplyingMouse, !isWriting, !isSyncingFromMouse else { return }
        guard let device, let known = deviceSignature else {
            hasPendingLocalEdits = false
            return
        }
        let sent = Self.signature(stages: dpiStages, active: activeStage)
        guard sent != known else {
            hasPendingLocalEdits = false
            return
        }

        let edits = dpiStages.map {
            DPIStageEdit(dpi: $0.dpi, isEnabled: $0.isEnabled, color: Self.dpiColor($0.color))
        }
        isWriting = true
        device.writeDPI(stages: edits, activeIndex: activeStage) { [weak self] confirmed in
            self?.finishWrite(sent: sent, confirmed: confirmed)
        }
    }

    private func finishWrite(sent: DPISignature, confirmed: DPIConfiguration?) {
        isWriting = false
        hasPendingLocalEdits = false
        if let confirmed { deviceSignature = Self.signature(of: confirmed) }

        let now = Self.signature(stages: dpiStages, active: activeStage)
        if now != sent {
            // The user kept editing while the write was in flight: send the newer state too.
            hasPendingLocalEdits = true
            pushDPIIfNeeded()
        } else if let confirmed, Self.signature(of: confirmed) != sent {
            // The mouse disagrees with what we sent: show what it really holds.
            applyMouse(confirmed)
        }
    }

    /// Loads the mouse's DPI setup into the UI (skipped while the user has unsent edits).
    private func applyMouse(_ configuration: DPIConfiguration) {
        guard !hasPendingLocalEdits, !isWriting else { return }
        deviceSignature = Self.signature(of: configuration)
        isApplyingMouse = true
        defer { isApplyingMouse = false }

        var stages = dpiStages
        for (index, incoming) in configuration.stages.enumerated() where stages.indices.contains(index) {
            stages[index].isEnabled = incoming.isEnabled
            stages[index].dpi = DPIRules.snap(incoming.dpi)
            // Only replace the colour when the bytes really differ, so the colour wheel doesn't jump.
            if stages[index].color.hex != Self.hex(of: incoming.color) {
                stages[index].color = StageColor(red: incoming.color.red, green: incoming.color.green, blue: incoming.color.blue)
            }
        }
        let active = min(max(configuration.activeStage - 1, 0), stages.count - 1)

        withAnimation(.easeInOut(duration: 0.2)) {
            if stages != dpiStages { dpiStages = stages }
            if activeStage != active { activeStage = active }
        }
    }

    private static func hex(of color: DPIColor) -> String {
        String(format: "#%02X%02X%02X", Int(color.red), Int(color.green), Int(color.blue))
    }

    private static func dpiColor(_ color: StageColor) -> DPIColor {
        let value = color.rgb
        return DPIColor(red: value.red, green: value.green, blue: value.blue)
    }

    /// Disabled stages only count by their on/off flag (the firmware may store their DPI/colour differently).
    private static func signature(stages: [DPIStageState], active: Int) -> DPISignature {
        DPISignature(
            stages: stages.map {
                $0.isEnabled
                    ? DPISignature.Stage(enabled: true, dpi: $0.dpi, hex: $0.color.hex)
                    : DPISignature.Stage(enabled: false, dpi: 0, hex: "")
            },
            active: active
        )
    }

    private static func signature(of configuration: DPIConfiguration) -> DPISignature {
        DPISignature(
            stages: configuration.stages.map {
                $0.isEnabled
                    ? DPISignature.Stage(enabled: true, dpi: DPIRules.snap($0.dpi), hex: hex(of: $0.color))
                    : DPISignature.Stage(enabled: false, dpi: 0, hex: "")
            },
            active: configuration.activeStage - 1
        )
    }

    // MARK: Performance sync

    private static func performance(rate: Int, debounce: Double, angle: Bool, ripple: Bool) -> PerformanceSettings {
        PerformanceSettings(pollingRate: rate, debounceMs: Int(debounce.rounded()), angleSnapping: angle, rippleControl: ripple)
    }

    private var currentPerformance: PerformanceSettings {
        Self.performance(rate: pollingRate, debounce: debounceMs, angle: angleSnapping, ripple: rippleControl)
    }

    /// ↻ button on the Performance page: drops unsent edits and loads what the mouse holds right now.
    func syncPerformanceFromMouse() {
        guard let device, !isWritingPerformance, !isSyncingPerformance else { return }
        hasPendingPerformanceEdits = false
        isSyncingPerformance = true
        device.refreshPerformance(userInitiated: true) { [weak self] settings in
            guard let self else { return }
            self.isSyncingPerformance = false
            if let settings { self.applyMousePerformance(settings) }
        }
    }

    private func notePerformanceChange(_ settings: PerformanceSettings) {
        guard !isApplyingPerformance, let known = performanceKnown else { return }
        if settings != known { hasPendingPerformanceEdits = true }
    }

    private func pushPerformanceIfNeeded() {
        guard !isApplyingPerformance, !isWritingPerformance, !isSyncingPerformance else { return }
        guard let device, let known = performanceKnown else {
            hasPendingPerformanceEdits = false
            return
        }
        let wanted = currentPerformance
        guard wanted != known else {
            hasPendingPerformanceEdits = false
            return
        }

        isWritingPerformance = true
        device.writePerformance(wanted) { [weak self] confirmed in
            self?.finishPerformanceWrite(sent: wanted, confirmed: confirmed)
        }
    }

    private func finishPerformanceWrite(sent: PerformanceSettings, confirmed: PerformanceSettings?) {
        isWritingPerformance = false
        hasPendingPerformanceEdits = false
        if let confirmed { performanceKnown = confirmed }

        if currentPerformance != sent {
            // The user kept editing while the write was in flight: send the newer state too.
            hasPendingPerformanceEdits = true
            pushPerformanceIfNeeded()
        } else if let confirmed, confirmed != sent {
            // The mouse disagrees with what we sent: show what it really holds.
            applyMousePerformance(confirmed)
        }
    }

    /// Loads the mouse's Performance settings into the UI (skipped while the user has unsent edits).
    private func applyMousePerformance(_ settings: PerformanceSettings) {
        guard !hasPendingPerformanceEdits, !isWritingPerformance else { return }
        performanceKnown = settings
        isApplyingPerformance = true
        defer { isApplyingPerformance = false }

        if pollingRate != settings.pollingRate { pollingRate = settings.pollingRate }
        let debounce = Double(min(max(settings.debounceMs, 2), 25))
        if debounceMs != debounce { debounceMs = debounce }
        if angleSnapping != settings.angleSnapping { angleSnapping = settings.angleSnapping }
        if rippleControl != settings.rippleControl { rippleControl = settings.rippleControl }
    }

    // MARK: Buttons sync

    /// Entry index -> new code, for every button whose action differs from what the mouse holds.
    private static func pendingChanges(_ actions: [ButtonAction], known: [UInt8]) -> [Int: UInt8] {
        var changes: [Int: UInt8] = [:]
        for (slot, entry) in ButtonMap.entries.enumerated() where actions.indices.contains(slot) && known.indices.contains(entry) {
            guard let code = actions[slot].code, known[entry] != code else { continue }
            changes[entry] = code
        }
        return changes
    }

    /// Back to the factory layout (sent to the mouse like any other edit).
    func resetButtonsToFactory() {
        buttonActions = ButtonMap.factoryActions
    }

    /// ↻ button on the Buttons page: drops unsent edits and loads what the mouse holds right now.
    func syncButtonsFromMouse() {
        guard let device, !isWritingButtons, !isSyncingButtons else { return }
        hasPendingButtonEdits = false
        isSyncingButtons = true
        device.refreshButtons(userInitiated: true) { [weak self] report in
            guard let self else { return }
            self.isSyncingButtons = false
            if let report { self.applyMouseButtons(report) }
        }
    }

    private func noteButtonEdit(_ actions: [ButtonAction]) {
        guard !isApplyingButtons, let known = buttonsKnown else { return }
        if !Self.pendingChanges(actions, known: known).isEmpty { hasPendingButtonEdits = true }
    }

    private func pushButtonsIfNeeded() {
        guard !isApplyingButtons, !isWritingButtons, !isSyncingButtons else { return }
        guard let device, let known = buttonsKnown else {
            hasPendingButtonEdits = false
            return
        }
        let changes = Self.pendingChanges(buttonActions, known: known)
        guard !changes.isEmpty else {
            hasPendingButtonEdits = false
            return
        }

        let sent = buttonActions
        isWritingButtons = true
        device.writeButtons(changes) { [weak self] confirmed, wasSent in
            self?.finishButtonsWrite(sent: sent, changes: changes, confirmed: confirmed, wasSent: wasSent)
        }
    }

    private func finishButtonsWrite(sent: [ButtonAction], changes: [Int: UInt8], confirmed: ButtonsReport?, wasSent: Bool) {
        isWritingButtons = false
        hasPendingButtonEdits = false
        if let confirmed {
            buttonsKnown = confirmed.codes
        } else if wasSent, var known = buttonsKnown {
            for (entry, code) in changes { known[entry] = code }
            buttonsKnown = known
        }

        if buttonActions != sent {
            // The user kept editing while the write was in flight: send the newer state too.
            hasPendingButtonEdits = true
            pushButtonsIfNeeded()
        } else if let confirmed {
            // Show what the mouse really holds (normally identical to what was sent).
            applyMouseButtons(confirmed)
        }
    }

    /// Loads the mouse's button layout into the UI (skipped while the user has unsent edits).
    private func applyMouseButtons(_ report: ButtonsReport) {
        guard !hasPendingButtonEdits, !isWritingButtons else { return }
        let codes = report.codes
        buttonsKnown = codes
        isApplyingButtons = true
        defer { isApplyingButtons = false }

        let actions = ButtonMap.entries.map { ButtonAction(code: codes[$0]) }
        if buttonActions != actions { buttonActions = actions }
    }

    // MARK: Lighting & power sync

    private static func makeLighting(mode: LightMode, brightness: Double, speed: Double, color: Color, sleep: Int) -> LightingSettings {
        let rgb = LEDColor.rgb(of: color)
        return LightingSettings(
            mode: mode.hardware,
            brightness: min(max(Int(brightness.rounded()), 1), 8),
            speed: min(max(Int(speed.rounded()), 1), 5),
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue,
            sleepSeconds: sleep
        )
    }

    private var currentLighting: LightingSettings {
        Self.makeLighting(mode: lightMode, brightness: brightnessLevel, speed: lightSpeedLevel, color: lightColor, sleep: sleepAfterSeconds)
    }

    /// ↻ button on the Lighting and Power pages: drops unsent edits and loads what the mouse holds right now.
    func syncLightingFromMouse() {
        guard let device, !isWritingLighting, !isSyncingLighting else { return }
        hasPendingLightingEdits = false
        isSyncingLighting = true
        device.refreshLighting(userInitiated: true) { [weak self] settings in
            guard let self else { return }
            self.isSyncingLighting = false
            if let settings { self.applyMouseLighting(settings) }
        }
    }

    private func noteLightingChange(_ settings: LightingSettings) {
        guard !isApplyingLighting, let known = lightingKnown else { return }
        lightingRetries = 0   // a new edit gets a fresh set of retries
        if settings != known { hasPendingLightingEdits = true }
    }

    private func pushLightingIfNeeded() {
        guard !isApplyingLighting, !isWritingLighting, !isSyncingLighting else { return }
        guard let device, let known = lightingKnown else {
            hasPendingLightingEdits = false
            return
        }
        let wanted = currentLighting
        guard wanted != known else {
            hasPendingLightingEdits = false
            return
        }

        isWritingLighting = true
        device.writeLighting(wanted) { [weak self] confirmed in
            self?.finishLightingWrite(sent: wanted, confirmed: confirmed)
        }
    }

    private func finishLightingWrite(sent: LightingSettings, confirmed: LightingSettings?) {
        isWritingLighting = false
        hasPendingLightingEdits = false
        if let confirmed {
            lightingKnown = confirmed
            lightingRetries = 0
        } else if currentLighting == sent, lightingRetries < 3 {
            // The write failed (typically a sleeping mouse): keep the edit and try again in a moment,
            // so the LED / sleep timer never silently stays different from what the UI shows.
            lightingRetries += 1
            hasPendingLightingEdits = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.pushLightingIfNeeded() }
            return
        }

        if currentLighting != sent {
            // The user kept editing while the write was in flight: send the newer state too.
            hasPendingLightingEdits = true
            pushLightingIfNeeded()
        } else if let confirmed, confirmed != sent {
            // The mouse disagrees with what we sent: show what it really holds.
            applyMouseLighting(confirmed)
        }
    }

    /// Loads the mouse's lighting / sleep settings into the UI (skipped while the user has unsent edits).
    private func applyMouseLighting(_ settings: LightingSettings) {
        guard !hasPendingLightingEdits, !isWritingLighting else { return }
        lightingKnown = settings
        isApplyingLighting = true
        defer { isApplyingLighting = false }

        let mode = LightMode(settings.mode)
        if lightMode != mode { lightMode = mode }
        if Int(brightnessLevel.rounded()) != settings.brightness { brightnessLevel = Double(settings.brightness) }
        if Int(lightSpeedLevel.rounded()) != settings.speed { lightSpeedLevel = Double(settings.speed) }
        let rgb = LEDColor.RGB(settings.red, settings.green, settings.blue)
        if LEDColor.rgb(of: lightColor) != rgb { lightColor = rgb.color }
        if sleepAfterSeconds != settings.sleepSeconds { sleepAfterSeconds = settings.sleepSeconds }
    }

    // MARK: Low battery alert

    private func evaluateBattery(level: Int, hasReading: Bool, charging: Bool, enabled: Bool, threshold: Double) {
        guard enabled else {
            batteryAlertSent = false
            return
        }
        guard hasReading else { return }
        if charging || Double(level) > threshold + 2 {
            batteryAlertSent = false   // recovered (with a 2% margin): the next drop alerts again
            return
        }
        // Between the threshold and threshold + 2: neither alert nor re-arm, so 20% <-> 21% can't ring twice.
        if Double(level) > threshold { return }
        guard !batteryAlertSent else { return }
        batteryAlertSent = true
        BatteryNotifier.shared.notifyLowBattery(level: level)
    }

    func requestNotificationAccess() {
        Task { @MainActor [weak self] in
            let allowed = await BatteryNotifier.shared.requestAccess()
            self?.notificationsBlocked = !allowed
        }
    }

    /// Re-checks the macOS notification permission without asking (the user may have just changed it in System Settings).
    func refreshNotificationStatus() {
        guard lowBatteryAlert else {
            notificationsBlocked = false
            return
        }
        Task { @MainActor [weak self] in
            let allowed = await BatteryNotifier.shared.requestAccess(prompt: false)
            self?.notificationsBlocked = !allowed
        }
    }

    /// "Send a test alert" button: asks for permission FIRST (a notification sent before that is silently dropped),
    /// then shows the notification, and reports in the UI if macOS refuses it.
    func sendTestBatteryAlert() {
        testAlertMessage = nil
        let level = Int(alertThreshold)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let allowed = await BatteryNotifier.shared.requestAccess()
            self.notificationsBlocked = !allowed
            guard allowed else { return }
            if let problem = await BatteryNotifier.shared.postTest(level: level) {
                self.testAlertMessage = "macOS couldn't show the notification: \(problem)"
            } else {
                self.testAlertMessage = "Test alert sent. If you don't see it, check Focus / Do Not Disturb."
            }
        }
    }

    // MARK: DPI logic

    var enabledStageCount: Int { dpiStages.filter(\.isEnabled).count }

    /// Making a stage active also enables it (the mouse only cycles through enabled stages).
    func selectStage(_ id: Int) {
        guard dpiStages.indices.contains(id) else { return }
        dpiStages[id].isEnabled = true
        activeStage = id
    }

    /// Returns false when refused: at least one stage must stay enabled.
    @discardableResult
    func setStageEnabled(_ id: Int, _ enabled: Bool) -> Bool {
        guard dpiStages.indices.contains(id) else { return false }
        if enabled {
            dpiStages[id].isEnabled = true
            return true
        }
        guard enabledStageCount > 1 else { return false }
        dpiStages[id].isEnabled = false
        if activeStage == id { activeStage = nearestEnabledStage(from: id) }
        return true
    }

    func setDPI(_ id: Int, _ value: Int) {
        guard dpiStages.indices.contains(id) else { return }
        let snapped = DPIRules.snap(value)
        if dpiStages[id].dpi != snapped { dpiStages[id].dpi = snapped }
    }

    func pushRecent(_ color: StageColor) {
        recentColors.removeAll { $0.hex == color.hex }
        recentColors.insert(color, at: 0)
        if recentColors.count > 6 { recentColors.removeLast(recentColors.count - 6) }
    }

    private func nearestEnabledStage(from id: Int) -> Int {
        for offset in 1..<dpiStages.count {
            let index = (id + offset) % dpiStages.count
            if dpiStages[index].isEnabled { return index }
        }
        return id
    }
}

// MARK: - Shared building blocks

/// Rounded panel background. The blurred drop shadow is only drawn in light mode: it is invisible on the
/// dark window anyway, and blurring a large shape on every frame is what made window resizing lag.
struct PanelBackground: View {
    let isDark: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if isDark {
            shape
                .fill(Color.black.opacity(0.4))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        } else {
            shape
                .fill(Color.white)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)
        }
    }
}

/// Soft press feedback used by every button in the panel.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

private struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct SliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(valueText)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

/// Capsule segmented control whose highlight glides between options.
private struct PillSegmented<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == option ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "pill", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

private struct SwatchRow: View {
    @Binding var selection: Color

    var body: some View {
        // Compared by the bytes the mouse stores, so the ring follows the real LED colour.
        let current = LEDColor.rgb(of: selection)

        HStack(spacing: 10) {
            ForEach(LEDColor.presets, id: \.self) { preset in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = preset.color }
                } label: {
                    Circle()
                        .fill(preset.color)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .padding(-4)
                                .opacity(current == preset ? 1 : 0)
                        )
                }
                .buttonStyle(PressableStyle())
            }
            ColorPicker("", selection: $selection, supportsOpacity: false)
                .labelsHidden()
        }
    }
}

// MARK: - Tab bar

private struct TabButton: View {
    let tab: ConfigTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(tab.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(hovering ? 1 : 0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.accentColor)
                                .matchedGeometryEffect(id: "tab-highlight", in: namespace)
                        } else {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(hovering ? 0.13 : 0.06))
                        }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
        }
    }
}

// MARK: - DPI page

/// Editable DPI value: typed numbers are snapped to what the mouse accepts.
private struct DPIField: View {
    let dpi: Int
    let onCommit: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12))
                .monospacedDigit()
                .frame(width: 44)
                .focused($focused)
                .onSubmit { commit() }
            Text("DPI")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(focused ? 0.14 : 0.06)))
        .onAppear { text = String(dpi) }
        .onChange(of: dpi) { _, newValue in
            if !focused { text = String(newValue) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        if let value = Int(digits), text != String(dpi) {
            onCommit(DPIRules.snap(value))
        }
        text = String(DPIRules.snap(Int(digits) ?? dpi))
    }
}

private struct DPIStageRow: View {
    let stage: DPIStageState
    let isActive: Bool
    let onSelect: () -> Void
    let onEnabled: (Bool) -> Void
    let onDPI: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { stage.isEnabled }, set: { onEnabled($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

            Group {
                Button(action: onSelect) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(stage.color.color)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 0.5))
                        Text("\(stage.id + 1)")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .frame(width: 52, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isActive ? Color.accentColor : Color.primary.opacity(0.07))
                    )
                }
                .buttonStyle(PressableStyle())

                Slider(
                    value: Binding(
                        get: { DPIRules.step(for: stage.dpi) },
                        set: { onDPI(DPIRules.dpi(forStep: $0)) }
                    ),
                    in: DPIRules.stepRange,
                    step: 1
                )
                .tint(stage.color.tint)
                .disabled(!stage.isEnabled)

                DPIField(dpi: stage.dpi, onCommit: onDPI)
                    .disabled(!stage.isEnabled)
            }
            .opacity(stage.isEnabled ? 1 : 0.4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive && stage.isEnabled ? stage.color.color.opacity(0.14) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.2), value: stage.isEnabled)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

/// The colour disc itself never changes, so it is rasterised once instead of re-drawing two gradients per frame.
private struct WheelDisc: View {
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(
                AngularGradient(
                    gradient: Gradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }),
                    center: .center
                )
            )
            Circle().fill(
                RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius)
            )
        }
        .drawingGroup()
    }
}

/// Hue/saturation disc. Brightness is a separate slider, and is shown by darkening the disc.
private struct ColorWheel: View {
    @Binding var color: StageColor
    var size: CGFloat = 140
    var onCommit: () -> Void

    var body: some View {
        let radius = size / 2
        let knobX = radius + CGFloat(cos(color.h * 2 * Double.pi) * color.s) * radius
        let knobY = radius + CGFloat(sin(color.h * 2 * Double.pi) * color.s) * radius

        ZStack {
            WheelDisc(radius: radius)
            Circle().fill(Color.black.opacity(1 - color.b))
            Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)

            Circle()
                .fill(color.color)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                .shadow(color: Color.black.opacity(0.35), radius: 2)
                .position(x: knobX, y: knobY)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in update(at: value.location, radius: radius) }
                .onEnded { _ in onCommit() }
        )
    }

    private func update(at point: CGPoint, radius: CGFloat) {
        let dx = Double(point.x - radius)
        let dy = Double(point.y - radius)
        var hue = atan2(dy, dx) / (2 * Double.pi)
        if hue < 0 { hue += 1 }
        var next = color
        next.h = hue
        next.s = min(sqrt(dx * dx + dy * dy) / Double(radius), 1)
        if next.b < 0.05 { next.b = 1 }   // dragging on the wheel from "off" brings the colour back
        color = next
    }
}

private struct BrightnessSlider: View {
    @Binding var color: StageColor
    var onCommit: () -> Void
    private let thumb: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [.black, StageColor(h: color.h, s: color.s, b: 1).color],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                Circle()
                    .fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5))
                    .shadow(color: Color.black.opacity(0.3), radius: 2)
                    .offset(x: (width - thumb) * CGFloat(color.b))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let track = max(width - thumb, 1)
                        color.b = Double(min(max((value.location.x - thumb / 2) / track, 0), 1))
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: thumb)
    }
}

private struct HexField: View {
    @Binding var color: StageColor
    var onCommit: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("#RRGGBB", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(focused ? 0.14 : 0.06)))
            .onAppear { text = color.hex }
            .onChange(of: color) { _, newValue in
                if !focused { text = newValue.hex }
            }
            .onSubmit { apply() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { apply() }
            }
    }

    private func apply() {
        // Only touch the colour when the text really differs, so a plain focus change can't lose hue/saturation.
        if text.uppercased() != color.hex, let parsed = StageColor(hex: text) {
            color = parsed
            onCommit()
        }
        text = color.hex
    }
}

private struct ColorDot: View {
    let color: StageColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(-4)
                        .opacity(isSelected ? 1 : 0)
                )
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

private struct StageColorEditor: View {
    @ObservedObject var state: ConfigState
    private let presets: [StageColor] = [
        "#FF0000", "#FF8000", "#FFFF00", "#00FF00", "#00FFFF",
        "#0080FF", "#8000FF", "#FF00FF", "#FFFFFF", "#000000"
    ].map { StageColor.hex($0) }

    var body: some View {
        let id = state.activeStage
        let stage = state.dpiStages[id]
        let binding = Binding<StageColor>(
            get: { state.dpiStages[id].color },
            set: { state.dpiStages[id].color = $0 }
        )

        SettingCard {
            HStack {
                Text("Stage \(id + 1) colour")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(stage.dpi) DPI")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: stage.dpi)
            }

            HStack(alignment: .top, spacing: 18) {
                ColorWheel(color: binding) { state.pushRecent(binding.wrappedValue) }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(stage.color.color)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        HexField(color: binding) { state.pushRecent(binding.wrappedValue) }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Brightness").font(.system(size: 11)).foregroundStyle(.secondary)
                        BrightnessSlider(color: binding) { state.pushRecent(binding.wrappedValue) }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Recent").font(.system(size: 11)).foregroundStyle(.secondary)
                        if state.recentColors.isEmpty {
                            Text("Your last picks show up here")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(height: 22, alignment: .leading)
                        } else {
                            HStack(spacing: 7) {
                                ForEach(state.recentColors, id: \.self) { recent in
                                    ColorDot(color: recent, isSelected: recent.hex == stage.color.hex) {
                                        binding.wrappedValue = recent
                                    }
                                }
                            }
                            .frame(height: 22, alignment: .leading)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    ColorDot(color: preset, isSelected: preset.hex == stage.color.hex) {
                        withAnimation(.easeInOut(duration: 0.2)) { binding.wrappedValue = preset }
                        state.pushRecent(preset)
                    }
                }
            }
        }
    }
}

/// Shows whether the DPI stages are in sync with the mouse; the button reads them from the mouse again.
private struct SyncBadge: View {
    let state: DPISyncState
    let onRefresh: () -> Void

    private var tint: Color {
        switch state {
        case .synced: .green
        case .searching, .reading, .writing: .accentColor
        case .unverified: .yellow
        case .noMouse: .secondary
        case .failed: .orange
        }
    }

    private var isBusy: Bool {
        switch state {
        case .searching, .reading, .writing: true
        default: false
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(state.label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.pulse, isActive: isBusy)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(isBusy || state == .noMouse)
            .help("Sync: read the settings from the mouse now")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .animation(.easeInOut(duration: 0.2), value: state)
    }
}

private struct DPIPage: View {
    @ObservedObject var state: ConfigState
    @ObservedObject var device: DeviceViewModel
    @State private var notice: String?
    private let quickValues = [400, 800, 1200, 1600, 3200, 6400]

    var body: some View {
        let active = state.dpiStages[state.activeStage]

        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "DPI")

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(active.color.color)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 0.5))
                    Text("Active: stage \(active.id + 1) · \(active.dpi) DPI")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.15), value: active.dpi)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.07)))

                Spacer(minLength: 8)

                SyncBadge(state: device.dpiSyncState) { state.syncFromMouse() }
            }

            VStack(spacing: 6) {
                ForEach(state.dpiStages) { stage in
                    DPIStageRow(
                        stage: stage,
                        isActive: stage.id == state.activeStage,
                        onSelect: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.selectStage(stage.id) }
                        },
                        onEnabled: { enabled in
                            var accepted = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                accepted = state.setStageEnabled(stage.id, enabled)
                            }
                            if !accepted { flash("At least one stage must stay enabled.") }
                        },
                        onDPI: { state.setDPI(stage.id, $0) }
                    )
                }
            }

            if let notice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            SettingCard {
                Text("Quick DPI for stage \(active.id + 1)")
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 8) {
                    ForEach(quickValues, id: \.self) { value in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                state.setDPI(active.id, value)
                            }
                        } label: {
                            Text("\(value)")
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(active.dpi == value ? Color.white : Color.primary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(active.dpi == value ? Color.accentColor : Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }

            StageColorEditor(state: state)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: notice)
    }

    private func flash(_ message: String) {
        notice = message
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if notice == message { notice = nil }
        }
    }
}

// MARK: - Other pages

private struct PerformancePage: View {
    @ObservedObject var state: ConfigState
    @ObservedObject var device: DeviceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                SectionHeader(title: "Performance", subtitle: "Polling and sensor behaviour. Changes are sent to the mouse as you make them.")
                Spacer(minLength: 8)
                SyncBadge(state: device.performanceSyncState) { state.syncPerformanceFromMouse() }
            }

            SettingCard {
                Text("Polling rate").font(.system(size: 13, weight: .medium))
                PillSegmented(options: [125, 250, 500, 1000], label: { "\($0) Hz" }, selection: $state.pollingRate)
            }

            SettingCard {
                ToggleRow(title: "Ripple control", subtitle: "Smooths movement at high DPI.", isOn: $state.rippleControl)
                Divider()
                ToggleRow(title: "Angle snapping", subtitle: "Straightens near-straight lines.", isOn: $state.angleSnapping)
            }

            SettingCard {
                SliderRow(title: "Button response time", valueText: "\(Int(state.debounceMs)) ms",
                          value: $state.debounceMs, range: 2...25)
                Text("Debounce: lower reacts faster, higher filters accidental double clicks.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ButtonsPage: View {
    @ObservedObject var state: ConfigState
    @ObservedObject var device: DeviceViewModel
    private let names = ["Left button", "Right button", "Middle button", "Forward side button", "Back side button"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                SectionHeader(title: "Buttons", subtitle: "Choose what each button does. Changes are sent to the mouse as you make them.")
                Spacer(minLength: 8)
                SyncBadge(state: device.buttonsSyncState) { state.syncButtonsFromMouse() }
            }

            SettingCard {
                ForEach(0..<names.count, id: \.self) { index in
                    HStack {
                        Text(names[index]).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $state.buttonActions[index]) {
                            ForEach(ButtonAction.selectable + (state.buttonActions[index] == .other ? [ButtonAction.other] : [])) { action in
                                Text(action.rawValue).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }
                    if index < names.count - 1 { Divider() }
                }
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.resetButtonsToFactory() }
            } label: {
                Text("Reset to factory")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(PressableStyle())
        }
    }
}

private struct LightingPage: View {
    @ObservedObject var state: ConfigState
    @ObservedObject var device: DeviceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                SectionHeader(title: "Lighting", subtitle: "Effect, brightness and colour of the mouse LED. Changes are sent to the mouse as you make them.")
                Spacer(minLength: 8)
                SyncBadge(state: device.lightingSyncState) { state.syncLightingFromMouse() }
            }

            Label("Lighting mode changes are available only over 2.4G wireless. They are not supported while the mouse is connected by cable.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            SettingCard {
                Text("Mode").font(.system(size: 13, weight: .medium))
                // Seven modes don't fit a narrow window in one row: let the row scroll sideways.
                ScrollView(.horizontal) {
                    PillSegmented(options: LightMode.allCases, label: { $0.rawValue }, selection: $state.lightMode)
                }
                .scrollIndicators(.hidden)
            }

            if state.lightMode != .off {
                SettingCard {
                    SliderRow(title: "Brightness", valueText: "\(Int((state.brightnessLevel / 8 * 100).rounded()))%",
                              value: $state.brightnessLevel, range: 1...8, step: 1)
                    if state.lightMode.usesSpeed {
                        SliderRow(title: "Speed", valueText: "\(Int(state.lightSpeedLevel.rounded())) / 5",
                                  value: $state.lightSpeedLevel, range: 1...5, step: 1)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                if state.lightMode.usesColor {
                    SettingCard {
                        Text("Colour").font(.system(size: 13, weight: .medium))
                        SwatchRow(selection: $state.lightColor)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if state.lightMode.followsDPIStage {
                    Label("The LED takes the colour of the active DPI stage (set it in the DPI tab).", systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.lightMode)
    }
}

private struct PowerPage: View {
    @ObservedObject var state: ConfigState
    @ObservedObject var device: DeviceViewModel

    /// The mouse counts in half-minutes, so 30 s is the shortest timer it can hold (10 s isn't possible).
    /// If the mouse holds a value that isn't one of the presets, it is added so the current setting is always visible.
    private var sleepOptions: [Int] {
        let presets = [30, 60, 120, 300, 600]
        return presets.contains(state.sleepAfterSeconds) ? presets : (presets + [state.sleepAfterSeconds]).sorted()
    }

    private func sleepLabel(_ seconds: Int) -> String {
        seconds >= 60 && seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                SectionHeader(title: "Power", subtitle: "Sleep behaviour and battery alerts. The sleep timer is sent to the mouse as you change it.")
                Spacer(minLength: 8)
                SyncBadge(state: device.lightingSyncState) { state.syncLightingFromMouse() }
            }

            SettingCard {
                Text("Sleep after").font(.system(size: 13, weight: .medium))
                PillSegmented(options: sleepOptions, label: sleepLabel, selection: $state.sleepAfterSeconds)
                Text("The mouse goes to sleep after this much inactivity. Moving it wakes it up.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            SettingCard {
                ToggleRow(title: "Low battery alert", subtitle: "Warn when the charge drops below the threshold.",
                          isOn: $state.lowBatteryAlert)
                if state.lowBatteryAlert {
                    SliderRow(title: "Alert threshold", valueText: "\(Int(state.alertThreshold))%",
                              value: $state.alertThreshold, range: 5...50, step: 5)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    HStack(spacing: 10) {
                        Button {
                            state.sendTestBatteryAlert()
                        } label: {
                            Text("Send test alert")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(PressableStyle())

                        if state.notificationsBlocked {
                            Label("Notifications are off for this app. Turn them on in System Settings › Notifications.",
                                  systemImage: "exclamationmark.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    if let message = state.testAlertMessage {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.lowBatteryAlert)
        .animation(.easeInOut(duration: 0.2), value: state.notificationsBlocked)
        .onAppear { state.refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshNotificationStatus()
        }
    }
}

// MARK: - Panel

/// Holds sizes without publishing them: reading or writing these never triggers a SwiftUI update.
private final class PanelSizeBox {
    var live: CGSize = .zero
    var frozen: CGSize?
}

struct ConfigPanelView: View {
    let isDark: Bool
    @ObservedObject var device: DeviceViewModel
    @StateObject private var state = ConfigState()
    @StateObject private var resize = WindowResizeMonitor()
    @State private var selected: ConfigTab = .dpi
    @State private var sizes = PanelSizeBox()
    @Namespace private var tabNamespace

    /// While the window is being resized (dragged, zoomed, full screen) the content keeps the size it had when
    /// the resize started. Only the panel's background and clip follow the window, so the page (8 DPI rows with
    /// sliders, text fields, toggles, the colour wheel...) isn't laid out again on every frame. One real layout
    /// happens when the resize ends.
    private var lockedSize: CGSize? {
        guard resize.isResizing else {
            sizes.frozen = nil
            return nil
        }
        if sizes.frozen == nil, sizes.live.width > 0, sizes.live.height > 0 { sizes.frozen = sizes.live }
        return sizes.frozen
    }

    var body: some View {
        let locked = lockedSize

        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                content
                    .frame(width: locked?.width, height: locked?.height, alignment: .topLeading)
            }
            .clipped()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { sizes.live = $0 }
            .background(PanelBackground(isDark: isDark))
            .onAppear {
                state.attach(device)
                resize.start()
            }
            .onDisappear { resize.stop() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ConfigTab.allCases) { tab in
                        TabButton(tab: tab, isSelected: selected == tab, namespace: tabNamespace) {
                            selected = tab
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            // Only the selected page is built. Keeping all five alive meant every hidden page was laid out
            // again on each frame of a window resize.
            ZStack(alignment: .topLeading) {
                ScrollView {
                    page(for: selected)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .id(selected)
                .transition(.opacity)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: selected)
    }

    @ViewBuilder
    private func page(for tab: ConfigTab) -> some View {
        switch tab {
        case .dpi: DPIPage(state: state, device: device)
        case .performance: PerformancePage(state: state, device: device)
        case .buttons: ButtonsPage(state: state, device: device)
        case .lighting: LightingPage(state: state, device: device)
        case .power: PowerPage(state: state, device: device)
        }
    }
}
