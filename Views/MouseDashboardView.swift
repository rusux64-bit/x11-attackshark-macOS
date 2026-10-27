import SwiftUI

public struct MouseDashboardView: View {
    @ObservedObject public var viewModel: DeviceViewModel
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    
    @StateObject private var inputMonitor = MouseInputMonitor()

    public init(viewModel: DeviceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Status Bar
            HStack(spacing: 20) {
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
                
                HStack(spacing: 8) {
                    Image(systemName: batteryIcon(for: viewModel.batteryLevel))
                        .foregroundColor(batteryColor(for: viewModel.batteryLevel))
                    Text("\(viewModel.batteryLevel)% Battery")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(batteryColor(for: viewModel.batteryLevel))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(batteryColor(for: viewModel.batteryLevel).opacity(0.15))
                .cornerRadius(8)
                
                // În interiorul HStack-ului de sus, înlocuiește butonul existent cu acesta:
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isDarkMode.toggle()
                    }
                }) {
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                        .foregroundColor(isDarkMode ? .yellow : .blue)
                        .font(.system(size: 16))
                        .rotationEffect(.degrees(isDarkMode ? 360 : 0))
                        .scaleEffect(isDarkMode ? 1.0 : 1.1)
                }
                .buttonStyle(.plain)
                .padding(8)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)

                // La sfârșitul containerului principal (înaintea modifiers-urilor finale), asigură tranziția lină:
                .animation(.easeInOut(duration: 0.3), value: isDarkMode)
                .buttonStyle(.plain)
                .padding(8)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
            }
            .padding(20)
            
            Divider()
            
            // Center Clean Schematic Area & Scroll Animations
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(isDarkMode ? Color.black.opacity(0.4) : Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 5)
                
                VStack(spacing: 15) {
                    Text("ATTACK SHARK X11 — LIVE TEST")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .tracking(2)
                    
                    ZStack {
                        // Clean Mouse Body Silhouette
                        Capsule()
                            .fill(isDarkMode ? Color(nsColor: .darkGray).opacity(0.6) : Color(nsColor: .controlBackgroundColor))
                            .frame(width: 160, height: 280)
                            .overlay(
                                Capsule()
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                            )
                        
                        // Left Click Button Zone
                        UnevenRoundedRectangle(topLeadingRadius: 70, bottomLeadingRadius: 20, bottomTrailingRadius: 10, topTrailingRadius: 10)
                            .fill(inputMonitor.activeButtons.contains(.left) ? Color.orange : (isDarkMode ? Color.gray.opacity(0.3) : Color.gray.opacity(0.15)))
                            .frame(width: 74, height: 110)
                            .offset(x: -41, y: -75)
                            .animation(.easeInOut(duration: 0.1), value: inputMonitor.activeButtons.contains(.left))
                            .onTapGesture { inputMonitor.simulateClick(.left) }
                        
                        // Right Click Button Zone
                        UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, bottomTrailingRadius: 20, topTrailingRadius: 70)
                            .fill(inputMonitor.activeButtons.contains(.right) ? Color.orange : (isDarkMode ? Color.gray.opacity(0.3) : Color.gray.opacity(0.15)))
                            .frame(width: 74, height: 110)
                            .offset(x: 41, y: -75)
                            .animation(.easeInOut(duration: 0.1), value: inputMonitor.activeButtons.contains(.right))
                            .onTapGesture { inputMonitor.simulateClick(.right) }
                        
                        // Scroll Wheel / Middle Click
                        Capsule()
                            .fill(inputMonitor.activeButtons.contains(.middle) ? Color.orange : Color.secondary.opacity(0.6))
                            .frame(width: 16, height: 50)
                            .offset(x: 0, y: -70)
                            .animation(.easeInOut(duration: 0.1), value: inputMonitor.activeButtons.contains(.middle))
                            .onTapGesture { inputMonitor.simulateClick(.middle) }
                        
                        // Scroll Up Indicator (Just above the wheel)
                        Image(systemName: "chevron.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.orange)
                            .opacity(inputMonitor.activeButtons.contains(.scrollUp) ? 1.0 : 0.0)
                            .offset(x: 0, y: -108)
                            .animation(.easeInOut(duration: 0.15), value: inputMonitor.activeButtons.contains(.scrollUp))
                        
                        // Scroll Down Indicator (Just below the wheel)
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.orange)
                            .opacity(inputMonitor.activeButtons.contains(.scrollDown) ? 1.0 : 0.0)
                            .offset(x: 0, y: -32)
                            .animation(.easeInOut(duration: 0.15), value: inputMonitor.activeButtons.contains(.scrollDown))
                        
                        // DPI / LED Indicator Strip
                        Capsule()
                            .fill(Color.cyan)
                            .frame(width: 8, height: 16)
                            .offset(x: 0, y: -5)
                        
                        // Side Forward Button (Left Side)
                        Capsule()
                            .fill(inputMonitor.activeButtons.contains(.forward) ? Color.orange : Color.secondary.opacity(0.4))
                            .frame(width: 32, height: 10)
                            .offset(x: -88, y: 15)
                            .animation(.easeInOut(duration: 0.1), value: inputMonitor.activeButtons.contains(.forward))
                            .onTapGesture { inputMonitor.simulateClick(.forward) }
                        
                        // Side Back Button (Left Side)
                        Capsule()
                            .fill(inputMonitor.activeButtons.contains(.back) ? Color.orange : Color.secondary.opacity(0.4))
                            .frame(width: 32, height: 10)
                            .offset(x: -88, y: 35)
                            .animation(.easeInOut(duration: 0.1), value: inputMonitor.activeButtons.contains(.back))
                            .onTapGesture { inputMonitor.simulateClick(.back) }
                    }
                    .frame(height: 320)
                    
                    Text("Click buttons or scroll up/down to test interactively")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(30)
            }
            .padding(25)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDarkMode ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor))
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
    
    private func batteryColor(for level: Int) -> Color {
        switch level {
        case 70...100: return .green
        case 40..<70:  return .yellow
        case 20..<40:  return .orange
        default:       return .red
        }
    }
    
    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 75...100: return "battery.100"
        case 50..<75:  return "battery.75"
        case 25..<50:  return "battery.50"
        default:       return "battery.25"
        }
    }
}
