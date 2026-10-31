import Testing
@testable import SharkControlProtocol

struct DPICodecTests {
    private let defaultReport: [UInt8] = [
        0x04, 0x38, 0x01, 0x00, 0x00, 0x3F, 0x20, 0x20,
        0x12, 0x25, 0x38, 0x4B, 0x75, 0x81, 0x12, 0x12,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x02, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00,
        0x00, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF,
        0xFF, 0x00, 0xFF, 0xFF, 0x40, 0x00, 0xFF, 0xFF,
        0xFF, 0x02, 0x0F, 0x8B, 0x00, 0x00, 0x00, 0x00
    ]

    @Test("DPI-to-step vectors from test_protocol.py")
    func dpiStepVectors() throws {
        for (dpi, step) in [(50, 1), (800, 16), (10_000, 200), (10_100, 201), (22_000, 320)] {
            #expect(try DPIProtocol.dpiToStep(dpi) == step)
            #expect(DPIProtocol.stepToDPI(step) == dpi)
        }

        for dpi in [0, 40, 825, 10_150, 22_100] {
            #expect(throws: ProtocolError.self) {
                try DPIProtocol.dpiToStep(dpi)
            }
        }
    }

    @Test("DPI sensor-code vectors from test_protocol.py")
    func dpiSensorCodeVectors() throws {
        #expect(try DPIProtocol.encodeStep(301) == DPISensorCode(code: 118, lowRange: true, highRange: true))
        #expect(try DPIProtocol.encodeStep(320) == DPISensorCode(code: 129, lowRange: true, highRange: true))
        #expect(try DPIProtocol.encodeStep(221) == DPISensorCode(code: 142, lowRange: false, highRange: true))
        #expect(try DPIProtocol.encodeStep(210) == DPISensorCode(code: 129, lowRange: true, highRange: false))
        #expect(DPIProtocol.decodeStep(code: 100, lowRange: true, highRange: true) == 270)
    }

    @Test("DPI sensor-code round trips from test_protocol.py")
    func dpiSensorCodeRoundTrips() throws {
        for step in 1...301 {
            let sensorCode = try DPIProtocol.encodeStep(step)
            #expect(DPIProtocol.decodeStep(
                code: sensorCode.code,
                lowRange: sensorCode.lowRange,
                highRange: sensorCode.highRange
            ) == step)
        }
        let step302 = try DPIProtocol.encodeStep(302)
        #expect(DPIProtocol.decodeStep(code: step302.code, lowRange: step302.lowRange, highRange: step302.highRange) == 303)
        let step320 = try DPIProtocol.encodeStep(320)
        #expect(DPIProtocol.decodeStep(code: step320.code, lowRange: step320.lowRange, highRange: step320.highRange) == 320)
    }

    @Test("DPI default report byte vector from test_config.py")
    func encodeDefaultReport() throws {
        #expect(try DPIProtocol.encode(defaultConfiguration) == defaultReport)
    }

    @Test("DPI default report decoder")
    func decodeDefaultReport() throws {
        let configuration = try DPIProtocol.decode(defaultReport)

        #expect(configuration.angleSnap == false)
        #expect(configuration.rippleControl == false)
        #expect(configuration.activeStage == 2)
        #expect(configuration.stages.map(\.dpi) == [800, 1_600, 2_400, 3_200, 5_000, 22_000, 800, 800])
        #expect(configuration.stages.map(\.isEnabled) == [true, true, true, true, true, true, false, false])
        #expect(configuration.stages[6].color == DPIColor(red: 0xFF, green: 0x40, blue: 0x00))
    }

    @Test("DPI decoder rejects malformed report vectors")
    func decoderRejectsMalformedReports() throws {
        #expect(throws: ProtocolError.self) {
            try DPIProtocol.decode(Array(defaultReport.dropLast()))
        }
        var wrongReportID = defaultReport
        wrongReportID[0] = 0x05
        #expect(throws: ProtocolError.self) {
            try DPIProtocol.decode(wrongReportID)
        }
        var badChecksum = defaultReport
        badChecksum[50] ^= 1
        #expect(throws: ProtocolError.self) {
            try DPIProtocol.decode(badChecksum)
        }
    }

    private var defaultConfiguration: DPIConfiguration {
        DPIConfiguration(
            angleSnap: false,
            rippleControl: false,
            stages: [
                DPIStage(dpi: 800, isEnabled: true, color: .red),
                DPIStage(dpi: 1_600, isEnabled: true, color: .green),
                DPIStage(dpi: 2_400, isEnabled: true, color: .blue),
                DPIStage(dpi: 3_200, isEnabled: true, color: .yellow),
                DPIStage(dpi: 5_000, isEnabled: true, color: .cyan),
                DPIStage(dpi: 22_000, isEnabled: true, color: .magenta),
                DPIStage(dpi: 800, isEnabled: false, color: DPIColor(red: 0xFF, green: 0x40, blue: 0x00)),
                DPIStage(dpi: 800, isEnabled: false, color: .white)
            ],
            activeStage: 2
        )
    }
}

struct ButtonsCodecTests {
    /// Real dump read from an X11 (the same bytes as ButtonsReport.observedDefaultBytes).
    private let realReport: [UInt8] = [
        0x08, 0x3B, 0x01, 0x02, 0x00, 0x00, 0x03, 0x00, 0x00, 0x04, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x0D, 0x00, 0x00, 0x06, 0x00, 0x00, 0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00,
        0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x09, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x3E
    ]

