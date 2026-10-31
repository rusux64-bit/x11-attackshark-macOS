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

// MARK: - Lighting & power (report 0x05)
//
// Layout (15 bytes), confirmed against the default report `05 0F 01 00 03 A8 00 FF 00 01 04 01 AF 00 00`:
//
//     [3]     light mode in the HIGH nibble (0 off, 1 steady, 2 breathing, 3 neon, 4 colour breathing,
//             5 steady by DPI stage, 6 breathing by DPI stage)
//     [4]     high nibble: deep-sleep timer (high part), low nibble: LED animation speed (inverted, see below)
//     [5]     high nibble: deep-sleep timer (low part), low nibble: LED brightness 1...8
//     [6...8] LED colour R, G, B
//     [9]     idle sleep timer in half-minutes
//     [10]    key response time (debounce), see `SystemSettingsReport`
//     [11,12] 16-bit big-endian sum of bytes 3...10
//
// Every write is read-modify-write: only the fields that really changed are touched, so the deep-sleep timer
// and every byte the app doesn't know about are sent back exactly as the mouse reported them.

public nonisolated enum LightingMode: UInt8, CaseIterable, Sendable {
    case off = 0
    case steady = 1
    case breathing = 2
    case neon = 3
    case colorBreathing = 4
    case dpiSteady = 5
    case dpiBreathing = 6
}

/// What the Lighting and Power tabs edit (everything that lives in report 0x05 apart from the debounce time).
public nonisolated struct LightingSettings: Equatable, Sendable {
    public static let brightnessRange = 1...8
    /// 1 = slowest ... 5 = fastest (the mouse stores it inverted).
    public static let speedRange = 1...5
    /// The mouse counts the idle sleep timer in half-minutes.
    public static let sleepStepSeconds = 30

    public var mode: LightingMode
    public var brightness: Int
    public var speed: Int
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var sleepSeconds: Int

    public init(mode: LightingMode, brightness: Int, speed: Int, red: UInt8, green: UInt8, blue: UInt8, sleepSeconds: Int) {
        self.mode = mode
        self.brightness = brightness
        self.speed = speed
        self.red = red
        self.green = green
        self.blue = blue
        self.sleepSeconds = sleepSeconds
    }
}

extension SystemSettingsReport {
    /// The lighting and sleep settings held by this report.
    public var lighting: LightingSettings {
        let mode = LightingMode(rawValue: bytes[3] >> 4) ?? .steady
        let hardwareSpeed = min(max(Int(bytes[4] & 0x0F), 1), 5)
        let brightness = min(max(Int(bytes[5] & 0x0F), 1), 8)
        return LightingSettings(
            mode: mode,
            brightness: brightness,
            speed: 6 - hardwareSpeed,
            red: bytes[6],
            green: bytes[7],
            blue: bytes[8],
            sleepSeconds: Int(bytes[9]) * LightingSettings.sleepStepSeconds
        )
    }

    /// The complete report to send for new lighting / sleep settings (checksum recomputed).
    /// Fields that already match are not touched, so their original bytes (including nibbles this app doesn't
    /// edit, like the deep-sleep timer) survive unchanged.
    public func applying(_ target: LightingSettings) throws -> [UInt8] {
        let step = LightingSettings.sleepStepSeconds
        guard LightingSettings.brightnessRange.contains(target.brightness),
              LightingSettings.speedRange.contains(target.speed) else {
            throw ProtocolError.invalidLightingSetting
        }

        let current = lighting
        var report = bytes
        if target.mode != current.mode {
            report[3] = (report[3] & 0x0F) | (target.mode.rawValue << 4)
        }
        if target.speed != current.speed {
            report[4] = (report[4] & 0xF0) | UInt8(6 - target.speed)
        }
        if target.brightness != current.brightness {
            report[5] = (report[5] & 0xF0) | UInt8(target.brightness)
        }
        if target.red != current.red { report[6] = target.red }
        if target.green != current.green { report[7] = target.green }
        if target.blue != current.blue { report[8] = target.blue }
        if target.sleepSeconds != current.sleepSeconds {
            guard target.sleepSeconds % step == 0, (1...255).contains(target.sleepSeconds / step) else {
                throw ProtocolError.invalidLightingSetting
            }
            report[9] = UInt8(target.sleepSeconds / step)
        }

        let checksum = ProtocolHelper.checksum(data: Array(report[3..<11]))
        report[11] = checksum[0]
        report[12] = checksum[1]
        return report
    }
}

