import SwiftUI

public struct MouseDashboardView: View {
    @ObservedObject public var viewModel: DeviceViewModel
    
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    
    @State private var activeLeftClick: Bool = false
    @State private var activeRightClick: Bool = false
    @State private var activeMiddleClick: Bool = false
    @State private var activeForward: Bool = false
    @State private var activeBack: Bool = false

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
                
                // Battery Percentage with Dynamic Color Coding
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
                
                // Theme Toggle
                Button(action: {
                    isDarkMode.toggle()
                }) {
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                        .foregroundColor(isDarkMode ? .yellow : .blue)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .padding(8)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
            }
            .padding(20)
            
            Divider()
            
            // Interactive Mouse Graphic
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(isDarkMode ? Color.black.opacity(0.5) : Color.white)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                
                VStack(spacing: 15) {
                    Text("ATTACK SHARK X11")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .tracking(2)
                    
                    ZStack {
                        Image(systemName: "computermouse.fill")
                            .font(.system(size: 220))
                            .foregroundColor(isDarkMode ? Color(nsColor: .darkGray) : Color(nsColor: .lightGray))
                        
                        RoundedRectangle(cornerRadius: 30)
                            .fill(activeLeftClick ? Color.orange : Color.clear)
                            .frame(width: 55, height: 90)
                            .offset(x: -32, y: -50)
                            .animation(.easeInOut(duration: 0.1), value: activeLeftClick)
                        
                        RoundedRectangle(cornerRadius: 30)
                            .fill(activeRightClick ? Color.orange : Color.clear)
                            .frame(width: 55, height: 90)
                            .offset(x: 32, y: -50)
                            .animation(.easeInOut(duration: 0.1), value: activeRightClick)
                        
                        Capsule()
                            .fill(activeMiddleClick ? Color.orange : Color.clear)
                            .frame(width: 14, height: 40)
                            .offset(x: 0, y: -45)
                            .animation(.easeInOut(duration: 0.1), value: activeMiddleClick)
                        
                        Capsule()
                            .fill(activeForward ? Color.orange : Color.clear)
                            .frame(width: 25, height: 8)
                            .offset(x: -72, y: 15)
                            .animation(.easeInOut(duration: 0.1), value: activeForward)
                        
                        Capsule()
                            .fill(activeBack ? Color.orange : Color.clear)
                            .frame(width: 25, height: 8)
                            .offset(x: -72, y: 35)
                            .animation(.easeInOut(duration: 0.1), value: activeBack)
                    }
                    
                    Text("Click mouse buttons to test in real time")
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
