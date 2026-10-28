import Foundation
import SwiftUI
import Combine
import IOKit.hid

public final class DeviceViewModel: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var deviceName: String = "No device connected"
    @Published public var batteryLevel: Int = 0                 // (A) nu mai e 69
    @Published public var hasBatteryReading: Bool = false       // (A) true doar dacă am primit un heartbeat real
    @Published public var isCharging: Bool = false
    @Published public var isWiredConnection: Bool = false

    private let scanner = HIDDeviceScanner()
    private var lastHeartbeat: Date?                            // (A) momentul ultimului heartbeat
    private var watchdog: Timer?                                // (A) verifică periodic dacă mouse-ul tace

    public init() {
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
            // (C) handshake-ul și crearea DeviceTransport au fost șterse: bateria nu are nevoie de scrieri
        }

        scanner.onDeviceDisconnected = { [weak self] in
            guard let self = self else { return }
            self.isConnected = false
            self.deviceName = "No device connected"
            self.isWiredConnection = false
            self.isCharging = false
            self.hasBatteryReading = false
            self.lastHeartbeat = nil
        }

        scanner.startScanning()

        // (B) Watchdog: dacă n-a venit niciun heartbeat în 6 secunde, mouse-ul e adormit/offline
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self, let last = self.lastHeartbeat else { return }
            if Date().timeIntervalSince(last) > 6 { self.hasBatteryReading = false }
        }
    }

    // (D) Parserul de heartbeat: 03 55 40 <stare> <procent>
    private func processInputReport(data: Data, reportID: UInt32) {
        let raw = [UInt8](data)
        print("📥 input:", raw.map { String(format: "%02x", $0) }.joined(separator: " "))

        // Normalizează: dacă report ID (0x03) lipsește din buffer, îl adăugăm
        let b = (raw.first == 0x03) ? raw : [0x03] + raw
        guard b.count >= 5, b[1] == 0x55, b[2] == ProtocolConstants.evBattery else { return }

        let state = b[3]
        let level = min(Int(b[4]), 100)
        lastHeartbeat = Date()
        batteryLevel = level
        hasBatteryReading = true
        isCharging = (state == ProtocolConstants.chargingFlag) || isWiredConnection
    }
}
