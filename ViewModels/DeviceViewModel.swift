import Foundation
import SwiftUI
import Combine
import IOKit.hid

/// One DPI stage as edited in the UI (what the user wants the mouse to hold).
public struct DPIStageEdit {
    public var dpi: Int
    public var isEnabled: Bool
    public var color: DPIColor

    public init(dpi: Int, isEnabled: Bool, color: DPIColor) {
        self.dpi = dpi
        self.isEnabled = isEnabled
        self.color = color
    }
}

/// State of the DPI <-> mouse synchronisation, shown in the DPI tab.
public enum DPISyncState: Equatable {
    case noMouse
    case searching
    case synced
    case writing
    case unverified
    case failed(String)

    public var label: String {
        switch self {
        case .noMouse: "No mouse connected"
        case .searching: "Connecting to the mouse…"
        case .synced: "Synced with mouse"
        case .writing: "Sending to mouse…"
        case .unverified: "Sent · mouse didn't confirm"
        case .failed(let message): message
        }
    }
}

public final class DeviceViewModel: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var deviceName: String = "No device connected"
    @Published public var batteryLevel: Int = 0                 // (A) nu mai e 69
    @Published public var hasBatteryReading: Bool = false       // (A) true doar dacă am primit un heartbeat real
    @Published public var isCharging: Bool = false
    @Published public var isWiredConnection: Bool = false

    // MARK: DPI sync

    @Published public private(set) var dpiSyncState: DPISyncState = .noMouse
    /// DPI configuration reported by the mouse itself: first read, DPI button pressed on the mouse, manual refresh.
    /// (Not published after our own writes: the UI already holds those values.)
    @Published public private(set) var mouseDPIConfiguration: DPIConfiguration?

    /// All blocking HID I/O happens here, one request at a time.
    private let hidQueue = DispatchQueue(label: "SharkControl.hid", qos: .userInitiated)
    /// Every HID endpoint that is attached right now (the mouse exposes several).
    private var endpoints: [ObjectIdentifier: IOHIDDevice] = [:]
    /// The endpoint that actually answers feature-report reads (found by probing).
    private var configTransport: DeviceTransport?
    /// Last DPI configuration known to be on the mouse. Used as the template for writes, so the bytes the
    /// UI doesn't know about (sensor codes, trailing bytes, angle snap, ripple control) are preserved.
    private var dpiBase: DPIConfiguration?
    private var probeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

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
            self.endpoints[ObjectIdentifier(device)] = device
            print("🔍 Connected Device PID: 0x\(String(format: "%04X", pid)), endpoints: \(self.endpointPIDs.count)")
            self.refreshConnectionState()

            // The mouse attaches several endpoints in a burst: wait a moment, then look for the one that
            // answers DPI reads. (Calling this again just restarts the wait.)
            self.scheduleProbe()
        }

        // Cablul poate fi scos în timp ce receiver-ul (2.4G) rămâne conectat: fără asta, starea
        // "wired / charging" rămânea blocată până la repornirea aplicației.
        scanner.onEndpointRemoved = { [weak self] device in
            guard let self = self else { return }
            self.endpointPIDs[ObjectIdentifier(device)] = nil
            self.endpoints[ObjectIdentifier(device)] = nil
            self.refreshConnectionState()

            if let transport = self.configTransport,
               ObjectIdentifier(transport.hidDevice) == ObjectIdentifier(device) {
                // The endpoint we were using is gone (e.g. cable unplugged): find another one.
                self.configTransport = nil
                self.dpiBase = nil
                if self.endpoints.isEmpty {
                    self.dpiSyncState = .noMouse
                } else {
                    self.scheduleProbe(after: 1.0)
                }
            }
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

            self.probeTask?.cancel()
            self.refreshTask?.cancel()
            self.endpoints.removeAll()
            self.configTransport = nil
            self.dpiBase = nil
            self.mouseDPIConfiguration = nil
            self.dpiSyncState = .noMouse
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

        // Normalizează: dacă report ID (0x03) lipsește din buffer, îl adăugăm
        let b = (raw.first == 0x03) ? raw : [0x03] + raw

        // The mouse tells us when its DPI button changed the stage: 03 <model> 10 ...
        // We don't guess the payload, we simply read the DPI report again. Checked on the real report ID
        // (not on b[2]) so ordinary movement reports can't trigger it.
        if reportID == 0x03, b.count >= 5, b[2] == ProtocolConstants.evDPI {
            print("🎯 DPI event:", raw.map { String(format: "%02x", $0) }.joined(separator: " "))
            scheduleDPIRefresh()
            return
        }

        print("📥 input:", raw.map { String(format: "%02x", $0) }.joined(separator: " "))
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

    // MARK: - DPI sync

    /// Runs blocking work on the HID queue and hands the result back to the caller's actor.
    private func onHIDQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        let queue = hidQueue
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// Endpoints worth trying first: the ones with a feature-report buffer big enough for the DPI report,
    /// then the cable before the 2.4G receiver.
    private func probeCandidates() -> [IOHIDDevice] {
        func featureSize(_ device: IOHIDDevice) -> Int {
            (IOHIDDeviceGetProperty(device, "MaxFeatureReportSize" as CFString) as? Int) ?? 0
        }
        func isWired(_ device: IOHIDDevice) -> Bool {
            endpointPIDs[ObjectIdentifier(device)] == ProtocolConstants.productWired
        }
        return endpoints.values.sorted { a, b in
            let fa = featureSize(a) >= 56, fb = featureSize(b) >= 56
            if fa != fb { return fa }
            let wa = isWired(a), wb = isWired(b)
            if wa != wb { return wa }
            return false
        }
    }

    private func scheduleProbe(after delay: Double = 0.5, attempt: Int = 0) {
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            await self?.probeConfigEndpoint(attempt: attempt)
        }
    }

    /// Finds the HID endpoint that answers DPI reads, then loads the mouse's current DPI setup.
    private func probeConfigEndpoint(attempt: Int) async {
        guard isConnected, !endpoints.isEmpty else { return }
        dpiSyncState = .searching

        let transports = probeCandidates().map { DeviceTransport(hidDevice: $0) }
        let found = await onHIDQueue { () -> (Int, DPIConfiguration)? in
            for (index, transport) in transports.enumerated() {
                if let configuration = transport.readDPIConfiguration() {
                    return (index, configuration)
                }
            }
            return nil
        }
        guard !Task.isCancelled, isConnected else { return }

        if let (index, configuration) = found {
            let transport = transports[index]
            print("✅ DPI endpoint found, stage \(configuration.activeStage) active")
            configTransport = transport
            dpiBase = configuration
            mouseDPIConfiguration = configuration
            dpiSyncState = .synced
        } else if attempt < 5 {
            // Wireless mice sleep after a while: keep trying, a mouse movement wakes it up.
            dpiSyncState = .failed("Mouse isn't answering — move it to wake it up")
            scheduleProbe(after: 3, attempt: attempt + 1)
        } else {
            dpiSyncState = .failed("Couldn't read the DPI settings — press ↻ to retry")
        }
    }

    /// Reads the DPI setup from the mouse again and publishes it (also used by the ↻ button).
    public func refreshDPI() {
        guard isConnected else { return }
        guard let transport = configTransport else {
            scheduleProbe(after: 0)
            return
        }
        guard dpiSyncState != .writing else { return }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let configuration = await self.onHIDQueue { transport.readDPIConfiguration() }
            guard !Task.isCancelled, self.configTransport === transport else { return }
            if let configuration {
                self.dpiBase = configuration
                self.mouseDPIConfiguration = configuration
                self.dpiSyncState = .synced
            } else {
                self.dpiSyncState = .failed("Mouse isn't answering — move it to wake it up")
            }
        }
    }

    /// Debounced re-read, triggered by the mouse's own "DPI changed" event.
    private func scheduleDPIRefresh() {
        guard configTransport != nil else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.refreshDPI()
        }
    }

    /// Sends the DPI setup chosen in the UI to the mouse, then reads it back to verify.
    /// `completion` runs on the main thread with the configuration now believed to be on the mouse
    /// (the read-back when available), or nil if nothing could be sent.
    public func writeDPI(stages edits: [DPIStageEdit], activeIndex: Int, completion: @escaping (DPIConfiguration?) -> Void) {
        guard let transport = configTransport, let base = dpiBase, edits.count == base.stages.count else {
            dpiSyncState = isConnected ? .failed("Not synced with the mouse yet — change not sent") : .noMouse
            completion(nil)
            return
        }

        // Start from what the mouse reported so everything the UI doesn't edit stays untouched.
        var configuration = base
        for (index, edit) in edits.enumerated() {
            configuration.stages[index].dpi = edit.dpi
            configuration.stages[index].isEnabled = edit.isEnabled
            configuration.stages[index].color = edit.color
        }
        configuration.activeStage = activeIndex + 1

        let report: [UInt8]
        do {
            report = try DPIProtocol.encode(configuration)
        } catch {
            dpiSyncState = .failed("Invalid DPI setup: \(error)")
            completion(nil)
            return
        }

        dpiSyncState = .writing
        refreshTask?.cancel()
        let intended = configuration

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.onHIDQueue { () -> (Bool, DPIConfiguration?) in
                guard transport.sendFeatureReport(reportID: ProtocolConstants.reportDPI, data: report) else {
                    return (false, nil)
                }
                usleep(150_000)   // give the mouse a moment to apply it before reading back
                return (true, transport.readDPIConfiguration())
            }

            guard self.configTransport === transport else {
                completion(nil)
                return
            }
            guard outcome.0 else {
                self.dpiSyncState = .failed("Couldn't send the settings to the mouse")
                completion(nil)
                return
            }
            if let readback = outcome.1 {
                self.dpiBase = readback
                self.dpiSyncState = Self.matches(readback, intended)
                    ? .synced
                    : .failed("The mouse reported different values than were sent")
                completion(readback)
            } else {
                self.dpiBase = intended
                self.dpiSyncState = .unverified
                completion(intended)
            }
        }
    }

    /// Compares what was sent with what the mouse reports. Disabled stages are ignored apart from their
    /// on/off flag, because the firmware may store them differently.
    private static func matches(_ a: DPIConfiguration, _ b: DPIConfiguration) -> Bool {
        guard a.activeStage == b.activeStage, a.stages.count == b.stages.count else { return false }
        return zip(a.stages, b.stages).allSatisfy { x, y in
            guard x.isEnabled == y.isEnabled else { return false }
            return !x.isEnabled || (x.dpi == y.dpi && x.color == y.color)
        }
    }
}
