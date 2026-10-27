import SwiftUI

struct InteractiveMouseTestView: View {
    @StateObject private var monitor = MouseInputMonitor()
    
    // Dimensiunea pătratului de testare (300x300 pixeli)
    private let boxSize: CGFloat = 300.0
    
    @State private var isInsideTestArea: Bool = false
    @State private var cursorPosition: CGPoint = .zero

    var body: some View {
        VStack(spacing: 20) {
            Text("Zona de Testare Mouse")
                .font(.title2)
                .bold()

            Text(isInsideTestArea ? "🟢 Test activ (Mouse în zonă)" : "🔴 Test oprit (Mouse în afara zonei)")
                .font(.headline)
                .foregroundColor(isInsideTestArea ? .green : .red)

            // Suprafața pătratului de testare
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isInsideTestArea ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isInsideTestArea ? Color.blue : Color.gray, lineWidth: 2)
                    )

                VStack(spacing: 12) {
                    if isInsideTestArea {
                        Text("Ultimele acțiuni:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("LMB: \(monitor.activeButtons.contains(.left) ? "APĂSAT" : "-")")
                        Text("RMB: \(monitor.activeButtons.contains(.right) ? "APĂSAT" : "-")")
                        Text("Eveniment: \(monitor.lastEventType)")
                            .font(.footnote)
                    } else {
                        Text("Mută cursorul AICI pentru a activa testul")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }
            .frame(width: boxSize, height: boxSize)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    self.cursorPosition = location
                    if !isInsideTestArea {
                        self.isInsideTestArea = true
                        monitor.startMonitoring()
                    }
                case .ended:
                    if isInsideTestArea {
                        self.isInsideTestArea = false
                        monitor.stopMonitoring()
                    }
                }
            }
        }
        .padding()
    }
}
