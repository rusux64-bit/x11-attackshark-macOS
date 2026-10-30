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
