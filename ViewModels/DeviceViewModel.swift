import Foundation
import SwiftUI
import Combine
import IOKit.hid

public final class DeviceViewModel: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var deviceName: String = "No device connected"

    private let scanner = HIDDeviceScanner()
    private var transport: DeviceTransport?

    public init() {
        setupScanner()
    }

    private func setupScanner() {
        scanner.onDeviceConnected = { [weak self] name, device in
            guard let self = self else { return }
            self.isConnected = true
            self.deviceName = name
            self.transport = DeviceTransport(hidDevice: device)
            
            // Apelăm automat citirea setărilor când se conectează
            self.requestDeviceSettings()
        }

        scanner.onDeviceDisconnected = { [weak self] in
            guard let self = self else { return }
            self.isConnected = false
            self.deviceName = "No device connected"
            self.transport = nil
        }

        scanner.startScanning()
    }

    // Metoda este acum plasată corect IN INTERIORUL clasei
    public func requestDeviceSettings() {
        guard let transport = transport else { return }
        
        // Typical HID report ID for battery/status query on Attack Shark X11
        if let batteryData = transport.getFeatureReport(reportID: 0x0B, length: 8) {
            print("🔋 Battery report data received: \(batteryData as NSData)")
            // Parse battery percentage and charging status here based on report structure
        }
    }
}
