import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DeviceViewModel()

    var body: some View {
        VStack(spacing: 20) {
            // Status Icon
            Image(systemName: viewModel.isConnected ? "computermouse.fill" : "computermouse")
                .font(.system(size: 60))
                .foregroundColor(viewModel.isConnected ? .green : .secondary)
                .symbolEffect(.bounce, value: viewModel.isConnected)
            
            // App Title
            Text("SharkControl")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Device Status / Name
            Text(viewModel.deviceName)
                .font(.headline)
                .foregroundColor(viewModel.isConnected ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Controls Section (Enabled only when connected)
            VStack(spacing: 12) {
                Text("Device Settings")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 15) {
                    Button(action: {
                        print("🎛️ DPI settings requested")
                    }) {
                        Label("DPI Settings", systemImage: "speedometer")
                    }
                    .disabled(!viewModel.isConnected)
                    
                    Button(action: {
                        print("🔋 Battery status requested")
                    }) {
                        Label("Check Battery", systemImage: "battery.100")
                    }
                    .disabled(!viewModel.isConnected)
                }
            }
            
            Spacer()
            
            // Connection hint
            Text(viewModel.isConnected ? "Connected to ATTACK SHARK X11" : "Connect the ATTACK SHARK X11 mouse via cable or receiver to begin.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 500, height: 380)
    }
}

#Preview {
    ContentView()
}
