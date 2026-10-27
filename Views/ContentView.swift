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
            
            Text("Waiting for ATTACK SHARK X11 device...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
