import Foundation
import SwiftUI
import Combine
import IOKit.hid

public final class DeviceViewModel: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var deviceName: String = "No device connected"
    @Published public var batteryLevel: Int = 75
    @Published public var isWiredConnection: Bool = false

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
            
            // Read Product ID from IOKit to accurately separate Dongle (0xFA60) from Cable (0xFA55)
            if let pidValue = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int {
                // 0xFA55 is typically the wired mode PID for Attack Shark X11
                self.isWiredConnection = (pidValue == 0xFA55)
                print("🔍 Connected Device PID: 0x\(String(format: "%04X", pidValue)), Is Wired: \(self.isWiredConnection)")
            } else {
                // Fallback check on name if PID property is unavailable
                self.isWiredConnection = name.lowercased().contains("wired") || name.lowercased().contains("cable")
            }
            
            self.transport = DeviceTransport(hidDevice: device)
            self.requestDeviceSettings()
        }

        scanner.onDeviceDisconnected = { [weak self] in
            guard let self = self else { return }
            self.isConnected = false
            self.deviceName = "No device connected"
            self.isWiredConnection = false
            self.transport = nil
        }

        scanner.startScanning()
    }

    public func requestDeviceSettings() {
        guard let transport = transport else { return }
        if let batteryData = transport.getFeatureReport(reportID: 0x0B, length: 8) {
            print("🔋 Battery report data received: \(batteryData as NSData)")
        }
    }
}
