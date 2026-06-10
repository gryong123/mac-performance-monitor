import AppKit
import SwiftUI

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopWindowController {
    static let shared = DesktopWindowController()

    private let panelSize = CGSize(width: 360, height: 620)
    private var panel: DesktopPanel?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.reposition() }
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.reposition() }
            }
        )
    }

    func show(store: MetricsStore) {
        if panel == nil {
            panel = makePanel(store: store)
        }
        reposition()
        panel?.orderFrontRegardless()
        store.isPanelVisible = true
    }

    func hide(store: MetricsStore) {
        panel?.orderOut(nil)
        store.isPanelVisible = false
    }

    func toggle(store: MetricsStore) {
        store.isPanelVisible ? hide(store: store) : show(store: store)
    }

    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel?.setFrame(
            DesktopPosition.frame(visibleFrame: screen.visibleFrame, panelSize: panelSize),
            display: true
        )
    }

    private func makePanel(store: MetricsStore) -> DesktopPanel {
        let panel = DesktopPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1
        )
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.contentViewController = NSHostingController(
            rootView: DashboardView(store: store)
        )
        return panel
    }
}
