import AppKit
import SwiftUI

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopWindowController: NSObject, NSWindowDelegate {
    static let shared = DesktopWindowController()

    private let panelSize = CGSize(width: 360, height: 620)
    private let savedOriginXKey = "desktopPanel.origin.x"
    private let savedOriginYKey = "desktopPanel.origin.y"
    private var panel: DesktopPanel?
    private var observers: [NSObjectProtocol] = []
    private var isAdjustingFrame = false

    private override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.keepPanelVisible() }
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.keepPanelVisible() }
            }
        )
    }

    func show(store: MetricsStore) {
        if panel == nil {
            panel = makePanel(store: store)
        }
        restorePosition()
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

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame, let panel else { return }
        save(origin: panel.frame.origin)
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
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.delegate = self
        panel.minSize = panelSize
        panel.maxSize = panelSize
        panel.contentViewController = NSHostingController(
            rootView: DashboardView(store: store)
        )
        return panel
    }

    private func restorePosition() {
        guard panel != nil,
              let fallbackScreen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let defaults = UserDefaults.standard
        let hasSavedOrigin = defaults.object(forKey: savedOriginXKey) != nil &&
            defaults.object(forKey: savedOriginYKey) != nil

        let proposedFrame: CGRect
        if hasSavedOrigin {
            proposedFrame = CGRect(
                origin: CGPoint(
                    x: defaults.double(forKey: savedOriginXKey),
                    y: defaults.double(forKey: savedOriginYKey)
                ),
                size: panelSize
            )
        } else {
            proposedFrame = DesktopPosition.frame(
                visibleFrame: fallbackScreen.visibleFrame,
                panelSize: panelSize
            )
        }

        setVisibleFrame(proposedFrame)
    }

    private func keepPanelVisible() {
        guard let panel else { return }
        setVisibleFrame(panel.frame)
    }

    private func setVisibleFrame(_ proposedFrame: CGRect) {
        guard let panel,
              let fallbackScreen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let targetScreen = NSScreen.screens.max {
            intersectionArea(proposedFrame, $0.visibleFrame) <
                intersectionArea(proposedFrame, $1.visibleFrame)
        } ?? fallbackScreen
        let visibleFrame = DesktopPosition.constrainedFrame(
            proposedFrame,
            within: targetScreen.visibleFrame
        )

        isAdjustingFrame = true
        panel.setFrame(visibleFrame, display: true)
        isAdjustingFrame = false
        save(origin: visibleFrame.origin)
    }

    private func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func save(origin: CGPoint) {
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: savedOriginXKey)
        defaults.set(origin.y, forKey: savedOriginYKey)
    }
}
