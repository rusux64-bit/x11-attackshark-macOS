import Foundation
import IOKit.hid
import SwiftUI

private class EndpointContext {
    weak var scanner: HIDDeviceScanner?
    let device: IOHIDDevice
    let bufferPtr: UnsafeMutablePointer<UInt8>
    let bufferSize: Int = 64
    
    init(scanner: HIDDeviceScanner, device: IOHIDDevice) {
        self.scanner = scanner
        self.device = device
        self.bufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        self.bufferPtr.initialize(repeating: 0, count: bufferSize)
    }
    
    deinit {
        bufferPtr.deallocate()
    }
}

public final class HIDDeviceScanner {
    
    private var hidManager: IOHIDManager?
    private var activeContexts: [EndpointContext] = []
    
    // Callbacks to notify ViewModel
    public var onDeviceConnected: ((String, IOHIDDevice) -> Void)?
    public var onDeviceDisconnected: (() -> Void)?
    public var onInputReport: ((Data, UInt32, IOHIDDevice) -> Void)?
    /// Fired for every single HID endpoint that disappears (cable unplugged, receiver removed...).
    public var onEndpointRemoved: ((IOHIDDevice) -> Void)?
    
    private let targetVendorID: Int = 0x1D57
    private let cableProductID: Int = 0xFA55
    private let receiverProductID: Int = 0xFA60
    
    public init() {}
    
    public func startScanning() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
            print("❌ Failed to create IOHIDManager.")
            return
        }
        
        let matchingCriteria: [[String: Any]] = [
            [kIOHIDVendorIDKey: targetVendorID, kIOHIDProductIDKey: cableProductID],
            [kIOHIDVendorIDKey: targetVendorID, kIOHIDProductIDKey: receiverProductID]
        ]
        
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let scanner = Unmanaged<HIDDeviceScanner>.fromOpaque(context).takeUnretainedValue()
            scanner.attachDevice(device)
        }, selfPointer)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let scanner = Unmanaged<HIDDeviceScanner>.fromOpaque(context).takeUnretainedValue()
            scanner.detachDevice(device)
        }, selfPointer)
        
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue as CFString)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            print("❌ IOHIDManagerOpen failed: 0x" + String(UInt32(bitPattern: openResult), radix: 16))
        } else {
            print("✅ IOHIDManagerOpen OK")
        }

        // Also attach any devices already connected
        if let existingDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for dev in existingDevices {
                attachDevice(dev)
            }
        }
        
        print("🔍 [HIDScanner] Started scanning for ATTACK SHARK X11...")
    }
    
    private func attachDevice(_ device: IOHIDDevice) {
        // Prevent duplicate registration for the exact same device pointer
        if activeContexts.contains(where: { $0.device == device }) {
            return
        }
        
        let productName = getProperty(device, key: kIOHIDProductKey) as? String ?? "ATTACK SHARK X11 Mouse"
        let maxFeature = (getProperty(device, key: "MaxFeatureReportSize") as? Int) ?? 0
        let maxInput = (getProperty(device, key: "MaxInputReportSize") as? Int) ?? 0
        
        print("🟢 Connected endpoint: \(productName) (Feature: \(maxFeature), Input: \(maxInput))")
        let usagePage = getProperty(device, key: kIOHIDPrimaryUsagePageKey) as? Int ?? -1
        print("   usagePage=0x\(String(usagePage, radix: 16))")
        
        
        let context = EndpointContext(scanner: self, device: device)
        activeContexts.append(context)
        let contextPtr = Unmanaged.passUnretained(context).toOpaque()
        
        IOHIDDeviceRegisterInputReportCallback(
            device,
            context.bufferPtr,
            context.bufferSize,
            { ctx, result, sender, type, reportID, report, reportLength in
                guard let ctx = ctx else { return }
                // The mouse sends ~1000 movement reports per second. Only battery heartbeats and DPI events matter,
                // so everything else is dropped here, before allocating or touching the main thread.
                guard HIDDeviceScanner.isRelevantReport(report, length: reportLength, reportID: reportID) else { return }
                let ep = Unmanaged<EndpointContext>.fromOpaque(ctx).takeUnretainedValue()
                let data = Data(bytes: report, count: reportLength)
                ep.scanner?.handleInputReport(data: data, reportID: reportID, device: ep.device)
            },
            contextPtr
        )
        
        DispatchQueue.main.async {
            self.onDeviceConnected?(productName, device)
        }
    }
    
    private func handleInputReport(data: Data, reportID: UInt32, device: IOHIDDevice) {
        // Already running on the main run loop (the manager is scheduled on it): no extra hop needed.
        onInputReport?(data, reportID, device)
    }

    /// Cheap pre-filter, same layouts the view model parses: `03 55 <event> ...` (battery) or `03 <model> <evDPI> ...`.
    /// The report ID byte may or may not be part of the buffer.
    private static func isRelevantReport(_ report: UnsafePointer<UInt8>, length: Int, reportID: UInt32) -> Bool {
        guard length >= 4 else { return false }
        if report[0] == 0x03 {
            return report[1] == 0x55 || report[2] == ProtocolConstants.evDPI
        }
        return report[0] == 0x55 || (reportID == 0x03 && report[1] == ProtocolConstants.evDPI)
    }
    
    private func detachDevice(_ device: IOHIDDevice) {
        activeContexts.removeAll(where: { $0.device == device })
        print("🔴 Disconnected endpoint. Remaining: \(activeContexts.count)")
        DispatchQueue.main.async { self.onEndpointRemoved?(device) }
        
        if activeContexts.isEmpty {
            DispatchQueue.main.async {
                self.onDeviceDisconnected?()
            }
        }
    }
    
    private func getProperty(_ device: IOHIDDevice, key: String) -> AnyObject? {
        let value = IOHIDDeviceGetProperty(device, key as CFString)
        return value as AnyObject?
    }
    
    deinit {
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue as CFString)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}


