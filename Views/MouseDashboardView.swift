import SwiftUI

public struct MouseDashboardView: View {
    @ObservedObject public var viewModel: DeviceViewModel
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    /// Screen area where the physical mouse is visualized (the live-test panel only).
    @State private var testZone = MouseTestZone()
    
    public init(viewModel: DeviceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Status Bar
            ZStack {
                HStack(spacing: 20) {
                // Connection badge
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isWiredConnection ? "cable.connector" : "wifi")
                        .foregroundColor(.accentColor)
                    Text(viewModel.isWiredConnection ? "Wired Connection" : "2.4G Wireless")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
                
                Spacer()
                
                // Battery indicator (top right)
                HStack(spacing: 8) {
                    Image(systemName: batteryIcon(for: viewModel.batteryLevel))
                        .foregroundColor(batteryColor(for: viewModel.batteryLevel))
                    Text(viewModel.hasBatteryReading ? "\(viewModel.batteryLevel)% Battery" : "Battery: — (mouse adormit?)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(batteryColor(for: viewModel.batteryLevel))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(batteryColor(for: viewModel.batteryLevel).opacity(0.15))
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.3), value: viewModel.batteryLevel)
                
                // Dark / Light Mode Button
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0)) {
                        isDarkMode.toggle()
                    }
                }) {
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                        .foregroundColor(isDarkMode ? .yellow : .blue)
                        .font(.system(size: 16))
                        .scaleEffect(isDarkMode ? 1.0 : 0.95)
                        .transition(.scale.combined(with: .opacity))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
                }

                Text("Attack Shark X11")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(20)
            
            Divider()
            
            // Live test (left, narrow) + configuration menu (right)
            HStack(spacing: 20) {
                livePanel
                    .frame(minWidth: 240, idealWidth: 290, maxWidth: 330)

                ConfigPanelView(isDark: isDarkMode, device: viewModel)
                    .frame(maxWidth: .infinity)
            }
            .padding(25)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDarkMode ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor))
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .animation(.easeInOut(duration: 0.5), value: isDarkMode)
    }

    /// Narrow panel with the SVG mouse that lights up on physical clicks / scrolling.
    private var livePanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(isDarkMode ? Color.black.opacity(0.4) : Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 5)
            
            VStack(spacing: 15) {
                Text("Live Test")
                    .font(.system(size: 10))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(2)

                // Real SVG illustration; highlights follow physical mouse events (see MouseInputMonitor).
                MouseVisualizerView(isDark: isDarkMode, zone: testZone)
                    .aspectRatio(520.0 / 1000.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("Press a button or scroll the wheel to test")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(MouseTestZoneReader(zone: testZone))
    }
    
    private func batteryColor(for level: Int) -> Color {
        if viewModel.isCharging {
            return .green
        }
        switch level {
        case 60...100: return .green
        case 30..<60:  return .yellow
        case 15..<30:  return .orange
        default:       return .red
        }
    }
    
    private func batteryIcon(for level: Int) -> String {
        if viewModel.isCharging {
            return "battery.100.bolt"
        }
        switch level {
        case 75...100: return "battery.100"
        case 50..<75:  return "battery.75"
        case 25..<50:  return "battery.50"
        default:       return "battery.25"
        }
    }
}
