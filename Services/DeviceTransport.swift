import Foundation
import IOKit.hid

/// Outcome of writing the Performance settings.
public nonisolated enum PerformanceWriteResult: Sendable {
    case failed(String)
    /// Everything that had to be sent was sent. The snapshot is the read-back (nil if the mouse didn't answer it).
    case written(PerformanceSnapshot?)
}

/// Outcome of writing the Buttons report.
public nonisolated enum ButtonsWriteResult: Sendable {
    case failed(String)
    /// The report was sent. The value is the read-back (nil if the mouse didn't answer it).
    case written(ButtonsReport?)
}

/// Outcome of writing the Lighting / Power settings (report 0x05).
public nonisolated enum LightingWriteResult: Sendable {
    case failed(String)
    /// Nothing needed sending, or the report was sent. The value is the read-back (nil if the mouse didn't answer it).
    case written(LightingSettings?)
}

/// Talks to ONE HID endpoint of the mouse.
///
/// Everything here is synchronous and can block for a few hundred milliseconds (the mouse answers a read
/// request asynchronously), so call it from a background queue, never from the main thread.
/// `nonisolated` because the app target defaults to @MainActor.
public nonisolated final class DeviceTransport: @unchecked Sendable {
    public let hidDevice: IOHIDDevice
    /// IOReturn code of the last refused write (nil after a successful one). Shown in the UI to help diagnose.
    public private(set) var lastFailure: String?

    public init(hidDevice: IOHIDDevice) {
        self.hidDevice = hidDevice
    }

    /// Sends a feature report. `data` is the complete report INCLUDING the report ID as its first byte.
    @discardableResult
    public func sendFeatureReport(reportID: UInt8, data: [UInt8], logFailure: Bool = true) -> Bool {
        func attempt(_ bytes: [UInt8], type: IOHIDReportType = kIOHIDReportTypeFeature) -> IOReturn {
            bytes.withUnsafeBufferPointer { buffer -> IOReturn in
                guard let base = buffer.baseAddress else { return kIOReturnError }
                return IOHIDDeviceSetReport(hidDevice, type, CFIndex(reportID), base, buffer.count)
            }
        }

        var result = attempt(data)

        // Config writes (not the 0xA0 read request) are retried: right after a read request the mouse can still be
        // busy and rejects the write, which over the cable shows up as a USB error (0xe0005000).
        if result != kIOReturnSuccess, reportID != ProtocolConstants.reportReadReq {
            for delay in [UInt32(80_000), UInt32(200_000)] {
                usleep(delay)
                result = attempt(data)
                if result == kIOReturnSuccess { break }
            }
            // Some USB HID stacks want the payload without the leading report ID byte.
            if result != kIOReturnSuccess, data.first == reportID {
                result = attempt(Array(data.dropFirst()))
                if result == kIOReturnSuccess { print("ℹ️ Report 0x\(String(format: "%02X", reportID)) accepted without the report ID byte") }
            }
            // Last resort: send it as an output report instead of a feature report.
            if result != kIOReturnSuccess {
                result = attempt(data, type: kIOHIDReportTypeOutput)
                if result == kIOReturnSuccess { print("ℹ️ Report 0x\(String(format: "%02X", reportID)) accepted as an OUTPUT report") }
            }
        }

        if result != kIOReturnSuccess {
            lastFailure = String(format: "0x%08X", UInt32(bitPattern: result))
            if logFailure {
                let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("❌ Failed to send feature report ID 0x\(String(format: "%02X", reportID)): 0x\(String(UInt32(bitPattern: result), radix: 16))  payload: \(hex)")
            }
            return false
        }
        lastFailure = nil
        return true
    }

    /// Reads a feature report (report ID is the first byte of the returned data).
    public func getFeatureReport(reportID: UInt8, length: Int, logFailure: Bool = true) -> Data? {
        var buffer = [UInt8](repeating: 0, count: length)
        var reportLength = CFIndex(length)

        let result = buffer.withUnsafeMutableBufferPointer { pointer -> IOReturn in
            guard let base = pointer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceGetReport(
                hidDevice,
                kIOHIDReportTypeFeature,
                CFIndex(reportID),
                base,
                &reportLength
            )
        }

        if result != kIOReturnSuccess {
            if logFailure {
                print("⚠️ Failed to get feature report ID 0x\(String(format: "%02X", reportID)): 0x\(String(UInt32(bitPattern: result), radix: 16))")
            }
            return nil
        }

        return Data(buffer.prefix(max(0, min(reportLength, length))))
    }

    /// Asks the mouse for a report: sends the 0xA0 read request, then fetches the report it prepared.
    /// Returns the raw bytes (report ID first) or nil if the mouse didn't answer (asleep, wrong endpoint...).
    public func readReport(reportID: UInt8, attempts: Int = 3) -> [UInt8]? {
        guard let expected = ProtocolConstants.reportSizes[reportID] else { return nil }
        let request = [UInt8](ProtocolHelper.makeReadRequest(reportID: reportID))

        for attempt in 0..<attempts {
            let isLast = attempt == attempts - 1
            guard sendFeatureReport(reportID: ProtocolConstants.reportReadReq, data: request, logFailure: isLast) else {
                usleep(80_000)
                continue
            }
            // The mouse (or the 2.4G receiver) needs a moment to prepare its answer; wait longer on each retry.
            usleep(UInt32(60_000 + attempt * 80_000))

            guard let data = getFeatureReport(reportID: reportID, length: expected, logFailure: isLast) else { continue }
            var bytes = [UInt8](data)
            // Some HID stacks strip the report ID from numbered feature reports; put it back.
            if bytes.count == expected - 1 { bytes.insert(reportID, at: 0) }
            if bytes.count == expected, bytes[0] == reportID { return bytes }
        }
        return nil
    }

    /// Reads and decodes the DPI report (0x04). Nil when the mouse doesn't answer or the answer is invalid.
    public func readDPIConfiguration() -> DPIConfiguration? {
        guard let report = readReport(reportID: ProtocolConstants.reportDPI) else { return nil }
        do {
            return try DPIProtocol.decode(report)
        } catch {
            print("⚠️ DPI report did not decode: \(error)")
            return nil
        }
    }

    /// Reads and decodes the polling report (0x06).
    public func readPollingRate() -> PollingRate? {
        guard let report = readReport(reportID: ProtocolConstants.reportPolling) else { return nil }
        do {
            return try PollingProtocol.decode(report)
        } catch {
            print("⚠️ Polling report did not decode: \(error)")
            return nil
        }
    }

    /// Reads and decodes the lighting/power report (0x05), which also carries the debounce time.
    public func readSystemSettings() -> SystemSettingsReport? {
        guard let report = readReport(reportID: ProtocolConstants.reportLight) else { return nil }
        do {
            return try SystemSettingsReport(decoding: report)
        } catch {
            print("⚠️ System report did not decode: \(error)")
            return nil
        }
    }

    /// Reads the lighting / sleep settings (report 0x05). Nil when the mouse doesn't answer or the answer is invalid.
    public func readLightingSettings() -> LightingSettings? {
        readSystemSettings()?.lighting
    }

    /// Writes the Lighting / Power settings. Read-modify-write against a fresh read of report 0x05, so the debounce
    /// time, the deep-sleep timer and every byte the app doesn't edit stay exactly as the mouse holds them.
    public func writeLighting(_ target: LightingSettings, alternates: [DeviceTransport] = []) -> LightingWriteResult {
        guard let current = readSystemSettings() else {
            return .failed("Mouse isn't answering — move it to wake it up")
        }
        if current.lighting == target { return .written(current.lighting) }

        guard let report = try? current.applying(target) else {
            return .failed("Unsupported lighting setting")
        }
        usleep(60_000)   // let the mouse finish answering the read before it gets the write
        let sentOnMain = sendFeatureReport(reportID: ProtocolConstants.reportLight, data: report, logFailure: alternates.isEmpty)
        // The mouse exposes several HID endpoints: if the one that answers reads refuses the write, try the others.
        let sent = sentOnMain || alternates.contains { other in
            let ok = other.sendFeatureReport(reportID: ProtocolConstants.reportLight, data: report, logFailure: false)
            if ok { print("ℹ️ Lighting report accepted by another HID endpoint") }
            return ok
        }
        if !sent && !alternates.isEmpty {
            print("❌ Lighting report refused by every HID endpoint: \(report.map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
        guard sent else {
            return .failed("Mouse refused the lighting report (USB error \(lastFailure ?? "unknown"))")
        }
        usleep(150_000)   // give the mouse time to apply it before reading back
        for _ in 0..<2 {
            if let readback = readSystemSettings() { return .written(readback.lighting) }
            usleep(150_000)
        }
        return .written(nil)
    }

    /// Reads and decodes the Buttons report (0x08). Nil when the mouse doesn't answer or the answer is invalid.
    public func readButtonsReport() -> ButtonsReport? {
        guard let report = readReport(reportID: ProtocolConstants.reportButtons) else { return nil }
        do {
            return try ButtonsReport(decoding: report)
        } catch {
            let raw = report.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("⚠️ Buttons report did not decode: \(error)\n    raw: \(raw)")
            return nil
        }
    }

    /// Changes the code byte of ONE entry. Read-modify-write against a fresh read, so every other byte stays
    /// exactly as the mouse holds it.
    public func writeButtonsEntry(_ index: Int, code: UInt8) -> ButtonsWriteResult {
        guard let current = readButtonsReport() else {
            return .failed("Mouse isn't answering — move it to wake it up")
        }
        guard let report = try? current.settingCode(code, forEntry: index) else {
            return .failed("Invalid button entry")
        }
        return sendButtons(report)
    }

    /// Changes the code byte of several entries in one report (read-modify-write against a fresh read).
    public func writeButtonCodes(_ codes: [Int: UInt8]) -> ButtonsWriteResult {
        guard let current = readButtonsReport() else {
            return .failed("Mouse isn't answering — move it to wake it up")
        }
        guard let report = try? current.settingCodes(codes) else {
            return .failed("Invalid button entry")
        }
        return sendButtons(report)
    }

    /// Writes a complete Buttons report back (used to restore the original one).
    public func writeButtonsReport(_ report: ButtonsReport) -> ButtonsWriteResult {
        sendButtons(report.bytes)
    }

    private func sendButtons(_ report: [UInt8]) -> ButtonsWriteResult {
        guard sendFeatureReport(reportID: ProtocolConstants.reportButtons, data: report) else {
            return .failed("Couldn't send the button settings to the mouse")
        }
        usleep(300_000)   // give the mouse time to apply it before reading back
        for _ in 0..<3 {
            if let readback = readButtonsReport() { return .written(readback) }
            usleep(300_000)
        }
        return .written(nil)
    }

    /// Polling rate + debounce + angle snapping / ripple control, read together. Nil if any of them fails.
    public func readPerformanceSnapshot() -> PerformanceSnapshot? {
        guard let polling = readPollingRate(),
              let system = readSystemSettings(),
              let dpi = readDPIConfiguration() else { return nil }
        return PerformanceSnapshot(polling: polling, system: system, dpi: dpi)
    }

    /// Writes the Performance settings, sending only the reports whose values differ from what the mouse holds.
    ///
    /// Every write is read-modify-write against a fresh read, so nothing the tab doesn't edit (DPI stages,
    /// colours, lighting, sleep timers) can be overwritten with stale values.
    public func writePerformance(_ target: PerformanceSettings) -> PerformanceWriteResult {
        guard let rate = PollingRate(rawValue: target.pollingRate) else {
            return .failed("Unsupported polling rate")
        }
        guard SystemSettingsReport.debounceRange.contains(target.debounceMs) else {
            return .failed("Unsupported debounce time")
        }
        guard let current = readPerformanceSnapshot() else {
            return .failed("Mouse isn't answering — move it to wake it up")
        }
        let now = current.settings
        var sentAnything = false

        if now.pollingRate != target.pollingRate {
            guard sendFeatureReport(reportID: ProtocolConstants.reportPolling, data: PollingProtocol.encode(rate)) else {
                return .failed("Couldn't send the polling rate to the mouse")
            }
            sentAnything = true
            usleep(120_000)
        }

        if now.debounceMs != target.debounceMs {
            guard let report = try? current.system.settingDebounce(target.debounceMs),
                  sendFeatureReport(reportID: ProtocolConstants.reportLight, data: report) else {
                return .failed("Couldn't send the debounce time to the mouse")
            }
            sentAnything = true
            usleep(120_000)
        }

        if now.angleSnapping != target.angleSnapping || now.rippleControl != target.rippleControl {
            var configuration = current.dpi
            configuration.angleSnap = target.angleSnapping
            configuration.rippleControl = target.rippleControl
            guard let report = try? DPIProtocol.encode(configuration),
                  sendFeatureReport(reportID: ProtocolConstants.reportDPI, data: report) else {
                return .failed("Couldn't send the sensor settings to the mouse")
            }
            sentAnything = true
            usleep(120_000)
        }

        guard sentAnything else { return .written(current) }
        return .written(readPerformanceSnapshot())
    }
}
