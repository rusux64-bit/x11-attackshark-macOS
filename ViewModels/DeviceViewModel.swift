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
    case reading
    case synced
    case writing
    case unverified
    case failed(String)

    public var label: String {
        switch self {
        case .noMouse: "No mouse connected"
        case .searching: "Connecting to the mouse…"
        case .reading: "Reading from mouse…"
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

    // MARK: Performance sync (polling rate, debounce, angle snapping, ripple control)

    @Published public private(set) var performanceSyncState: DPISyncState = .noMouse
    /// Performance settings reported by the mouse: first read and manual refresh.
    /// (Not published after our own writes: the UI already holds those values.)
    @Published public private(set) var mousePerformance: PerformanceSettings?
    private var performanceTask: Task<Void, Never>?

    // MARK: Lighting & power sync (report 0x05: light mode, brightness, speed, colour, sleep timer)

    @Published public private(set) var lightingSyncState: DPISyncState = .noMouse
    /// Lighting / sleep settings reported by the mouse: first read and manual refresh.
    /// (Not published after our own writes: the UI already holds those values.)
    @Published public private(set) var mouseLighting: LightingSettings?
    private var lightingTask: Task<Void, Never>?

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
            self.resetBatterySmoothing()

            self.probeTask?.cancel()
            self.refreshTask?.cancel()
            self.performanceTask?.cancel()
            self.lightingTask?.cancel()
            self.mouseLighting = nil
            self.lightingSyncState = .noMouse
            self.endpoints.removeAll()
            self.configTransport = nil
            self.dpiBase = nil
            self.mouseDPIConfiguration = nil
            self.mousePerformance = nil
            self.performanceSyncState = .noMouse
            self.buttonsTask?.cancel()
            self.buttonsReport = nil
            self.buttonsSyncState = .noMouse
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

        guard b.count >= 5, b[1] == 0x55, b[2] == ProtocolConstants.evBattery else { return }

        let state = b[3]
        let level = min(Int(b[4]), 100)
        lastHeartbeat = Date()
        reportedCharging = (state == ProtocolConstants.chargingFlag)
        refreshConnectionState()
        // The mouse's percentage is a noisy voltage estimate: show a steady value instead of the raw one.
        batteryLevel = smoothedBattery(raw: level, charging: isCharging)
        hasBatteryReading = true

        if lastLogged?.state != state || lastLogged?.level != level {
            lastLogged = (state, level)
            print("🔋 battery raw \(level)% shown \(batteryLevel)% state=0x\(String(format: "%02X", state)) wired=\(isWiredConnection) charging=\(isCharging)")
        }
    }

    // MARK: - Battery smoothing

    private var batteryWindow: [Int] = []
    private var shownLevel: Int?
    private var lastLevelStep = Date.distantPast
    private var lastBatterySample = Date.distantPast
    private var lastBatteryCharging: Bool?
    private var wrongDirectionCount = 0
    /// The shown value moves by at most 1% per this many seconds.
    private static let batteryStepInterval: TimeInterval = 15

    private func resetBatterySmoothing() {
        batteryWindow.removeAll()
        shownLevel = nil
        lastBatteryCharging = nil
        wrongDirectionCount = 0
        lastLevelStep = .distantPast
    }

    /// Median of the last readings, then:
    /// - on cable the reported % (about 100%) is ignored and the last level read on battery stays shown;
    /// - on battery the shown value never goes up;
    /// - it moves toward the target by 1% at a time, at most every 15 s, so it can't jump 70 -> 77.
    /// A long silence (10 min) or a disconnect starts again from the raw value.
    private func smoothedBattery(raw: Int, charging: Bool) -> Int {
        let now = Date()
        if now.timeIntervalSince(lastBatterySample) > 600 { resetBatterySmoothing() }
        lastBatterySample = now

        if lastBatteryCharging != charging {
            // Plugging / unplugging changes the voltage: don't mix readings from before and after.
            batteryWindow.removeAll()
            wrongDirectionCount = 0
            // Just unplugged: the reading is the real battery again, so start from it (no slow climb down from 100%).
            if lastBatteryCharging == true && !charging { shownLevel = nil }
            lastBatteryCharging = charging
        }
        if charging {
            // Over the cable the mouse reports ~100% whatever its real charge is, so that reading is not shown:
            // keep the last level read on battery (the charging icon tells the rest).
            if let shown = shownLevel { return shown }
            shownLevel = raw   // the app started while plugged in: nothing better to show
            return raw
        }
        batteryWindow.append(raw)
        if batteryWindow.count > 7 { batteryWindow.removeFirst() }
        let median = batteryWindow.sorted()[batteryWindow.count / 2]

        guard let shown = shownLevel else {
            shownLevel = raw
            lastLevelStep = now
            return raw
        }

        var target = median
        if target > shown {
            wrongDirectionCount += 1
            // Only accept a big, lasting disagreement (e.g. the mouse was charged while the app wasn't watching).
            if !(wrongDirectionCount >= 20 && abs(target - shown) >= 5) { target = shown }
        } else {
            wrongDirectionCount = 0
        }

        guard target != shown, now.timeIntervalSince(lastLevelStep) >= Self.batteryStepInterval else { return shown }
        lastLevelStep = now
        let next = shown + (target > shown ? 1 : -1)
        shownLevel = next
        return next
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
        probeTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            await self?.probeConfigEndpoint(attempt: attempt)
        }
    }

    /// Finds the HID endpoint that answers DPI reads, then loads the mouse's current DPI setup.
    @MainActor
    private func probeConfigEndpoint(attempt: Int) async {
        guard isConnected, !endpoints.isEmpty else { return }
        dpiSyncState = .searching
        performanceSyncState = .searching
        buttonsSyncState = .searching
        lightingSyncState = .searching

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
            refreshPerformance()
            refreshButtons()
            refreshLighting()
        } else if attempt < 5 {
            // Wireless mice sleep after a while: keep trying, a mouse movement wakes it up.
            dpiSyncState = .failed("Mouse isn't answering — move it to wake it up")
            performanceSyncState = dpiSyncState
            buttonsSyncState = dpiSyncState
            lightingSyncState = dpiSyncState
            scheduleProbe(after: 3, attempt: attempt + 1)
        } else {
            dpiSyncState = .failed("Couldn't read the DPI settings — press ↻ to retry")
            performanceSyncState = .failed("Couldn't read the settings — press ↻ to retry")
            buttonsSyncState = .failed("Couldn't read the settings — press ↻ to retry")
            lightingSyncState = .failed("Couldn't read the settings — press ↻ to retry")
        }
    }

    /// Reads the DPI setup from the mouse again and publishes it.
    /// `userInitiated` is the ↻ button: it shows "Reading from mouse…" and retries once if the mouse is slow.
    /// `completion` receives what was read from the mouse, or nil if nothing could be read.
    public func refreshDPI(userInitiated: Bool = false, completion: ((DPIConfiguration?) -> Void)? = nil) {
        guard isConnected else {
            completion?(nil)
            return
        }
        guard let transport = configTransport else {
            // No endpoint found yet: search again (a successful probe also loads the DPI setup).
            scheduleProbe(after: 0)
            completion?(nil)
            return
        }
        guard dpiSyncState != .writing else {
            completion?(nil)
            return
        }

        refreshTask?.cancel()
        if userInitiated { dpiSyncState = .reading }

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let started = Date()
            let configuration = await self.onHIDQueue { () -> DPIConfiguration? in
                if let first = transport.readDPIConfiguration() { return first }
                guard userInitiated else { return nil }
                usleep(150_000)   // a sleeping wireless mouse often answers the second try
                return transport.readDPIConfiguration()
            }
            if userInitiated {
                // Keep the "reading" feedback visible long enough to be noticed.
                let elapsed = Date().timeIntervalSince(started)
                if elapsed < 0.45 { try? await Task.sleep(for: .seconds(0.45 - elapsed)) }
            }
            guard !Task.isCancelled, self.configTransport === transport else {
                completion?(nil)
                return
            }
            if let configuration {
                self.dpiBase = configuration
                self.mouseDPIConfiguration = configuration
                self.dpiSyncState = .synced
            } else {
                self.dpiSyncState = .failed("Mouse isn't answering — move it to wake it up")
            }
            completion?(configuration)
        }
    }

    // MARK: - Performance sync

    /// Reads polling rate, debounce and angle snapping / ripple control from the mouse and publishes them.
    /// `userInitiated` is the ↻ button: it shows "Reading from mouse…" and retries once if the mouse is slow.
    /// `completion` receives what was read, or nil if nothing could be read.
    public func refreshPerformance(userInitiated: Bool = false, completion: ((PerformanceSettings?) -> Void)? = nil) {
        guard isConnected, let transport = configTransport else {
            completion?(nil)
            return
        }
        guard performanceSyncState != .writing else {
            completion?(nil)
            return
        }

        performanceTask?.cancel()
        if userInitiated {
            performanceSyncState = .reading
        } else if mousePerformance == nil {
            performanceSyncState = .searching
        }

        performanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let started = Date()
            let snapshot = await self.onHIDQueue { () -> PerformanceSnapshot? in
                if let first = transport.readPerformanceSnapshot() { return first }
                guard userInitiated else { return nil }
                usleep(150_000)
                return transport.readPerformanceSnapshot()
            }
            if userInitiated {
                let elapsed = Date().timeIntervalSince(started)
                if elapsed < 0.45 { try? await Task.sleep(for: .seconds(0.45 - elapsed)) }
            }
            guard !Task.isCancelled, self.configTransport === transport else {
                completion?(nil)
                return
            }
            if let snapshot {
                // angle snapping / ripple control live in the DPI report: keep the write template current.
                if self.dpiSyncState != .writing { self.dpiBase = snapshot.dpi }
                self.mousePerformance = snapshot.settings
                self.performanceSyncState = .synced
                completion?(snapshot.settings)
            } else {
                self.performanceSyncState = .failed("Mouse isn't answering — move it to wake it up")
                completion?(nil)
            }
        }
    }

    /// Sends the Performance settings chosen in the UI to the mouse, then reads them back to verify.
    /// `completion` runs on the main thread with the settings now believed to be on the mouse
    /// (the read-back when available), or nil if nothing could be sent.
    public func writePerformance(_ target: PerformanceSettings, completion: @escaping (PerformanceSettings?) -> Void) {
        guard let transport = configTransport else {
            performanceSyncState = isConnected ? .failed("Not synced with the mouse yet — change not sent") : .noMouse
            completion(nil)
            return
        }

        performanceSyncState = .writing
        performanceTask?.cancel()
        performanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.onHIDQueue { transport.writePerformance(target) }

            guard self.configTransport === transport else {
                completion(nil)
                return
            }
            switch result {
            case .failed(let message):
                self.performanceSyncState = .failed(message)
                completion(nil)
            case .written(let snapshot):
                if let snapshot {
                    self.dpiBase = snapshot.dpi
                    self.performanceSyncState = snapshot.settings == target
                        ? .synced
                        : .failed("The mouse reported different values than were sent")
                    completion(snapshot.settings)
                } else {
                    self.performanceSyncState = .unverified
                    completion(target)
                }
            }
        }
    }

    // MARK: - Lighting & power sync

    /// Reads the lighting / sleep settings from the mouse and publishes them.
    /// `userInitiated` is the ↻ button: it shows "Reading from mouse…" and retries once if the mouse is slow.
    /// `completion` receives what was read, or nil if nothing could be read.
    public func refreshLighting(userInitiated: Bool = false, completion: ((LightingSettings?) -> Void)? = nil) {
        guard isConnected, let transport = configTransport else {
            completion?(nil)
            return
        }
        guard lightingSyncState != .writing else {
            completion?(nil)
            return
        }

        lightingTask?.cancel()
        if userInitiated {
            lightingSyncState = .reading
        } else if mouseLighting == nil {
            lightingSyncState = .searching
        }

        lightingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let started = Date()
            let settings = await self.onHIDQueue { () -> LightingSettings? in
                if let first = transport.readLightingSettings() { return first }
                guard userInitiated else { return nil }
                usleep(150_000)
                return transport.readLightingSettings()
            }
            if userInitiated {
                let elapsed = Date().timeIntervalSince(started)
                if elapsed < 0.45 { try? await Task.sleep(for: .seconds(0.45 - elapsed)) }
            }
            guard !Task.isCancelled, self.configTransport === transport else {
                completion?(nil)
                return
            }
            if let settings {
                self.mouseLighting = settings
                self.lightingSyncState = .synced
            } else {
                self.lightingSyncState = .failed("Mouse isn't answering — move it to wake it up")
            }
            completion?(settings)
        }
    }

    /// Sends the Lighting / Power settings chosen in the UI to the mouse, then reads them back to verify.
    /// `completion` runs on the main thread with the settings now believed to be on the mouse
    /// (the read-back when available), or nil if nothing could be sent.
    public func writeLighting(_ target: LightingSettings, completion: @escaping (LightingSettings?) -> Void) {
        guard let transport = configTransport else {
            lightingSyncState = isConnected ? .failed("Not synced with the mouse yet — change not sent") : .noMouse
            completion(nil)
            return
        }

        lightingSyncState = .writing
        lightingTask?.cancel()
        lightingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let mainID = ObjectIdentifier(transport.hidDevice)
            let alternates = self.endpoints.values
                .filter { ObjectIdentifier($0) != mainID }
                .map { DeviceTransport(hidDevice: $0) }
            let result = await self.onHIDQueue { transport.writeLighting(target, alternates: alternates) }

            guard self.configTransport === transport else {
                completion(nil)
                return
            }
            switch result {
            case .failed(let message):
                self.lightingSyncState = .failed(message)
                completion(nil)
            case .written(let readback):
                if let readback {
                    self.lightingSyncState = readback == target
                        ? .synced
                        : .failed("The mouse reported different values than were sent")
                    completion(readback)
                } else {
                    self.lightingSyncState = .unverified
                    completion(target)
                }
            }
        }
    }

    // MARK: - Buttons report (report 0x08)

    /// Last Buttons report read from the mouse.
    @Published public private(set) var buttonsReport: ButtonsReport?
    /// State of the Buttons <-> mouse synchronisation, shown in the Buttons tab.
    @Published public private(set) var buttonsSyncState: DPISyncState = .noMouse
    private var buttonsTask: Task<Void, Never>?
    /// First Buttons report read in this session. "Restore" writes exactly this back.
    private var buttonsOriginal: ButtonsReport?

    /// Reads the Buttons report (0x08) from the mouse. Read only: nothing is written.
    public func readButtonsReport(completion: @escaping (ButtonsReport?) -> Void) {
        guard isConnected, let transport = configTransport else {
            completion(nil)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let report = await self.onHIDQueue { () -> ButtonsReport? in
                if let first = transport.readButtonsReport() { return first }
                usleep(150_000)   // a sleeping wireless mouse often answers the second try
                return transport.readButtonsReport()
            }
            if let report {
                if self.buttonsOriginal == nil { self.buttonsOriginal = report }
                self.buttonsReport = report
                print("🧩 Buttons report 0x08:\n\(report.hexDump)")
            }
            completion(report)
        }
    }

    /// Reads the Buttons report and publishes it. `userInitiated` is the ↻ button: it shows "Reading from mouse…"
    /// and retries once if the mouse is slow. `completion` receives what was read, or nil.
    public func refreshButtons(userInitiated: Bool = false, completion: ((ButtonsReport?) -> Void)? = nil) {
        guard isConnected, let transport = configTransport else {
            completion?(nil)
            return
        }
        guard buttonsSyncState != .writing else {
            completion?(nil)
            return
        }

        buttonsTask?.cancel()
        if userInitiated {
            buttonsSyncState = .reading
        } else if buttonsReport == nil {
            buttonsSyncState = .searching
        }

        buttonsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let started = Date()
            let report = await self.onHIDQueue { () -> ButtonsReport? in
                if let first = transport.readButtonsReport() { return first }
                guard userInitiated else { return nil }
                usleep(150_000)
                return transport.readButtonsReport()
            }
            if userInitiated {
                let elapsed = Date().timeIntervalSince(started)
                if elapsed < 0.45 { try? await Task.sleep(for: .seconds(0.45 - elapsed)) }
            }
            guard !Task.isCancelled, self.configTransport === transport else {
                completion?(nil)
                return
            }
            if let report {
                if self.buttonsOriginal == nil { self.buttonsOriginal = report }
                self.buttonsReport = report
                self.buttonsSyncState = .synced
            } else {
                self.buttonsSyncState = .failed("Mouse isn't answering — move it to wake it up")
            }
            completion?(report)
        }
    }

    /// Sends new codes for some entries of the Buttons report (entry index -> code), then reads it back to verify.
    /// `completion` gets (the read-back or nil, whether the report was actually sent).
    public func writeButtons(_ codes: [Int: UInt8], completion: @escaping (ButtonsReport?, Bool) -> Void) {
        guard let transport = configTransport else {
            buttonsSyncState = isConnected ? .failed("Not synced with the mouse yet — change not sent") : .noMouse
            completion(nil, false)
            return
        }

        buttonsSyncState = .writing
        buttonsTask?.cancel()
        buttonsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.onHIDQueue { transport.writeButtonCodes(codes) }

            guard self.configTransport === transport else {
                completion(nil, false)
                return
            }
            switch result {
            case .failed(let message):
                self.buttonsSyncState = .failed(message)
                completion(nil, false)
            case .written(let readback):
                if let readback {
                    self.buttonsReport = readback
                    let confirmed = codes.allSatisfy { readback.codes[$0.key] == $0.value }
                    self.buttonsSyncState = confirmed
                        ? .synced
                        : .failed("The mouse reported different values than were sent")
                    completion(readback, true)
                } else {
                    self.buttonsSyncState = .unverified
                    completion(nil, true)
                }
            }
        }
    }

    /// Changes the code of ONE entry of the Buttons report, then reads the report back.
    /// `completion` gets the read-back, or an error message.
    public func writeButtonsEntry(_ index: Int, code: UInt8, completion: @escaping (ButtonsReport?, String?) -> Void) {
        guard isConnected, let transport = configTransport else {
            completion(nil, "No mouse connected")
            return
        }
        runButtonsWrite(completion) { transport.writeButtonsEntry(index, code: code) }
    }

    /// Puts back the factory button layout (the report first observed on a real X11).
    public func restoreButtonsReport(completion: @escaping (ButtonsReport?, String?) -> Void) {
        guard isConnected, let transport = configTransport else {
            completion(nil, "No mouse connected")
            return
        }
        guard let original = (try? ButtonsReport(decoding: ButtonsReport.observedDefaultBytes)) ?? buttonsOriginal else {
            completion(nil, "Nothing to restore")
            return
        }
        runButtonsWrite(completion) { transport.writeButtonsReport(original) }
    }

    private func runButtonsWrite(_ completion: @escaping (ButtonsReport?, String?) -> Void,
                                 _ work: @escaping @Sendable () -> ButtonsWriteResult) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.onHIDQueue(work)
            switch result {
            case .failed(let message):
                completion(nil, message)
            case .written(let readback):
                if let readback {
                    self.buttonsReport = readback
                    completion(readback, nil)
                } else {
                    completion(nil, "Sent, but the mouse didn't confirm it")
                }
            }
        }
    }

    /// Debounced re-read, triggered by the mouse's own "DPI changed" event.
    private func scheduleDPIRefresh() {
        guard configTransport != nil else { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
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

        Task { @MainActor [weak self] in
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