// MARK: - Buttons (report 0x08)

/// Report 0x08 (59 bytes). Layout confirmed against a real dump (the checksum matches):
///
///     [0]      08   report ID
///     [1]      3B   length (59)
///     [2]      01
///     [3...56] 18 entries of 3 bytes: <code> <param1> <param2>
///     [57,58]  16-bit big-endian sum of bytes 3...56
///
/// What each entry and each code MEANS is still being worked out (see the experiment card in the Buttons tab).
/// Writes therefore only ever change the code byte of ONE entry; every other byte is kept as the mouse reported it.
public nonisolated struct ButtonsReport: Equatable, Sendable {
    public static let reportLength = 59
    public static let entryCount = 18
    private static let firstEntryOffset = 3
    private static let entrySize = 3
    private static let checksumOffset = 57

    /// The report exactly as the mouse sent it (first dump seen on a real X11; used as a last-resort restore point).
    public static let observedDefaultBytes: [UInt8] = [
        0x08, 0x3B, 0x01, 0x02, 0x00, 0x00, 0x03, 0x00, 0x00, 0x04, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x0D, 0x00, 0x00, 0x06, 0x00, 0x00, 0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00,
        0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x09, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x3E
    ]

    public let bytes: [UInt8]

    public init(decoding report: [UInt8]) throws {
        guard report.count == Self.reportLength else {
            throw ProtocolError.badLength(expected: Self.reportLength, actual: report.count)
        }
        guard report[0] == ProtocolConstants.reportButtons else {
            throw ProtocolError.unexpectedReportID(expected: ProtocolConstants.reportButtons, actual: report[0])
        }
        guard report[1] == UInt8(Self.reportLength) else {
            throw ProtocolError.invalidReportedLength(expected: UInt8(Self.reportLength), actual: report[1])
        }
        let expected = ProtocolHelper.checksum(data: Array(report[Self.firstEntryOffset..<Self.checksumOffset]))
        guard Array(report[Self.checksumOffset..<(Self.checksumOffset + 2)]) == expected else {
            throw ProtocolError.invalidChecksum
        }
        bytes = report
    }

    /// The code byte of every entry, in report order.
    public var codes: [UInt8] {
        (0..<Self.entryCount).map { bytes[Self.firstEntryOffset + $0 * Self.entrySize] }
    }

    public func entry(_ index: Int) throws -> (code: UInt8, param1: UInt8, param2: UInt8) {
        guard (0..<Self.entryCount).contains(index) else { throw ProtocolError.invalidButtonEntry(index) }
        let offset = Self.firstEntryOffset + index * Self.entrySize
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }

    /// The complete report to send after changing the code byte of one entry (checksum recomputed).
    public func settingCode(_ code: UInt8, forEntry index: Int) throws -> [UInt8] {
        guard (0..<Self.entryCount).contains(index) else { throw ProtocolError.invalidButtonEntry(index) }
        var report = bytes
        report[Self.firstEntryOffset + index * Self.entrySize] = code
        let checksum = ProtocolHelper.checksum(data: Array(report[Self.firstEntryOffset..<Self.checksumOffset]))
        report[Self.checksumOffset] = checksum[0]
        report[Self.checksumOffset + 1] = checksum[1]
        return report
    }

    /// Like `settingCode`, for several entries at once (checksum recomputed once).
    public func settingCodes(_ codes: [Int: UInt8]) throws -> [UInt8] {
        var report = bytes
        for (index, code) in codes {
            guard (0..<Self.entryCount).contains(index) else { throw ProtocolError.invalidButtonEntry(index) }
            report[Self.firstEntryOffset + index * Self.entrySize] = code
        }
        let checksum = ProtocolHelper.checksum(data: Array(report[Self.firstEntryOffset..<Self.checksumOffset]))
        report[Self.checksumOffset] = checksum[0]
        report[Self.checksumOffset + 1] = checksum[1]
        return report
    }

    /// 16 bytes per line, each line starting with the offset of its first byte.
    public var hexDump: String {
        stride(from: 0, to: bytes.count, by: 16).map { start in
            let chunk = bytes[start..<min(start + 16, bytes.count)]
            return String(format: "%02d: ", start) + chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
        }.joined(separator: "\n")
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