    @Test("Real report decodes and its checksum matches")
    func decodesRealReport() throws {
        let report = try ButtonsReport(decoding: realReport)
        #expect(report.codes == [2, 3, 4, 1, 1, 13, 6, 5, 1, 1, 1, 1, 1, 1, 1, 1, 9, 10])
        #expect(report.bytes == realReport)
        #expect(ButtonsReport.observedDefaultBytes == realReport)
    }

    @Test("Changing one entry touches only that code byte and the checksum")
    func settingOneEntry() throws {
        let report = try ButtonsReport(decoding: realReport)
        let changed = try report.settingCode(0x06, forEntry: 7)   // entry 8 in the UI, was 0x05

        #expect(changed[24] == 0x06)
        #expect(changed[57] == 0x00)
        #expect(changed[58] == 0x3F)   // 0x3E + 1
        for index in 0..<changed.count where index != 24 && index != 58 {
            #expect(changed[index] == realReport[index])
        }
        #expect(try ButtonsReport(decoding: changed).codes[7] == 0x06)
    }

    @Test("Changing several entries recomputes the checksum once")
    func settingSeveralEntries() throws {
        let report = try ButtonsReport(decoding: realReport)
        let changed = try report.settingCodes([6: 0x05, 7: 0x06])   // swap Forward and Back

        let decoded = try ButtonsReport(decoding: changed)
        #expect(decoded.codes[6] == 0x05)
        #expect(decoded.codes[7] == 0x06)
        #expect(changed[57] == 0x00)
        #expect(changed[58] == 0x3E)   // 5 + 6 is still 11, so the sum is unchanged
        #expect(throws: ProtocolError.self) { try report.settingCodes([18: 1]) }
    }

    @Test("Buttons decoder rejects malformed reports")
    func rejectsMalformedReports() throws {
        #expect(throws: ProtocolError.self) { try ButtonsReport(decoding: Array(realReport.dropLast())) }

        var wrongID = realReport
        wrongID[0] = 0x04
        #expect(throws: ProtocolError.self) { try ButtonsReport(decoding: wrongID) }

        var badChecksum = realReport
        badChecksum[58] ^= 1
        #expect(throws: ProtocolError.self) { try ButtonsReport(decoding: badChecksum) }

        let report = try ButtonsReport(decoding: realReport)
        #expect(throws: ProtocolError.self) { try report.settingCode(1, forEntry: 18) }
        #expect(throws: ProtocolError.self) { try report.settingCode(1, forEntry: -1) }
    }
}

struct PerformanceCodecTests {
    @Test("Polling report vectors")
    func pollingVectors() throws {
        #expect(PollingProtocol.encode(.hz125) == [0x06, 0x09, 0x01, 0x08, 0xF7, 0x00, 0x00, 0x00, 0x00])
        #expect(PollingProtocol.encode(.hz250) == [0x06, 0x09, 0x01, 0x04, 0xFB, 0x00, 0x00, 0x00, 0x00])
        #expect(PollingProtocol.encode(.hz500) == [0x06, 0x09, 0x01, 0x02, 0xFD, 0x00, 0x00, 0x00, 0x00])
        #expect(PollingProtocol.encode(.hz1000) == [0x06, 0x09, 0x01, 0x01, 0xFE, 0x00, 0x00, 0x00, 0x00])

        for rate in PollingRate.allCases {
            #expect(try PollingProtocol.decode(PollingProtocol.encode(rate)) == rate)
        }
    }

    @Test("Polling decoder rejects malformed reports")
    func pollingDecoderRejectsMalformedReports() throws {
        let valid = PollingProtocol.encode(.hz1000)
        #expect(throws: ProtocolError.self) { try PollingProtocol.decode(Array(valid.dropLast())) }

        var wrongID = valid
        wrongID[0] = 0x05
        #expect(throws: ProtocolError.self) { try PollingProtocol.decode(wrongID) }

        var unknownCode = valid
        unknownCode[3] = 0x03
        #expect(throws: ProtocolError.self) { try PollingProtocol.decode(unknownCode) }
    }

    private func systemReport(debounce: UInt8) -> [UInt8] {
        var report: [UInt8] = [0x05, 0x0F, 0x01, 0x00, 0x03, 0x08, 0x00, 0xFF, 0x00, 0x01, debounce, 0x00, 0x00, 0x00, 0x00]
        let checksum = ProtocolHelper.checksum(data: Array(report[3..<11]))
        report[11] = checksum[0]
        report[12] = checksum[1]
        return report
    }

    @Test("System report keeps every byte except the debounce time")
    func debounceRewrite() throws {
        let original = systemReport(debounce: 4)
        let decoded = try SystemSettingsReport(decoding: original)
        #expect(decoded.debounceMs == 4)

        let rewritten = try decoded.settingDebounce(10)
        #expect(rewritten == systemReport(debounce: 10))
        #expect(try SystemSettingsReport(decoding: rewritten).debounceMs == 10)

        for index in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 14] {
            #expect(rewritten[index] == original[index])
        }
    }

    @Test("System report rejects bad input")
    func systemReportValidation() throws {
        let valid = systemReport(debounce: 4)
        #expect(throws: ProtocolError.self) { try SystemSettingsReport(decoding: Array(valid.dropLast())) }

        var badChecksum = valid
        badChecksum[12] ^= 1
        #expect(throws: ProtocolError.self) { try SystemSettingsReport(decoding: badChecksum) }

        let decoded = try SystemSettingsReport(decoding: valid)
        #expect(throws: ProtocolError.self) { try decoded.settingDebounce(1) }
        #expect(throws: ProtocolError.self) { try decoded.settingDebounce(26) }
    }
}
