import AppKit
import SwiftUI

@main
struct PerformanceMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MetricsStore.shared

    var body: some Scene {
        MenuBarExtra("性能监测", systemImage: "gauge.with.dots.needle.50percent") {
            Button(store.isPanelVisible ? "隐藏桌面面板" : "显示桌面面板") {
                DesktopWindowController.shared.toggle(store: store)
            }

            Divider()

            SettingsLink {
                Text("设置…")
            }

            Button("立即刷新") {
                Task { await store.refresh() }
            }
            .keyboardShortcut("r")

            Divider()

            Button("退出性能监测") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DesktopWindowController.shared.show(store: MetricsStore.shared)
        MetricsStore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MetricsStore.shared.stop()
    }
}
