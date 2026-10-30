import Foundation

public nonisolated enum ProtocolError: Error, Equatable {
    case badLength(expected: Int, actual: Int)
    case unexpectedReportID(expected: UInt8, actual: UInt8)
    case invalidReportedLength(expected: UInt8, actual: UInt8)
    case invalidChecksum
    case invalidDPI(Int)
    case invalidStep(Int)
    case invalidSensorFlag(UInt8)
    case invalidStageCount(Int)
    case noEnabledDPIStage
    case invalidActiveStage(Int)
}

public nonisolated struct DPIColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let red = DPIColor(red: 0xFF, green: 0x00, blue: 0x00)
    public static let green = DPIColor(red: 0x00, green: 0xFF, blue: 0x00)
    public static let blue = DPIColor(red: 0x00, green: 0x00, blue: 0xFF)
    public static let yellow = DPIColor(red: 0xFF, green: 0xFF, blue: 0x00)
    public static let cyan = DPIColor(red: 0x00, green: 0xFF, blue: 0xFF)
    public static let magenta = DPIColor(red: 0xFF, green: 0x00, blue: 0xFF)
    public static let white = DPIColor(red: 0xFF, green: 0xFF, blue: 0xFF)
}

public nonisolated struct DPISensorCode: Equatable, Sendable {
    public let code: UInt8
    public let lowRange: Bool
    public let highRange: Bool

    public init(code: UInt8, lowRange: Bool, highRange: Bool) {
        self.code = code
        self.lowRange = lowRange
        self.highRange = highRange
    }
}

public nonisolated struct DPIStage: Equatable, Sendable {
    public var dpi: Int
    public var isEnabled: Bool
    public var color: DPIColor
    fileprivate let readSensorCode: DPISensorCode?

    public init(dpi: Int, isEnabled: Bool, color: DPIColor) {
        self.dpi = dpi
        self.isEnabled = isEnabled
        self.color = color
        self.readSensorCode = nil
    }

    fileprivate init(dpi: Int, isEnabled: Bool, color: DPIColor, readSensorCode: DPISensorCode) {
        self.dpi = dpi
        self.isEnabled = isEnabled
        self.color = color
        self.readSensorCode = readSensorCode
    }
}

public nonisolated struct DPIConfiguration: Equatable, Sendable {
    public var angleSnap: Bool
    public var rippleControl: Bool
    public var stages: [DPIStage]
    public var activeStage: Int
    fileprivate let trailingBytes: [UInt8]

    public init(angleSnap: Bool, rippleControl: Bool, stages: [DPIStage], activeStage: Int) {
        self.angleSnap = angleSnap
        self.rippleControl = rippleControl
        self.stages = stages
        self.activeStage = activeStage
        self.trailingBytes = [0, 0, 0, 0]
    }

    fileprivate init(angleSnap: Bool, rippleControl: Bool, stages: [DPIStage], activeStage: Int, trailingBytes: [UInt8]) {
        self.angleSnap = angleSnap
        self.rippleControl = rippleControl
        self.stages = stages
        self.activeStage = activeStage
        self.trailingBytes = trailingBytes
    }
}

