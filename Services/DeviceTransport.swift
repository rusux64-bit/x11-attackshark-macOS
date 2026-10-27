import Foundation
import IOKit.hid

public final class DeviceTransport {
    private let hidDevice: IOHIDDevice
    
    public init(hidDevice: IOHIDDevice) {
        self.hidDevice = hidDevice
    }
    
    /// Sends a HID feature report to the device.
    public func setFeatureReport(reportID: UInt8, data: Data) -> Bool {
        let bytes = [UInt8](data)
        let result = bytes.withUnsafeBytes { ptr -> IOReturn in
            guard let baseAddress = ptr.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(
                hidDevice,
                kIOHIDReportTypeFeature,
                CFIndex(reportID),
                baseAddress.assumingMemoryBound(to: UInt8.self),
                bytes.count
            )
        }
        return result == kIOReturnSuccess
    }
    
    /// Reads a HID feature report from the device.
    public func getFeatureReport(reportID: UInt8, length: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: length)
        var reportLength = CFIndex(length)
        
        let result = buffer.withUnsafeMutableBytes { ptr -> IOReturn in
            guard let baseAddress = ptr.baseAddress else { return kIOReturnError }
            return IOHIDDeviceGetReport(
                hidDevice,
                kIOHIDReportTypeFeature,
                CFIndex(reportID),
                baseAddress.assumingMemoryBound(to: UInt8.self),
                &reportLength
            )
        }
        
        guard result == kIOReturnSuccess else { return nil }
        return Data(buffer.prefix(reportLength))
    }
}
