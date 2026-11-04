import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class AgentMeterPanelController: NSObject, NSWindowDelegate {
    private let model: AgentMeterModel
    private let panel: FlatMeterWindow
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var showingPreview = false

    init(model: AgentMeterModel) {
        self.model = model
        panel = FlatMeterWindow()
        super.init()
        let hostingView = TransparentHostingView(rootView: AgentMeterPanel(model: model))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = NSRect(origin: .zero, size: panel.frame.size)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = FlatGeometry.panelRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.hidePanel() }
    }

    var isPanelVisible: Bool {
        panel.isVisible
    }

    func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        showingPreview = false
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        fitPanel(to: screen)
        var targetOrigin = panel.frame.origin
        if let screen {
            let bounds = screen.visibleFrame.insetBy(dx: 10, dy: 10)
            let x = min(max(mouse.x - panel.frame.width / 2, bounds.minX), bounds.maxX - panel.frame.width)
            targetOrigin = NSPoint(x: x, y: bounds.maxY - panel.frame.height)
        }
        presentPanel(at: targetOrigin)
        installDismissMonitors()
        model.panelDidOpen()
    }

    func showPreview() {
        showingPreview = true
        fitPanel(to: NSScreen.main)
        panel.center()
        presentPanel(at: panel.frame.origin)
        NSApplication.shared.activate(ignoringOtherApps: true)
        model.panelDidOpen()
    }

    private func presentPanel(at targetOrigin: NSPoint) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduceMotion else {
            panel.alphaValue = 1
            panel.setFrameOrigin(targetOrigin)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y + 6))
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(targetOrigin)
        }
    }

    private func fitPanel(to screen: NSScreen?) {
        let availableHeight = (screen?.visibleFrame.height ?? 700) - 24
        panel.setContentSize(NSSize(width: 416, height: min(560, max(300, availableHeight))))
        panel.invalidateShadow()
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    self.hidePanel()
                    return nil
                }
            } else if event.window !== self.panel {
                self.hidePanel()
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func hidePanel() {
        removeDismissMonitors()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard panel.isVisible, !reduceMotion else {
            panel.orderOut(nil)
            model.panelDidClose()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.model.panelDidClose()
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if !showingPreview { hidePanel() }
    }

    func stop() { hidePanel() }
}

@MainActor
private final class FlatMeterWindow: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 416, height: 560),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        title = "Agent Meter"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .popUpMenu
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .none
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}
