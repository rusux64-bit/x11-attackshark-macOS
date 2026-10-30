import Foundation
import IOKit.hid

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
}
