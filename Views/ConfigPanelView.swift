// ConfigPanelView.swift
// Configuration menu shown to the right of the live mouse test.
// UI only for now: everything is bound to `ConfigState`, which the HID backend can read/write later.

import SwiftUI
import Combine

struct DPIStage: Identifiable {
    let id: Int
    var isEnabled: Bool
    var dpi: Double
    var color: Color
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
    @Published var dpiStages: [DPIStage] = {
        let dpis: [Double] = [800, 1600, 2400, 3200, 5000, 22000, 800, 800]
        let colors: [Color] = [.red, .green, .blue, .yellow, .cyan, .purple, .orange, .white]
        return (0..<8).map { DPIStage(id: $0, isEnabled: $0 < 6, dpi: dpis[$0], color: colors[$0]) }
    }()
    @Published var activeStage = 1

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

// MARK: - Pages

private struct DPIStageRow: View {
    @Binding var stage: DPIStage
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $stage.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Circle().fill(stage.color).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
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

            Slider(value: $stage.dpi, in: 100...22000, step: 100)
                .disabled(!stage.isEnabled)

            Text("\(Int(stage.dpi)) DPI")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .frame(width: 76, alignment: .trailing)
        }
        .opacity(stage.isEnabled ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: stage.isEnabled)
    }
}

private struct DPIPage: View {
    @ObservedObject var state: ConfigState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "DPI stages",
                subtitle: "Click a number to make that stage active and edit its colour. The mouse's DPI button cycles through the enabled stages."
            )

            VStack(spacing: 8) {
                ForEach($state.dpiStages) { $stage in
                    DPIStageRow(stage: $stage, isActive: state.activeStage == stage.id) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.activeStage = stage.id }
                    }
                }
            }

            SettingCard {
                Text("Stage \(state.activeStage + 1) colour")
                    .font(.system(size: 13, weight: .medium))
                SwatchRow(selection: Binding(
                    get: { state.dpiStages[state.activeStage].color },
                    set: { state.dpiStages[state.activeStage].color = $0 }
                ))
            }
        }
    }
}

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

            Text("Interface preview. Changes are not sent to the mouse yet.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(isDark ? Color.black.opacity(0.4) : Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 5)
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: selected)
    }

    @ViewBuilder
    private func page(for tab: ConfigTab) -> some View {
        switch tab {
        case .dpi: DPIPage(state: state)
        case .performance: PerformancePage(state: state)
        case .buttons: ButtonsPage(state: state)
        case .lighting: LightingPage(state: state)
        case .power: PowerPage(state: state)
        }
    }
}
