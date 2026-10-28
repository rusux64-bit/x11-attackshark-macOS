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
