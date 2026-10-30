import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = DeviceViewModel()
    
    public var body: some View {
        Group {
            if viewModel.isConnected {
                MouseDashboardView(viewModel: viewModel)
            } else {
                ConnectionStatusView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 800, minHeight: 550)
    }
}

private struct ConnectionStatusView: View {
    @ObservedObject var viewModel: DeviceViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
                .symbolEffect(.pulse)
            
            Text("SharkControl")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(viewModel.deviceName)
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 6) {
                Text("Waiting for ATTACK SHARK X11 device...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Bluetooth is not supported. Please connect your mouse using a USB cable or a 2.4 GHz wireless dongle")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .opacity(0.8)
            }
            .padding(.top, 10)
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        // Waiting screen is dark-only (no theme switcher here); it must not inherit the dashboard's light mode.
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
