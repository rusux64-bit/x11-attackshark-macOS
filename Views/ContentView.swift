import SwiftUI

struct ContentView: View {
    // Instanciezi scanerul pentru mouse-ul ATTACK SHARK X11
    private let scanner = HIDDeviceScanner()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "computermouse")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("SharkControl")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Conectează mouse-ul ATTACK SHARK X11 prin cablu sau receptor pentru a începe.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(width: 450, height: 320)
        .onAppear {
            // Pornește scanerul IOKit imediat ce fereastra devine vizibilă
            scanner.startScanning()
            print("🔍 [SharkControl] Scanerul HID a fost inițializat.")
        }
    }
}

#Preview {
    ContentView()
}
