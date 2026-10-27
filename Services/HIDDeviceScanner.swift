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
    private var endpointContexts: [IOHIDDevice: EndpointContext] = [:]
    
    // Callbacks to notify ViewModel
    public var onDeviceConnected: ((String, IOHIDDevice) -> Void)?
    public var onDeviceDisconnected: (() -> Void)?
    public var onInputReport: ((Data, UInt32, IOHIDDevice) -> Void)?
    
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
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        // Also attach any matching devices already plugged in
        if let existingDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for dev in existingDevices {
                attachDevice(dev)
            }
        }
        
        print("🔍 [HIDScanner] Started scanning for ATTACK SHARK X11...")
    }
    
    private func attachDevice(_ device: IOHIDDevice) {
        guard endpointContexts[device] == nil else { return }
        
        let productName = getProperty(device, key: kIOHIDProductKey) as? String ?? "ATTACK SHARK X11 Mouse"
        let maxFeature = (getProperty(device, key: "MaxFeatureReportSize") as? Int) ?? 0
        let maxInput = (getProperty(device, key: "MaxInputReportSize") as? Int) ?? 0
        print("🟢 Connected endpoint: \(productName) (Feature: \(maxFeature), Input: \(maxInput))")
        
        let context = EndpointContext(scanner: self, device: device)
        endpointContexts[device] = context
        let contextPtr = Unmanaged.passUnretained(context).toOpaque()
        
        IOHIDDeviceRegisterInputReportCallback(
            device,
            context.bufferPtr,
            context.bufferSize,
            { ctx, result, sender, type, reportID, report, reportLength in
                guard let ctx = ctx else { return }
                let ep = Unmanaged<EndpointContext>.fromOpaque(ctx).takeUnretainedValue()
                let data = Data(bytes: report, count: reportLength)
                ep.scanner?.handleInputReport(data: data, reportID: reportID, device: ep.device)
            },
            contextPtr
        )
        
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
        
        DispatchQueue.main.async {
            self.onDeviceConnected?(productName, device)
        }
    }
    
    private func handleInputReport(data: Data, reportID: UInt32, device: IOHIDDevice) {
        DispatchQueue.main.async {
            self.onInputReport?(data, reportID, device)
        }
    }
    
    private func detachDevice(_ device: IOHIDDevice) {
        endpointContexts.removeValue(forKey: device)
        print("🔴 Disconnected endpoint. Remaining: \(endpointContexts.count)")
        
        if endpointContexts.isEmpty {
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
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}
