import Foundation

// `nonisolated`: the app target defaults to @MainActor, but the HID I/O (which uses this codec)
// runs on a background queue.
public nonisolated enum ProtocolConstants {
    public static let vendorID: Int = 0x1D57
    public static let productReceiver: Int = 0xFA60
    public static let productWired: Int = 0xFA55
    
    // Feature Report IDs & Sizes
    public static let reportDPI: UInt8 = 0x04
    public static let reportLight: UInt8 = 0x05
    public static let reportPolling: UInt8 = 0x06
    public static let reportButtons: UInt8 = 0x08
    public static let reportIdent: UInt8 = 0x0B
    public static let reportReadReq: UInt8 = 0xA0
    
    public static let reportSizes: [UInt8: Int] = [
        0x04: 56,
        0x05: 15,
        0x06: 9,
        0x08: 59,
        0x09: 64,
        0x0B: 8,
        0xA0: 8
    ]
    
    // Event IDs
    public static let evDPI: UInt8 = 0x10
    public static let evPolling: UInt8 = 0x20
    public static let evBattery: UInt8 = 0x40
    public static let evAck: UInt8 = 0x50
    public static let chargingFlag: UInt8 = 0x03
}

public nonisolated struct ProtocolHelper {
    /// Computes a 16-bit big-endian checksum of the data block.
    public static func checksum(data: [UInt8]) -> [UInt8] {
        let sum = data.reduce(0) { ($0 + Int($1)) & 0xFFFF }
        return [UInt8(sum >> 8), UInt8(sum & 0xFF)]
    }
    
    /// Builds the 0xA0 read request packet.
    public static func makeReadRequest(reportID: UInt8) -> Data {
        let size = UInt8(ProtocolConstants.reportSizes[reportID] ?? 8)
        let payload: [UInt8] = [
            ProtocolConstants.reportReadReq,
            reportID,
            size,
            0x00,
            reportID == ProtocolConstants.reportIdent ? 0x00 : 0x01,
            0x00, 0x00, 0x00
        ]
        return Data(payload)
    }
    
    /// Parses an incoming Input Report 0x03 event: (model, event, v0, v1)
    public static func parseEvent(report: Data) -> (model: UInt8, event: UInt8, v0: UInt8, v1: UInt8)? {
        guard report.count >= 5, report[0] == 0x03 else { return nil }
        return (report[1], report[2], report[3], report[4])
    }
}

// MARK: - Performance settings
//
// Report 0x06 (9 bytes)  polling rate
// Report 0x05 (15 bytes) lighting + sleep timers + button debounce (byte 10)
// Report 0x04 (56 bytes) DPI table, which also holds angle snapping (byte 3) and ripple control (byte 4)

public nonisolated enum PollingRate: Int, CaseIterable, Sendable {
    case hz125 = 125
    case hz250 = 250
    case hz500 = 500
    case hz1000 = 1000

    /// Code the mouse uses for this rate in report 0x06.
    public var code: UInt8 {
        switch self {
        case .hz125: 0x08
        case .hz250: 0x04
        case .hz500: 0x02
        case .hz1000: 0x01
        }
    }

    public init?(code: UInt8) {
        guard let rate = Self.allCases.first(where: { $0.code == code }) else { return nil }
        self = rate
    }
}

public nonisolated enum PollingProtocol {
    private static let reportLength = 9

    /// `06 09 01 <rate> <0xFF - rate> 00 00 00 00`, e.g. 125 Hz is `06 09 01 08 F7 00 00 00 00`.
    public static func encode(_ rate: PollingRate) -> [UInt8] {
        [ProtocolConstants.reportPolling, UInt8(reportLength), 0x01, rate.code, 0xFF - rate.code, 0x00, 0x00, 0x00, 0x00]
    }

    public static func decode(_ report: [UInt8]) throws -> PollingRate {
        guard report.count == reportLength else {
            throw ProtocolError.badLength(expected: reportLength, actual: report.count)
        }
        guard report[0] == ProtocolConstants.reportPolling else {
            throw ProtocolError.unexpectedReportID(expected: ProtocolConstants.reportPolling, actual: report[0])
        }
        guard report[1] == UInt8(reportLength) else {
            throw ProtocolError.invalidReportedLength(expected: UInt8(reportLength), actual: report[1])
        }
        guard let rate = PollingRate(code: report[3]) else {
            throw ProtocolError.invalidPollingCode(report[3])
        }
        return rate
    }
}

/// Report 0x05 as the mouse reported it. Only the debounce time is changed; every other byte (lighting mode,
/// colour, brightness, sleep timers) is written back exactly as read, with the checksum recomputed.
public nonisolated struct SystemSettingsReport: Equatable, Sendable {
    public static let reportLength = 15
    /// "Key Response Time" slider of the official app.
    public static let debounceRange = 2...25
    private static let debounceOffset = 10
    private static let checksumOffset = 11

    private let bytes: [UInt8]

    public var debounceMs: Int { Int(bytes[Self.debounceOffset]) }

    public init(decoding report: [UInt8]) throws {
        guard report.count == Self.reportLength else {
            throw ProtocolError.badLength(expected: Self.reportLength, actual: report.count)
        }
        guard report[0] == ProtocolConstants.reportLight else {
            throw ProtocolError.unexpectedReportID(expected: ProtocolConstants.reportLight, actual: report[0])
        }
        guard report[1] == UInt8(Self.reportLength) else {
            throw ProtocolError.invalidReportedLength(expected: UInt8(Self.reportLength), actual: report[1])
        }
        let expected = ProtocolHelper.checksum(data: Array(report[3..<Self.checksumOffset]))
        guard Array(report[Self.checksumOffset..<(Self.checksumOffset + 2)]) == expected else {
            throw ProtocolError.invalidChecksum
        }
        bytes = report
    }

    /// The complete report to send for a new debounce time.
    public func settingDebounce(_ milliseconds: Int) throws -> [UInt8] {
        guard Self.debounceRange.contains(milliseconds) else {
            throw ProtocolError.invalidDebounce(milliseconds)
        }
        var report = bytes
        report[Self.debounceOffset] = UInt8(milliseconds)
        let checksum = ProtocolHelper.checksum(data: Array(report[3..<Self.checksumOffset]))
        report[Self.checksumOffset] = checksum[0]
        report[Self.checksumOffset + 1] = checksum[1]
        return report
    }
}

/// What the Performance tab edits.
public nonisolated struct PerformanceSettings: Equatable, Sendable {
    public var pollingRate: Int
    public var debounceMs: Int
    public var angleSnapping: Bool
    public var rippleControl: Bool

    public init(pollingRate: Int, debounceMs: Int, angleSnapping: Bool, rippleControl: Bool) {
        self.pollingRate = pollingRate
        self.debounceMs = debounceMs
        self.angleSnapping = angleSnapping
        self.rippleControl = rippleControl
    }
}

/// The three reports the Performance tab depends on, read together.
public nonisolated struct PerformanceSnapshot: Sendable {
    public let polling: PollingRate
    public let system: SystemSettingsReport
    public let dpi: DPIConfiguration

    public init(polling: PollingRate, system: SystemSettingsReport, dpi: DPIConfiguration) {
        self.polling = polling
        self.system = system
        self.dpi = dpi
    }

    public var settings: PerformanceSettings {
        PerformanceSettings(
            pollingRate: polling.rawValue,
            debounceMs: system.debounceMs,
            angleSnapping: dpi.angleSnap,
            rippleControl: dpi.rippleControl
        )
    }
}
