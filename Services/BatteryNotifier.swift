// BatteryNotifier.swift
// Delivers the "low battery" alert as a macOS notification (the mouse itself has no such setting).

import Foundation
import UserNotifications

final class BatteryNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BatteryNotifier()

    private let alertID = "x11.lowBattery"
    private let testID = "x11.lowBattery.test"

    private override init() {
        super.init()
        // Without a delegate macOS silently drops notifications while the app is in the foreground,
        // which would make the "Send test alert" button look broken.
        UNUserNotificationCenter.current().delegate = self
    }

    /// Returns true when notifications can be shown.
    /// `prompt: false` only checks (used when the app comes back to the front); `true` also asks the first time.
    func requestAccess(prompt: Bool = true) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            guard prompt else { return true }   // not refused (yet): nothing to warn about
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    func notifyLowBattery(level: Int, isTest: Bool = false) {
        UNUserNotificationCenter.current().add(makeRequest(level: level, isTest: isTest)) { error in
            if let error { print("⚠️ Couldn't show the low battery notification: \(error)") }
        }
    }

    /// Test notification that reports what went wrong (nil = delivered to macOS).
    func postTest(level: Int) async -> String? {
        do {
            try await UNUserNotificationCenter.current().add(makeRequest(level: level, isTest: true))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func makeRequest(level: Int, isTest: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        if isTest {
            content.title = "Test alert"
            content.body = "This is how the low battery alert looks (threshold \(level)%)."
        } else {
            content.title = "Mouse battery low"
            content.body = "Your X11 is at \(level)%. Plug in the cable soon."
        }
        content.sound = .default

        // A fixed identifier replaces the previous alert instead of stacking several.
        return UNNotificationRequest(identifier: isTest ? testID : alertID, content: content, trigger: nil)
    }

    // Show banners even while the app is frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
