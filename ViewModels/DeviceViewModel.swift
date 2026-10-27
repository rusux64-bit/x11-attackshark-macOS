import Foundation
import SwiftUI
import Combine
import IOKit.hid

public final class DeviceViewModel: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var deviceName: String = "No device connected"
    @Published public var batteryLevel: Int = 65
    @Published public var isCharging: Bool = false
    @Published public var isWiredConnection: Bool = false

    private let scanner = HIDDeviceScanner()
    private var transport: DeviceTransport?

    public init() {
        let savedLevel = UserDefaults.standard.integer(forKey: "AttackShark_LastBatteryLevel")
        if savedLevel > 0 && savedLevel <= 100 {
            self.batteryLevel = savedLevel
        }
        setupScanner()
    }

    private func setupScanner() {
        scanner.onInputReport = { [weak self] data, reportID, _ in
            self?.processInputReport(data: data, reportID: reportID)
        }

        scanner.onDeviceConnected = { [weak self] name, device in
            guard let self = self else { return }
            self.isConnected = true
            self.deviceName = name
            
            // Check PID to distinguish Wired Cable (0xFA55) from 2.4G Receiver (0xFA60)
            if let pidValue = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int {
                self.isWiredConnection = (pidValue == 0xFA55)
                if self.isWiredConnection {
                    self.isCharging = true
                }
                print("🔍 Connected Device PID: 0x\(String(format: "%04X", pidValue)), Is Wired: \(self.isWiredConnection)")
            } else {
                self.isWiredConnection = name.lowercased().contains("wired") || name.lowercased().contains("cable")
                if self.isWiredConnection {
                    self.isCharging = true
                }
            }
            
            let maxFeature = (IOHIDDeviceGetProperty(device, "MaxFeatureReportSize" as CFString) as? Int) ?? 0
            if self.transport == nil || maxFeature >= 64 {
                self.transport = DeviceTransport(hidDevice: device)
                self.sendHandshake()
            }
        }

        scanner.onDeviceDisconnected = { [weak self] in
            guard let self = self else { return }
            self.isConnected = false
            self.deviceName = "No device connected"
            self.isWiredConnection = false
            self.isCharging = false
            self.transport = nil
        }

        scanner.startScanning()
    }

    public func sendHandshake() {
        guard let transport = transport else { return }
        var handshake = [UInt8](repeating: 0, count: 24)
        handshake[0] = 0x09
        handshake[1] = 0x01
        _ = transport.sendFeatureReport(reportID: 0x09, data: handshake)
    }

    private func processInputReport(data: Data, reportID: UInt32) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return }

        var payload = bytes
        if payload.first == 0x03 {
            payload.removeFirst()
        }

        // Search for battery event (0x40) preceded by device model identifier (0x55 or 0x02)
        // Expected payload format: [0x55, 0x40, <statusFlag>, <batteryLevel>]
        if let idx = payload.firstIndex(of: ProtocolConstants.evBattery), idx > 0, payload.count > idx + 2 {
            let model = payload[idx - 1]
            if model == 0x55 || model == 0x02 {
                let statusFlag = payload[idx + 1]
                let level = Int(payload[idx + 2])
                
                if level > 0 && level <= 100 {
                    DispatchQueue.main.async {
                        self.batteryLevel = level
                        self.isCharging = (statusFlag == ProtocolConstants.chargingFlag) || self.isWiredConnection
                        UserDefaults.standard.set(level, forKey: "AttackShark_LastBatteryLevel")
                        print("🔋 Real Attack Shark battery updated: \(level)%, Charging: \(self.isCharging)")
                    }
                }
            }
        }
    }
}
