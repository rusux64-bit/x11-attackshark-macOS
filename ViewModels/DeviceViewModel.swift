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

    /// Product ID of every HID endpoint that is attached right now (the mouse exposes several).
    /// This tells "cable plugged in" apart from "cable unplugged, but the 2.4G receiver is still there".
    private var endpointPIDs: [ObjectIdentifier: Int] = [:]
    /// Charging flag exactly as the mouse reported it in its last heartbeat.
    private var reportedCharging = false
    /// Last (state, level) that was logged, so the console only shows real changes.
    private var lastLogged: (state: UInt8, level: Int)?

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

            let pid: Int
            if let pidValue = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int {
                pid = pidValue
            } else {
                let lower = name.lowercased()
                pid = (lower.contains("wired") || lower.contains("cable"))
                    ? ProtocolConstants.productWired
                    : ProtocolConstants.productReceiver
            }
            self.endpointPIDs[ObjectIdentifier(device)] = pid
            print("🔍 Connected Device PID: 0x\(String(format: "%04X", pid)), endpoints: \(self.endpointPIDs.count)")
            self.refreshConnectionState()
            // (C) handshake-ul și crearea DeviceTransport au fost șterse: bateria nu are nevoie de scrieri
        }

        // Cablul poate fi scos în timp ce receiver-ul (2.4G) rămâne conectat: fără asta, starea
        // "wired / charging" rămânea blocată până la repornirea aplicației.
        scanner.onEndpointRemoved = { [weak self] device in
            guard let self = self else { return }
            self.endpointPIDs[ObjectIdentifier(device)] = nil
            self.refreshConnectionState()
        }

        scanner.onDeviceDisconnected = { [weak self] in
            guard let self = self else { return }
            self.isConnected = false
            self.deviceName = "No device connected"
            self.endpointPIDs.removeAll()
            self.reportedCharging = false
            self.lastLogged = nil
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

    /// Recomputes "wired" and "charging" from what is attached now + what the mouse last reported.
    private func refreshConnectionState() {
        let wired = endpointPIDs.values.contains(ProtocolConstants.productWired)
        if wired != isWiredConnection { isWiredConnection = wired }
        let charging = reportedCharging || wired
        if charging != isCharging { isCharging = charging }
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
        reportedCharging = (state == ProtocolConstants.chargingFlag)
        refreshConnectionState()

        if lastLogged?.state != state || lastLogged?.level != level {
            lastLogged = (state, level)
            print("🔋 battery \(level)% state=0x\(String(format: "%02X", state)) wired=\(isWiredConnection) charging=\(isCharging)")
        }
    }
}
