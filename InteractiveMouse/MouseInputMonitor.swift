import Foundation
import SwiftUI
import Combine
import AppKit

public enum MouseButtonType: String, CaseIterable, Identifiable {
    case left = "Left Click"
    case right = "Right Click"
    case middle = "Middle Click"
    case forward = "Forward"
    case back = "Back"
    case scrollUp = "Scroll Up"
    case scrollDown = "Scroll Down"
    
    public var id: String { rawValue }
}

public final class MouseInputMonitor: ObservableObject {
    @Published public var activeButtons: Set<MouseButtonType> = []
    @Published public var lastEventType: String = "None"
    
    private var localMonitor: Any?
    private var scrollWorkItem: DispatchWorkItem?
    
    deinit {
        stopMonitoring()
    }
    
    public func simulateClick(_ button: MouseButtonType) {
        lastEventType = "Simulated: \(button.rawValue)"
        activeButtons.insert(button)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.activeButtons.remove(button)
        }
    }
    
    public func startMonitoring() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }
    }
    
    public func stopMonitoring() {
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        scrollWorkItem?.cancel()
        scrollWorkItem = nil
        activeButtons.removeAll()
    }
    
    private func handleNSEvent(_ event: NSEvent) {
        if event.type == .scrollWheel {
            let deltaY = event.deltaY
            if deltaY > 0 {
                triggerScroll(.scrollUp)
            } else if deltaY < 0 {
                triggerScroll(.scrollDown)
            }
            return
        }
        
        let isDown = (event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown)
        
        switch event.buttonNumber {
        case 0: updateState(.left, isDown: isDown)
        case 1: updateState(.right, isDown: isDown)
        case 2: updateState(.middle, isDown: isDown)
        case 3: updateState(.back, isDown: isDown)
        case 4: updateState(.forward, isDown: isDown)
        default: break
        }
    }
    
    private func triggerScroll(_ type: MouseButtonType) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeButtons.insert(type)
            
            self.scrollWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.activeButtons.remove(.scrollUp)
                self?.activeButtons.remove(.scrollDown)
            }
            self.scrollWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }
    }
    
    private func updateState(_ button: MouseButtonType, isDown: Bool) {
        if isDown {
            activeButtons.insert(button)
        } else {
            activeButtons.remove(button)
        }
    }
}
