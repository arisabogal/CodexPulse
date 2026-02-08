import Foundation
import UserNotifications

actor UsageAlertService {
    static let shared = UsageAlertService()

    private static let sentNotificationKeysDefaultsKey = "usage_alerts.sent_notification_keys"

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let thresholds: [Double] = [50, 25, 10]

    private var authorizationChecked = false
    private var notificationsEnabled = false
    private var sentKeys: Set<String>

    init() {
        sentKeys = Set(defaults.stringArray(forKey: Self.sentNotificationKeysDefaultsKey) ?? [])
    }

    func evaluate(rateLimitSnapshots: [RateLimitSnapshot]) async {
        await ensureAuthorizationIfNeeded()
        guard notificationsEnabled else { return }

        evaluateRateLimitThresholds(rateLimitSnapshots)
    }

    private func evaluateRateLimitThresholds(_ snapshots: [RateLimitSnapshot]) {
        for snapshot in snapshots {
            let remaining = max(0, min(100, snapshot.remainingPercent))
            for threshold in thresholds where remaining <= threshold {
                let key = "rate-\(snapshot.windowKind.rawValue)-\(Int(snapshot.resetsAt.timeIntervalSince1970))-\(Int(threshold))"
                guard !sentKeys.contains(key) else { continue }

                let title = "\(snapshotTitle(snapshot.windowKind)) low"
                let body = "\(Int(remaining.rounded()))% remaining. Resets at \(snapshot.resetsAt.formatted(date: .omitted, time: .shortened))."
                sendNotification(id: key, title: title, body: body)
                rememberSent(key)
            }
        }
    }

    private func snapshotTitle(_ kind: RateLimitWindowKind) -> String {
        switch kind {
        case .fiveHour:
            return "5-hour window"
        case .weekly:
            return "Weekly window"
        }
    }

    private func sendNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }

    private func rememberSent(_ key: String) {
        sentKeys.insert(key)
        defaults.set(Array(sentKeys), forKey: Self.sentNotificationKeysDefaultsKey)
    }

    private func ensureAuthorizationIfNeeded() async {
        guard !authorizationChecked else { return }
        authorizationChecked = true

        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsEnabled = true
        case .notDetermined:
            notificationsEnabled = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            notificationsEnabled = false
        @unknown default:
            notificationsEnabled = false
        }
    }
}
