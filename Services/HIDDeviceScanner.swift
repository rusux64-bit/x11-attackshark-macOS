import Foundation
import IOKit.hid
import SwiftUI

public final class HIDDeviceScanner {
    
    private var hidManager: IOHIDManager?
    
    // Callbacks to notify ViewModel
    public var onDeviceConnected: ((String, IOHIDDevice) -> Void)?
    public var onDeviceDisconnected: (() -> Void)?
    
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
            let scanner = Unmanaged<HIDDeviceScanner>.fromOpaque(context!).takeUnretainedValue()
            scanner.deviceConnected(device)
        }, selfPointer)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            let scanner = Unmanaged<HIDDeviceScanner>.fromOpaque(context!).takeUnretainedValue()
            scanner.deviceDisconnected(device)
        }, selfPointer)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue as CFString)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        print("🔍 [HIDScanner] Started scanning for ATTACK SHARK X11...")
    }
    
    private func deviceConnected(_ device: IOHIDDevice) {
        let productName = getProperty(device, key: kIOHIDProductKey) as? String ?? "ATTACK SHARK X11 Mouse"
        print("🟢 Connected: \(productName)")
        
        DispatchQueue.main.async {
            self.onDeviceConnected?(productName, device)
        }
    }
    
    private func deviceDisconnected(_ device: IOHIDDevice) {
        print("🔴 Disconnected")
        DispatchQueue.main.async {
            self.onDeviceDisconnected?()
        }
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