public nonisolated enum DPIProtocol {
    private static let reportLength = 56
    private static let checksumOffset = 50
    private static let stageCount = 8

    // Sensor table T from sharkx11.protocol.T, indexed by slider step 0...220.
    private static let sensorCodeTable: [UInt8] = [
        0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 14, 15, 16, 17, 18, 19, 21, 22, 23,
        24, 25, 27, 28, 29, 30, 31, 32, 34, 35, 36, 37, 38, 39, 41, 42, 43, 44, 45, 47,
        48, 49, 50, 51, 52, 54, 55, 56, 57, 58, 59, 61, 62, 63, 64, 65, 67, 68, 69, 70,
        71, 72, 74, 75, 76, 77, 78, 79, 81, 82, 83, 84, 85, 87, 88, 89, 90, 91, 92, 94,
        95, 96, 97, 98, 99, 101, 102, 103, 104, 105, 107, 108, 109, 110, 111, 112, 114, 115, 116, 117,
        118, 119, 121, 122, 123, 124, 125, 127, 128, 129, 130, 131, 132, 134, 135, 136, 137, 138, 139, 141,
        142, 143, 144, 145, 147, 148, 149, 150, 151, 152, 154, 155, 156, 157, 158, 159, 161, 162, 163, 164,
        165, 167, 168, 169, 170, 171, 172, 174, 175, 176, 177, 178, 179, 181, 182, 183, 184, 185, 187, 188,
        189, 190, 191, 192, 194, 195, 196, 197, 198, 199, 201, 202, 203, 204, 205, 207, 208, 209, 210, 211,
        212, 214, 215, 216, 217, 218, 219, 221, 222, 223, 224, 225, 227, 228, 229, 230, 231, 232, 234, 235,
        118, 119, 121, 122, 123, 124, 125, 127, 128, 129, 130, 131, 132, 134, 135, 136, 137, 138, 139, 141
    ]

    /// Report 0x04: mirrors Python `dpi_to_step`, converting an allowed DPI value to its slider step.
    public static func dpiToStep(_ dpi: Int) throws -> Int {
        let increment = dpi <= 10_000 ? 50 : 100
        guard (50...22_000).contains(dpi), dpi % increment == 0 else {
            throw ProtocolError.invalidDPI(dpi)
        }
        return dpi <= 10_000 ? dpi / 50 : dpi / 100 + 100
    }

    /// Report 0x04: mirrors Python `step_to_dpi`, converting a slider step to DPI.
    public static func stepToDPI(_ step: Int) -> Int {
        step <= 200 ? 50 * step : 100 * (step - 100)
    }

    /// Report 0x04: mirrors Python `encode_step`, producing a sensor code and its range flags.
    public static func encodeStep(_ step: Int) throws -> DPISensorCode {
        guard (1...320).contains(step) else {
            throw ProtocolError.invalidStep(step)
        }
        if step <= 200 {
            return DPISensorCode(code: sensorCodeTable[step], lowRange: false, highRange: false)
        }
        if step <= 220 {
            return DPISensorCode(code: sensorCodeTable[step], lowRange: true, highRange: false)
        }
        if step <= 300 {
            return DPISensorCode(code: sensorCodeTable[step - 100], lowRange: false, highRange: true)
        }
        let code = Int((Double(stepToDPI(step)) / (42.55 * 4)).rounded())
        return DPISensorCode(code: UInt8(code), lowRange: true, highRange: true)
    }

    /// Report 0x04: mirrors Python `decode_step`, returning the matching or nearest slider step.
    public static func decodeStep(code: UInt8, lowRange: Bool, highRange: Bool) -> Int {
        let sensorCode = DPISensorCode(code: code, lowRange: lowRange, highRange: highRange)
        for step in (1...320).reversed() where (try? encodeStep(step)) == sensorCode {
            return step
        }

        let multiplier = (lowRange ? 1 : 0) + (highRange ? 1 : 0)
        let dpi = Double(code) * 42.55 * pow(2, Double(multiplier))
        return (1...320).min { abs(Double(stepToDPI($0)) - dpi) < abs(Double(stepToDPI($1)) - dpi) } ?? 1
    }

    /// Report 0x04: mirrors Python `encode_dpi`, framing the complete 56-byte DPI feature report.
    public static func encode(_ configuration: DPIConfiguration) throws -> [UInt8] {
        guard configuration.stages.count == stageCount else {
            throw ProtocolError.invalidStageCount(configuration.stages.count)
        }
        guard configuration.stages.contains(where: \.isEnabled) else {
            throw ProtocolError.noEnabledDPIStage
        }
        guard (1...stageCount).contains(configuration.activeStage) else {
            throw ProtocolError.invalidActiveStage(configuration.activeStage)
        }

        var report = Array(repeating: UInt8(0), count: reportLength)
        report[0] = ProtocolConstants.reportDPI
        report[1] = UInt8(reportLength)
        report[2] = 0x01
        report[3] = configuration.angleSnap ? 1 : 0
        report[4] = configuration.rippleControl ? 1 : 0

        for (index, stage) in configuration.stages.enumerated() {
            let step = try dpiToStep(stage.dpi)
            let sensorCode: DPISensorCode
            if let readSensorCode = stage.readSensorCode, decodeStep(
                code: readSensorCode.code,
                lowRange: readSensorCode.lowRange,
                highRange: readSensorCode.highRange
            ) == step {
                sensorCode = readSensorCode
            } else {
                sensorCode = try encodeStep(step)
            }
            if stage.isEnabled {
                report[5] |= 1 << UInt8(index)
            }
            if sensorCode.highRange {
                report[6] |= 1 << UInt8(index)
            }
            report[8 + index] = sensorCode.code
            report[16 + index] = sensorCode.lowRange ? 1 : 0
            report[25 + index * 3] = stage.color.red
            report[26 + index * 3] = stage.color.green
            report[27 + index * 3] = stage.color.blue
        }

        report[7] = report[6]
        report[24] = UInt8(configuration.activeStage)
        report[49] = 0x02
        let checksum = ProtocolHelper.checksum(data: Array(report[3..<checksumOffset]))
        report[checksumOffset] = checksum[0]
        report[checksumOffset + 1] = checksum[1]
        report.replaceSubrange(52..<56, with: configuration.trailingBytes)
        return report
    }

    /// Report 0x04: mirrors Python `decode_dpi`, validating and parsing the complete DPI feature report.
    public static func decode(_ report: [UInt8]) throws -> DPIConfiguration {
        guard report.count == reportLength else {
            throw ProtocolError.badLength(expected: reportLength, actual: report.count)
        }
        guard report[0] == ProtocolConstants.reportDPI else {
            throw ProtocolError.unexpectedReportID(expected: ProtocolConstants.reportDPI, actual: report[0])
        }
        guard report[1] == UInt8(reportLength) else {
            throw ProtocolError.invalidReportedLength(expected: UInt8(reportLength), actual: report[1])
        }
        guard Array(report[checksumOffset..<(checksumOffset + 2)]) == ProtocolHelper.checksum(data: Array(report[3..<checksumOffset])) else {
            throw ProtocolError.invalidChecksum
        }

        var stages: [DPIStage] = []
        for index in 0..<stageCount {
            let lowFlag = report[16 + index]
            guard lowFlag <= 1 else {
                throw ProtocolError.invalidSensorFlag(lowFlag)
            }
            let sensorCode = DPISensorCode(
                code: report[8 + index],
                lowRange: lowFlag == 1,
                highRange: report[6] & (1 << UInt8(index)) != 0
            )
            let dpi = sensorCode.code == 0 ? 800 : stepToDPI(decodeStep(
                code: sensorCode.code,
                lowRange: sensorCode.lowRange,
                highRange: sensorCode.highRange
            ))
            stages.append(DPIStage(
                dpi: dpi,
                isEnabled: report[5] & (1 << UInt8(index)) != 0,
                color: DPIColor(red: report[25 + index * 3], green: report[26 + index * 3], blue: report[27 + index * 3]),
                readSensorCode: sensorCode
            ))
        }

        return DPIConfiguration(
            angleSnap: report[3] != 0,
            rippleControl: report[4] != 0,
            stages: stages,
            activeStage: min(max(Int(report[24]), 1), stageCount),
            trailingBytes: Array(report[52..<56])
        )
    }
}
