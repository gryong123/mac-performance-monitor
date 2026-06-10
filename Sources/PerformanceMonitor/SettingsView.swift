import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MetricsStore
    @StateObject private var loginItem = LoginItemManager.shared

    var body: some View {
        Form {
            Section("告警阈值") {
                thresholdRow(title: "CPU", value: cpuBinding)
                thresholdRow(title: "内存", value: memoryBinding)
                thresholdRow(title: "磁盘", value: diskBinding)
                Text("指标连续 3 次超过阈值后提醒，通知冷却时间为 15 分钟。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("启动") {
                Toggle(
                    "登录 Mac 后自动启动",
                    isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    )
                )

                if let message = loginItem.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("传感器权限") {
                Label("GPU、温度与风扇当前使用安全降级模式", systemImage: "lock.shield")
                Text("未安装管理员辅助程序，应用不会读取或修改 SMC。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 410)
        .padding()
        .onAppear { loginItem.refresh() }
    }

    private func thresholdRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: 50...100, step: 1)
            Text("\(Int(value.wrappedValue))%")
                .fontDesign(.monospaced)
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)告警阈值 \(Int(value.wrappedValue))%")
    }

    private var cpuBinding: Binding<Double> {
        Binding(
            get: { store.thresholds.cpu },
            set: { store.thresholds.cpu = $0 }
        )
    }

    private var memoryBinding: Binding<Double> {
        Binding(
            get: { store.thresholds.memory },
            set: { store.thresholds.memory = $0 }
        )
    }

    private var diskBinding: Binding<Double> {
        Binding(
            get: { store.thresholds.disk },
            set: { store.thresholds.disk = $0 }
        )
    }
}
