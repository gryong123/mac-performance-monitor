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
    private let dragHandleHeight: CGFloat = 64
    private let savedOriginXKey = "desktopPanel.origin.x"
    private let savedOriginYKey = "desktopPanel.origin.y"
    private var panel: DesktopPanel?
    private var observers: [NSObjectProtocol] = []
    private var eventMonitors: [Any] = []
    private var isAdjustingFrame = false
    private var dragStartMouseLocation: CGPoint?
    private var dragStartPanelOrigin: CGPoint?

    private override init() {
        super.init()
        installDragEventMonitors()
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

    func finishDraggingPanel() {
        dragStartMouseLocation = nil
        dragStartPanelOrigin = nil
        keepPanelVisible()
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

    private func installDragEventMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp
        ]

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleDragEvent(event)
            }
            return event
        }) {
            eventMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in
                self?.handleDragEvent(event)
            }
        }) {
            eventMonitors.append(globalMonitor)
        }
    }

    private func handleDragEvent(_ event: NSEvent) {
        guard let panel, panel.isVisible else { return }
        let mouseLocation = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            let dragHandleFrame = CGRect(
                x: panel.frame.minX,
                y: panel.frame.maxY - dragHandleHeight,
                width: panel.frame.width,
                height: dragHandleHeight
            )
            guard dragHandleFrame.contains(mouseLocation) else { return }
            dragStartMouseLocation = mouseLocation
            dragStartPanelOrigin = panel.frame.origin

        case .leftMouseDragged:
            guard let dragStartMouseLocation,
                  let dragStartPanelOrigin else {
                return
            }
            let newOrigin = CGPoint(
                x: dragStartPanelOrigin.x + mouseLocation.x - dragStartMouseLocation.x,
                y: dragStartPanelOrigin.y + mouseLocation.y - dragStartMouseLocation.y
            )
            isAdjustingFrame = true
            panel.setFrameOrigin(newOrigin)
            isAdjustingFrame = false

        case .leftMouseUp:
            guard dragStartMouseLocation != nil else { return }
            finishDraggingPanel()

        default:
            break
        }
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
