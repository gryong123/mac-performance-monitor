import Foundation

struct ProcessUsage: Identifiable, Sendable, Equatable {
    let id: Int32
    let name: String
    let cpuPercent: Double
    let memoryMB: Double
}

enum ProcessSortMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "内存"

    var id: String { rawValue }

    func sorted(_ processes: [ProcessUsage]) -> [ProcessUsage] {
        processes.sorted { first, second in
            switch self {
            case .cpu:
                if first.cpuPercent == second.cpuPercent {
                    return first.memoryMB > second.memoryMB
                }
                return first.cpuPercent > second.cpuPercent
            case .memory:
                if first.memoryMB == second.memoryMB {
                    return first.cpuPercent > second.cpuPercent
                }
                return first.memoryMB > second.memoryMB
            }
        }
    }
}

struct MetricSnapshot: Sendable, Equatable {
    var timestamp: Date
    var cpuPercent: Double
    var gpuPercent: Double?
    var memoryPercent: Double
    var memoryUsedGB: Double
    var memoryTotalGB: Double
    var diskPercent: Double
    var diskUsedGB: Double
    var diskTotalGB: Double
    var networkDownloadBytesPerSecond: Double
    var networkUploadBytesPerSecond: Double
    var temperatureCelsius: Double?
    var fanRPM: Double?
    var batteryPercent: Double?
    var isCharging: Bool?
    var topProcesses: [ProcessUsage]

    static let empty = MetricSnapshot(
        timestamp: .now,
        cpuPercent: 0,
        gpuPercent: nil,
        memoryPercent: 0,
        memoryUsedGB: 0,
        memoryTotalGB: 0,
        diskPercent: 0,
        diskUsedGB: 0,
        diskTotalGB: 0,
        networkDownloadBytesPerSecond: 0,
        networkUploadBytesPerSecond: 0,
        temperatureCelsius: nil,
        fanRPM: nil,
        batteryPercent: nil,
        isCharging: nil,
        topProcesses: []
    )
}

struct HistoricalSample: Identifiable, Sendable {
    let timestamp: Date
    let cpuPercent: Double
    let memoryPercent: Double

    var id: Date { timestamp }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case hour = "1小时"
    case day = "24小时"
    case week = "7天"

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .hour: 60 * 60
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        }
    }
}

enum HealthLevel: String {
    case normal = "正常"
    case warning = "注意"
    case critical = "过高"
}

struct AlertThresholds: Equatable {
    var cpu: Double
    var memory: Double
    var disk: Double

    static let defaults = AlertThresholds(cpu: 85, memory: 90, disk: 90)
}

enum DesktopPosition {
    static let panelSize = CGSize(width: 360, height: 684)

    static func frame(
        visibleFrame: CGRect,
        panelSize: CGSize = panelSize,
        margin: CGFloat = 16
    ) -> CGRect {
        CGRect(
            x: visibleFrame.minX + margin,
            y: visibleFrame.minY + margin,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    static func constrainedFrame(_ frame: CGRect, within visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - height)

        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), maximumX),
            y: min(max(frame.minY, visibleFrame.minY), maximumY),
            width: width,
            height: height
        )
    }

    static func originKeepingTop(
        origin: CGPoint,
        previousHeight: CGFloat,
        newHeight: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: origin.x,
            y: origin.y + previousHeight - newHeight
        )
    }
}
