import Foundation
import IOKit.hid

/// Outcome of writing the Performance settings.
public nonisolated enum PerformanceWriteResult: Sendable {
    case failed(String)
    /// Everything that had to be sent was sent. The snapshot is the read-back (nil if the mouse didn't answer it).
    case written(PerformanceSnapshot?)
}

/// Talks to ONE HID endpoint of the mouse.
///
/// Everything here is synchronous and can block for a few hundred milliseconds (the mouse answers a read
/// request asynchronously), so call it from a background queue, never from the main thread.
/// `nonisolated` because the app target defaults to @MainActor.
public nonisolated final class DeviceTransport: @unchecked Sendable {
    public let hidDevice: IOHIDDevice

    public init(hidDevice: IOHIDDevice) {
        self.hidDevice = hidDevice
    }

    /// Sends a feature report. `data` is the complete report INCLUDING the report ID as its first byte.
    @discardableResult
    public func sendFeatureReport(reportID: UInt8, data: [UInt8], logFailure: Bool = true) -> Bool {
        let result = data.withUnsafeBufferPointer { buffer -> IOReturn in
            guard let base = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(
                hidDevice,
                kIOHIDReportTypeFeature,
                CFIndex(reportID),
                base,
                buffer.count
            )
        }

        if result != kIOReturnSuccess {
            if logFailure {
                print("❌ Failed to send feature report ID 0x\(String(format: "%02X", reportID)): 0x\(String(UInt32(bitPattern: result), radix: 16))")
            }
            return false
        }
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
