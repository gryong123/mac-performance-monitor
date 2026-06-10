import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: MetricsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accentColor: Color {
        switch store.healthLevel {
        case .normal: .mint
        case .warning: .orange
        case .critical: .red
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            header

            HStack(spacing: 8) {
                MetricTile(
                    title: "CPU",
                    value: percent(store.snapshot.cpuPercent),
                    detail: metricStatus(
                        value: store.snapshot.cpuPercent,
                        threshold: store.thresholds.cpu
                    ),
                    icon: "cpu",
                    tint: accentColor,
                    progress: store.snapshot.cpuPercent / 100
                )
                MetricTile(
                    title: "内存",
                    value: percent(store.snapshot.memoryPercent),
                    detail: String(
                        format: "%.1f / %.1f GB",
                        store.snapshot.memoryUsedGB,
                        store.snapshot.memoryTotalGB
                    ),
                    icon: "memorychip",
                    tint: .blue,
                    progress: store.snapshot.memoryPercent / 100
                )
            }

            historyCard

            HStack(spacing: 8) {
                CompactMetric(
                    title: "磁盘",
                    value: percent(store.snapshot.diskPercent),
                    detail: String(format: "%.0f GB 可用", max(0, store.snapshot.diskTotalGB - store.snapshot.diskUsedGB)),
                    icon: "internaldrive"
                )
                CompactMetric(
                    title: "电池",
                    value: optionalPercent(store.snapshot.batteryPercent),
                    detail: batteryDetail,
                    icon: "battery.75percent"
                )
            }

            networkCard
            sensorCard
            processCard
        }
        .padding(12)
        .frame(
            width: DesktopPosition.panelSize.width,
            height: DesktopPosition.panelSize.height,
            alignment: .top
        )
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accentColor.opacity(store.healthLevel == .normal ? 0.22 : 0.75), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.healthLevel.rawValue)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("电脑性能监测面板")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("性能监测")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(store.snapshot.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
                Text(store.healthLevel.rawValue)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(accentColor.opacity(0.13), in: Capsule())
            .accessibilityLabel("设备状态：\(store.healthLevel.rawValue)")
        }
        .contentShape(Rectangle())
        .accessibilityHint("按住标题区域可移动监测面板")
    }

    private var historyCard: some View {
        VStack(spacing: 6) {
            HStack {
                Label("负载趋势", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.semibold))
                Spacer()
                Picker("趋势时间范围", selection: $store.historyRange) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 176)
            }

            Chart {
                ForEach(store.history) { sample in
                    LineMark(
                        x: .value("时间", sample.timestamp),
                        y: .value("CPU", sample.cpuPercent)
                    )
                    .foregroundStyle(by: .value("指标", "CPU"))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("时间", sample.timestamp),
                        y: .value("内存", sample.memoryPercent)
                    )
                    .foregroundStyle(by: .value("指标", "内存"))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: 0...100)
            .chartForegroundStyleScale([
                "CPU": Color.mint,
                "内存": Color.blue
            ])
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) {
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
            .frame(height: 92)
            .overlay {
                if store.history.isEmpty {
                    Text("正在积累趋势数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("CPU 与内存历史趋势")
        }
        .cardStyle()
    }

    private var networkCard: some View {
        HStack(spacing: 12) {
            Label("网络", systemImage: "network")
                .font(.caption.weight(.semibold))
                .frame(width: 58, alignment: .leading)
            RateLabel(
                label: "下载",
                systemImage: "arrow.down",
                value: byteRate(store.snapshot.networkDownloadBytesPerSecond),
                tint: .cyan
            )
            RateLabel(
                label: "上传",
                systemImage: "arrow.up",
                value: byteRate(store.snapshot.networkUploadBytesPerSecond),
                tint: .purple
            )
        }
        .cardStyle()
    }

    private var sensorCard: some View {
        HStack(spacing: 10) {
            SensorItem(
                title: "GPU",
                value: optionalPercent(store.snapshot.gpuPercent),
                icon: "rectangle.3.group",
                unavailable: store.snapshot.gpuPercent == nil
            )
            Divider().frame(height: 28)
            SensorItem(
                title: "温度",
                value: store.snapshot.temperatureCelsius.map { String(format: "%.0f℃", $0) } ?? "暂不可用",
                icon: "thermometer.medium",
                unavailable: store.snapshot.temperatureCelsius == nil
            )
            Divider().frame(height: 28)
            SensorItem(
                title: "风扇",
                value: store.snapshot.fanRPM.map { String(format: "%.0f RPM", $0) } ?? "暂不可用",
                icon: "fan",
                unavailable: store.snapshot.fanRPM == nil
            )
        }
        .cardStyle()
    }

    private var processCard: some View {
        VStack(spacing: 5) {
            HStack {
                Label("高占用进程", systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Picker("进程排序方式", selection: $store.processSortMetric) {
                    ForEach(ProcessSortMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 108)
            }

            if store.snapshot.topProcesses.isEmpty {
                Text("暂无进程数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54)
            } else {
                ForEach(displayedProcesses) { process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f%%", process.cpuPercent))
                            .foregroundStyle(
                                store.processSortMetric == .cpu ? .primary : .secondary
                            )
                            .frame(width: 48, alignment: .trailing)
                        Text(String(format: "%.0f MB", process.memoryMB))
                            .foregroundStyle(
                                store.processSortMetric == .memory ? .primary : .secondary
                            )
                            .frame(width: 58, alignment: .trailing)
                    }
                    .fontDesign(.monospaced)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .cardStyle()
    }

    private var displayedProcesses: [ProcessUsage] {
        Array(
            store.processSortMetric
                .sorted(store.snapshot.topProcesses)
                .prefix(6)
        )
    }

    private var batteryDetail: String {
        guard let isCharging = store.snapshot.isCharging else { return "无电池数据" }
        return isCharging ? "电源已连接" : "正在使用电池"
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    private func optionalPercent(_ value: Double?) -> String {
        value.map(percent) ?? "暂不可用"
    }

    private func byteRate(_ value: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(value)))/s"
    }

    private func metricStatus(value: Double, threshold: Double) -> String {
        if value >= threshold { return "超过告警阈值" }
        if value >= threshold * 0.8 { return "接近告警阈值" }
        return "运行正常"
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(tint)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(value)，\(detail)")
    }
}

private struct CompactMetric: View {
    let title: String
    let value: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

private struct RateLabel: View {
    let label: String
    let systemImage: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SensorItem: View {
    let title: String
    let value: String
    let icon: String
    let unavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(unavailable ? .secondary : .primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
