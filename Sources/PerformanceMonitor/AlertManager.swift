import Foundation
import UserNotifications

@MainActor
final class AlertManager {
    private var consecutiveHighSamples = 0
    private var lastNotificationDate: Date?
    private(set) var level: HealthLevel = .normal

    func requestAuthorization() {
        guard RuntimeEnvironment.isAppBundle else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    func evaluate(snapshot: MetricSnapshot, thresholds: AlertThresholds) -> HealthLevel {
        let values = [
            snapshot.cpuPercent / thresholds.cpu,
            snapshot.memoryPercent / thresholds.memory,
            snapshot.diskPercent / thresholds.disk
        ]
        let highest = values.max() ?? 0

        if highest >= 1 {
            consecutiveHighSamples += 1
        } else {
            consecutiveHighSamples = 0
        }

        if consecutiveHighSamples >= 3 {
            level = .critical
            sendNotificationIfNeeded(snapshot: snapshot)
        } else if highest >= 0.8 {
            level = .warning
        } else {
            level = .normal
        }

        return level
    }

    private func sendNotificationIfNeeded(snapshot: MetricSnapshot) {
        guard RuntimeEnvironment.isAppBundle else { return }
        if let lastNotificationDate,
           Date().timeIntervalSince(lastNotificationDate) < 15 * 60 {
            return
        }

        lastNotificationDate = Date()
        let content = UNMutableNotificationContent()
        content.title = "电脑负载持续偏高"
        content.body = String(
            format: "CPU %.0f%% · 内存 %.0f%% · 磁盘 %.0f%%",
            snapshot.cpuPercent,
            snapshot.memoryPercent,
            snapshot.diskPercent
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "performance-high-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
