import AppKit
import SwiftUI

@main
struct AgentMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AgentMeterModel.shared

    var body: some Scene {
        MenuBarExtra {
            AgentMeterPanel(model: model)
                .frame(width: 416, height: min(560, max(300, (NSScreen.main?.visibleFrame.height ?? 700) - 24)))
        } label: {
            Image(
                nsImage: Self.menuBarIcon(
                    visualState: model.menuBarVisualState
                )
            )
            .accessibilityLabel(Self.accessibilityLabel(for: model.menuBarVisualState, language: model.language))
            .help(model.menuTitle())
        }
        .menuBarExtraStyle(.window)
    }

    private static func accessibilityLabel(for state: MenuBarVisualState, language: AppLanguage) -> String {
        let en = language == .english
        switch state {
        case .needsInput(let count):
            return en ? "Agent Activity (\(count) waiting for confirmation)" : "Agent 动态（\(count) 个会话等待确认）"
        case .unreadCompleted(let count):
            return en ? "Agent Activity (\(count) newly completed)" : "Agent 动态（\(count) 个新完成的任务）"
        case .working(let count):
            return en ? "Agent Activity (\(count) running)" : "Agent 动态（\(count) 个任务运行中）"
        case .idle(let online):
            if en {
                return online > 0 ? "Agent Activity (\(online) online)" : "Agent Activity"
            } else {
                return online > 0 ? "Agent 动态（\(online) 个在线）" : "Agent 动态"
            }
        }
    }

    private static func menuBarIcon(visualState: MenuBarVisualState) -> NSImage {
        let hasBadge: Bool = {
            switch visualState {
            case .needsInput, .unreadCompleted:
                return true
            case .working, .idle:
                return false
            }
        }()

        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)

            let fgColor = NSColor.labelColor.cgColor
            let offsetX: CGFloat = hasBadge ? 1.8 : 3.2

            // Minimalist terminal chevron `>`
            ctx.beginPath()
            ctx.move(to: CGPoint(x: offsetX, y: 12.6))
            ctx.addLine(to: CGPoint(x: offsetX + 3.8, y: 9.0))
            ctx.addLine(to: CGPoint(x: offsetX, y: 5.4))
            ctx.setLineWidth(1.85)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(fgColor)
            ctx.strokePath()

            // Three clean static horizontal meter bars
            let barX = offsetX + 6.4
            let bars: [(y: CGFloat, width: CGFloat, alpha: CGFloat)] = [
                (12.2, 7.6, 1.0),
                (9.0, 5.4, 0.85),
                (5.8, 3.6, 0.55),
            ]
            for bar in bars {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: barX, y: bar.y))
                ctx.addLine(to: CGPoint(x: barX + bar.width, y: bar.y))
                ctx.setLineWidth(1.85)
                ctx.setLineCap(.round)
                ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(bar.alpha).cgColor)
                ctx.strokePath()
            }

            // State-specific bright dot badge
            let dotColor: NSColor? = {
                switch visualState {
                case .needsInput:
                    // Bright Amber-Orange dot for pending user confirmation
                    return NSColor(srgbRed: 1.0, green: 0.62, blue: 0.12, alpha: 1.0)
                case .unreadCompleted:
                    // Bright Coral-Rose dot for unread task completion
                    return NSColor(srgbRed: 1.0, green: 0.22, blue: 0.44, alpha: 1.0)
                case .working, .idle:
                    return nil
                }
            }()

            if let dotColor {
                let dotDiameter: CGFloat = 6.5
                let dotRect = NSRect(
                    x: rect.width - dotDiameter - 0.8,
                    y: rect.height - dotDiameter - 1.8,
                    width: dotDiameter,
                    height: dotDiameter
                )
                let glowRect = dotRect.insetBy(dx: -1.5, dy: -1.5)
                dotColor.withAlphaComponent(0.34).setFill()
                NSBezierPath(ovalIn: glowRect).fill()

                dotColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        image.isTemplate = !hasBadge
        return image
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: AgentMeterPanelController?
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--dump") {
            Task { @MainActor in
                let tracker = AgentActivityTracker()
                let res = await tracker.poll()
                for item in res.items {
                    let ctxStr = item.contextPercentUsed.map { "\($0)%" } ?? "-"
                let previewStr = item.terminalPreviewLines.joined(separator: " // ")
                print("DUMP_ITEM | id=\(item.id) | family=\(item.family.rawValue) | status=\(item.status.rawValue) | pid=\(item.pid ?? 0) | ctx=\(ctxStr) | title=\(item.title) | subtitle=\(item.subtitleText()) | preview=\(previewStr)")
                }
                NSApplication.shared.terminate(nil)
            }
            return
        }
        let isPreview = ProcessInfo.processInfo.arguments.contains("--preview")
        NSApplication.shared.setActivationPolicy(isPreview ? .regular : .accessory)
        AgentMeterModel.shared.applyAppearance()
        panelController = AgentMeterPanelController(model: AgentMeterModel.shared)
        AgentMeterModel.shared.start()

        GlobalHotKeyManager.shared.onTogglePanel = { [weak self] in
            self?.togglePanel()
        }
        GlobalHotKeyManager.shared.onJumpMostUrgent = {
            AgentMeterModel.shared.jumpToMostUrgentAgentSession()
        }
        AgentMeterModel.shared.onGlobalHotkeysPreferenceChanged = { enabled in
            GlobalHotKeyManager.shared.setEnabled(enabled)
        }
        GlobalHotKeyManager.shared.setEnabled(AgentMeterModel.shared.globalHotkeysEnabled)

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in AgentMeterModel.shared.sleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in AgentMeterModel.shared.wake() }
            },
        ]
        if isPreview { panelController?.showPreview() }
        if ProcessInfo.processInfo.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.openPanel() }
        }
    }

    func openPanel() {
        DispatchQueue.main.async { [weak self] in
            for window in NSApplication.shared.windows where window.isVisible {
                if let button = Self.statusButton(in: window.contentView) {
                    button.performClick(nil)
                    return
                }
            }
            self?.panelController?.showPanel()
        }
    }

    func togglePanel() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasVisibleMenuWindow = NSApplication.shared.windows.contains { window in
                guard window.isVisible else { return false }
                let className = NSStringFromClass(type(of: window))
                return !className.contains("StatusBar")
            }
            if hasVisibleMenuWindow || AgentMeterModel.shared.isPanelOpen {
                for window in NSApplication.shared.windows where window.isVisible {
                    let className = NSStringFromClass(type(of: window))
                    if className.contains("StatusBar") { continue }
                    window.orderOut(nil)
                }
                self.panelController?.stop()
                AgentMeterModel.shared.panelDidClose()
            } else {
                self.openPanel()
            }
        }
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for child in view.subviews {
            if let button = statusButton(in: child) { return button }
        }
        return nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            panelController?.showPreview()
        } else {
            openPanel()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyManager.shared.unregisterHotKeys()
        panelController?.stop()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
