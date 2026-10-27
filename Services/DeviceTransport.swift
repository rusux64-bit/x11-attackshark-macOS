import Foundation
import IOKit.hid

public final class DeviceTransport {
    private let hidDevice: IOHIDDevice
    
    public init(hidDevice: IOHIDDevice) {
        self.hidDevice = hidDevice
    }
    
    /// Sends a feature report to the mouse (e.g., changing DPI, polling rate, or lighting)
    public func sendFeatureReport(reportID: UInt8, data: [UInt8]) -> Bool {
        var reportBytes = data
        let result = reportBytes.withUnsafeMutableBytes { buffer -> IOReturn in
            guard let baseAddress = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(
                hidDevice,
                kIOHIDReportTypeFeature, // Corectat aici
                CFIndex(reportID),
                baseAddress,
                buffer.count
            )
        }
        
        if result != kIOReturnSuccess {
            print("❌ Failed to send feature report ID 0x\(String(format: "%02X", reportID)): \(result)")
            return false
        }
        return true
    }
    
    /// Reads a feature report from the mouse (e.g., battery level, current DPI, status)
    public func getFeatureReport(reportID: UInt8, length: Int) -> Data? {
        var reportData = [UInt8](repeating: 0, count: length)
        var reportLength = CFIndex(length)
        
        let result = reportData.withUnsafeMutableBytes { buffer -> IOReturn in
            guard let baseAddress = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceGetReport(
                hidDevice,
                kIOHIDReportTypeFeature, // Corectat și aici
                CFIndex(reportID),
                baseAddress,
                &reportLength
            )
        }
        
        if result != kIOReturnSuccess {
            print("⚠️ Failed to get feature report ID 0x\(String(format: "%02X", reportID))")
            return nil
        }
        
        return Data(reportData.prefix(reportLength))
    }
}
