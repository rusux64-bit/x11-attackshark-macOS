// ConfigPanelView.swift
// Configuration menu shown to the right of the live mouse test.
// UI only for now: everything is bound to `ConfigState`, which the HID backend can read/write later.

import SwiftUI
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

    var id: String { rawValue }
}

enum LightMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case steady = "Steady"
    case breathing = "Breathing"
    case rainbow = "Rainbow"

    var id: String { rawValue }
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

    // Performance
    @Published var pollingRate = 1000
    @Published var liftOff = 2
    @Published var motionSync = true
    @Published var rippleControl = false
    @Published var angleSnapping = false
    @Published var debounceMs: Double = 4

    // Buttons (left, right, middle, forward, back)
    @Published var buttonActions: [ButtonAction] = [.leftClick, .rightClick, .middleClick, .forward, .back]

    // Lighting
    @Published var lightMode: LightMode = .steady
    @Published var brightness: Double = 80
    @Published var lightSpeed: Double = 50
    @Published var lightColor: Color = .green

    // Power
    @Published var sleepAfterSeconds = 60
    @Published var lowBatteryAlert = true
    @Published var alertThreshold: Double = 20

    // MARK: Mouse sync (DPI only)

    private weak var device: DeviceViewModel?
    /// What the mouse is known to hold (nil until the first successful read).
    private var deviceSignature: DPISignature?
    private var hasPendingLocalEdits = false
    private var isApplyingMouse = false
    private var isWriting = false
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
    }

    /// Connects the DPI state to the mouse: mouse -> UI updates, UI edits -> mouse writes.
    func attach(_ device: DeviceViewModel) {
        guard self.device !== device else { return }
        self.device = device
        device.$mouseDPIConfiguration
            .compactMap { $0 }
            .sink { [weak self] configuration in self?.applyMouse(configuration) }
            .store(in: &cancellables)
    }

    private func noteLocalChange(stages: [DPIStageState], active: Int) {
        guard !isApplyingMouse, let known = deviceSignature else { return }
        if Self.signature(stages: stages, active: active) != known { hasPendingLocalEdits = true }
    }

    private func pushDPIIfNeeded() {
        guard !isApplyingMouse, !isWriting else { return }
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
    private let presets: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .white]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, color in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = color }
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .padding(-4)
                                .opacity(selection == color ? 1 : 0)
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
            Circle().fill(
                AngularGradient(
                    gradient: Gradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }),
                    center: .center
                )
            )
            Circle().fill(
                RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius)
            )
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
        case .searching, .writing: .accentColor
        case .unverified: .yellow
        case .noMouse: .secondary
        case .failed: .orange
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
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help("Read the DPI settings from the mouse again")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
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

                SyncBadge(state: device.dpiSyncState) { device.refreshDPI() }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Performance", subtitle: "Tracking and report behaviour of the sensor.")

            SettingCard {
                Text("Polling rate").font(.system(size: 13, weight: .medium))
                PillSegmented(options: [125, 250, 500, 1000], label: { "\($0) Hz" }, selection: $state.pollingRate)
                Text("Lift-off distance").font(.system(size: 13, weight: .medium))
                PillSegmented(options: [1, 2], label: { "\($0) mm" }, selection: $state.liftOff)
            }

            SettingCard {
                ToggleRow(title: "Motion sync", subtitle: "Aligns sensor reports with the polling interval.", isOn: $state.motionSync)
                Divider()
                ToggleRow(title: "Ripple control", subtitle: "Smooths movement at high DPI.", isOn: $state.rippleControl)
                Divider()
                ToggleRow(title: "Angle snapping", subtitle: "Straightens near-straight lines.", isOn: $state.angleSnapping)
            }

            SettingCard {
                SliderRow(title: "Debounce time", valueText: "\(Int(state.debounceMs)) ms",
                          value: $state.debounceMs, range: 0...20)
            }
        }
    }
}

private struct ButtonsPage: View {
    @ObservedObject var state: ConfigState
    private let names = ["Left button", "Right button", "Middle button", "Forward side button", "Back side button"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Buttons", subtitle: "Choose what each button does.")

            SettingCard {
                ForEach(0..<names.count, id: \.self) { index in
                    HStack {
                        Text(names[index]).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $state.buttonActions[index]) {
                            ForEach(ButtonAction.allCases) { action in
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
        }
    }
}

private struct LightingPage: View {
    @ObservedObject var state: ConfigState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Lighting", subtitle: "Effect, brightness and colour of the mouse LED.")

            SettingCard {
                Text("Mode").font(.system(size: 13, weight: .medium))
                PillSegmented(options: LightMode.allCases, label: { $0.rawValue }, selection: $state.lightMode)
            }

            if state.lightMode != .off {
                SettingCard {
                    SliderRow(title: "Brightness", valueText: "\(Int(state.brightness))%",
                              value: $state.brightness, range: 0...100)
                    if state.lightMode == .breathing || state.lightMode == .rainbow {
                        SliderRow(title: "Speed", valueText: "\(Int(state.lightSpeed))%",
                                  value: $state.lightSpeed, range: 0...100)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                if state.lightMode != .rainbow {
                    SettingCard {
                        Text("Colour").font(.system(size: 13, weight: .medium))
                        SwatchRow(selection: $state.lightColor)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.lightMode)
    }
}

private struct PowerPage: View {
    @ObservedObject var state: ConfigState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Power", subtitle: "Sleep behaviour and battery alerts.")

            SettingCard {
                Text("Sleep after").font(.system(size: 13, weight: .medium))
                PillSegmented(
                    options: [10, 30, 60, 300],
                    label: { $0 >= 60 ? "\($0 / 60) min" : "\($0) s" },
                    selection: $state.sleepAfterSeconds
                )
            }

            SettingCard {
                ToggleRow(title: "Low battery alert", subtitle: "Warn when the charge drops below the threshold.",
                          isOn: $state.lowBatteryAlert)
                if state.lowBatteryAlert {
                    SliderRow(title: "Alert threshold", valueText: "\(Int(state.alertThreshold))%",
                              value: $state.alertThreshold, range: 5...50, step: 5)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.lowBatteryAlert)
    }
}

// MARK: - Panel

struct ConfigPanelView: View {
    let isDark: Bool
    @ObservedObject var device: DeviceViewModel
    @StateObject private var state = ConfigState()
    @State private var selected: ConfigTab = .dpi
    @Namespace private var tabNamespace

    var body: some View {
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

            // All pages stay alive and slide relative to the selected one, so the direction is always right
            // and each page keeps its own state when you switch away and back.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(ConfigTab.allCases) { tab in
                        ScrollView {
                            page(for: tab)
                                .padding(.bottom, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollIndicators(.hidden)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(x: CGFloat(tab.rawValue - selected.rawValue) * geo.size.width * 0.45)
                        .opacity(tab == selected ? 1 : 0)
                        .allowsHitTesting(tab == selected)
                    }
                }
                .clipped()
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(isDark ? Color.black.opacity(0.4) : Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 5)
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: selected)
        .onAppear { state.attach(device) }
    }

    @ViewBuilder
    private func page(for tab: ConfigTab) -> some View {
        switch tab {
        case .dpi: DPIPage(state: state, device: device)
        case .performance: PerformancePage(state: state)
        case .buttons: ButtonsPage(state: state)
        case .lighting: LightingPage(state: state)
        case .power: PowerPage(state: state)
        }
    }
}
