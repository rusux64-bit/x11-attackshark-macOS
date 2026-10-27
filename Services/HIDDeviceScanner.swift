import Foundation
import IOKit.hid
import SwiftUI

public final class HIDDeviceScanner {
    
    private var hidManager: IOHIDManager?
    private var activeTransport: DeviceTransport?
    
    // ATTACK SHARK X11 Hardware Constants
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
        
        // Set multiple matching criteria strictly for the X11 mouse (Cable & Receiver)
        let matchingCriteria: [[String: Any]] = [
            [
                kIOHIDVendorIDKey: targetVendorID,
                kIOHIDProductIDKey: cableProductID
            ],
            [
                kIOHIDVendorIDKey: targetVendorID,
                kIOHIDProductIDKey: receiverProductID
            ]
        ]
        
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            let scanner = Unmanaged<HIDDeviceScanner>.fromOpaque(context!).takeUnretainedValue()
            scanner.deviceConnected(device)
        }, selfPointer)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            let scanner = Unmanaged<HIDDeviceScanner>.fromOpaque(context!).takeUnretainedValue()
            scanner.deviceDisconnected(device)
        }, selfPointer)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue as CFString)
        
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if openResult == kIOReturnSuccess {
            print("🔍 [HIDScanner] Started - listening strictly for ATTACK SHARK X11 (Cable & Receiver)...")
        } else {
            print("⚠️ IOHIDManager open warning: \(openResult)")
        }
    }
    
    private func deviceConnected(_ device: IOHIDDevice) {
        let vendorID = getProperty(device, key: kIOHIDVendorIDKey) as? Int ?? 0
        let productID = getProperty(device, key: kIOHIDProductIDKey) as? Int ?? 0
        let productName = getProperty(device, key: kIOHIDProductKey) as? String ?? "Unknown Device"
        
        print("🟢 ATTACK SHARK X11 Connected -> Name: \(productName) | VID: 0x\(String(vendorID, radix: 16)) | PID: 0x\(String(productID, radix: 16))")
        
        // Initialize transport layer for this device
        let transport = DeviceTransport(hidDevice: device)
        self.activeTransport = transport
        
        // Test command interface
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            print("🔍 Attempting to communicate with X11...")
            if let data = transport.getFeatureReport(reportID: 0x0B, length: 8) {
                print("✨ Success! Read data from mouse: \(data as NSData)")
            } else {
                print("ℹ️ Active input interface for X11.")
            }
        }
    }
    
    private func deviceDisconnected(_ device: IOHIDDevice) {
        let productName = getProperty(device, key: kIOHIDProductKey) as? String ?? "Unknown Device"
        print("🔴 ATTACK SHARK X11 Disconnected: \(productName)")
        self.activeTransport = nil
    }
    
    private func getProperty(_ device: IOHIDDevice, key: String) -> AnyObject? {
        let value = IOHIDDeviceGetProperty(device, key as CFString)
        return value as AnyObject?
    }
    
    deinit {
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue as CFString)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}
