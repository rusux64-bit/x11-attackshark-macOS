// WindowResizeMonitor.swift
// Tells SwiftUI when the app window is being resized, so heavy pages (the DPI tab) can stop re-laying-out
// on every frame and do one real layout when the resize ends.

import AppKit
import Combine

/// `isResizing` flips to true when a resize starts and back to false shortly after it ends.
/// It changes only twice per resize, so observing it never costs a SwiftUI update per frame.
///
/// Two sources are combined:
/// - live resize notifications (dragging a corner / edge): exact start and end;
/// - plain `didResize` notifications, debounced: covers the zoom button, full screen, tiling and
///   programmatic resizes, which never send the live-resize notifications.
final class WindowResizeMonitor: ObservableObject {
    @Published private(set) var isResizing = false

    private var observers: [NSObjectProtocol] = []
    private var endWork: DispatchWorkItem?
    /// How long the window must stay still before a non-live resize (zoom, full screen...) counts as finished.
    private static let settleDelay: TimeInterval = 0.18

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: NSWindow.willStartLiveResizeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, Self.isTracked(window) else { return }
            self.begin()
        })
        observers.append(center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, Self.isTracked(window) else { return }
            self.scheduleEnd(after: 0.05)
        })
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, Self.isTracked(window) else { return }
            self.begin()
            self.scheduleEnd(after: Self.settleDelay)
        })
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        endWork?.cancel()
        endWork = nil
        if isResizing { isResizing = false }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        endWork?.cancel()
    }

    /// Only the app's real windows count: not the colour panel, popovers or other panels.
    private static func isTracked(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.canBecomeMain
    }

    private func begin() {
        endWork?.cancel()
        endWork = nil
        if !isResizing { isResizing = true }
    }

    private func scheduleEnd(after delay: TimeInterval) {
        endWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.endWork = nil
            if self.isResizing { self.isResizing = false }
        }
        endWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
