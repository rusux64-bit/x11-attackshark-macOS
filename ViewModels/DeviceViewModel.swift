import Foundation
import SwiftUI
import Combine
import IOKit.hid

public final class DeviceViewModel: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var deviceName: String = "No device connected"

    private let scanner = HIDDeviceScanner()
    private var transport: DeviceTransport?

    public init() {
        setupScanner()
    }

    private func setupScanner() {
        scanner.onDeviceConnected = { [weak self] name, device in
            guard let self = self else { return }
            self.isConnected = true
            self.deviceName = name
            self.transport = DeviceTransport(hidDevice: device)
        }

        scanner.onDeviceDisconnected = { [weak self] in
            guard let self = self else { return }
            self.isConnected = false
            self.deviceName = "No device connected"
            self.transport = nil
        }

        scanner.startScanning()
    }
}
