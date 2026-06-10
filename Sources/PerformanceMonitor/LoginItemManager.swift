import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var message: String?

    private init() {
        refresh()
    }

    func refresh() {
        guard RuntimeEnvironment.isAppBundle else {
            isEnabled = false
            message = "开发运行模式不支持登录启动，请先生成本地 .app。"
            return
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        guard RuntimeEnvironment.isAppBundle else {
            message = "开发运行模式不支持登录启动，请先生成本地 .app。"
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            message = nil
        } catch {
            message = "登录启动设置失败：\(error.localizedDescription)"
        }
        refresh()
    }
}
