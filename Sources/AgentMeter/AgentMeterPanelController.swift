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

@MainActor
final class AgentMiniConfirmController: NSObject {
    private let model: AgentMeterModel
    private let panel: MiniConfirmWindow
    private var hostingView: TransparentHostingView<AgentMiniConfirmCardView>?
    private var currentItemID: String?
    private var currentToken: String?
    private var localScrollMonitor: Any?
    private var globalScrollMonitor: Any?
    private var accumulatedUpwardSwipe: CGFloat = 0
    private var isDismissing = false

    init(model: AgentMeterModel) {
        self.model = model
        self.panel = MiniConfirmWindow()
        super.init()
        panel.onSwipeUpDismiss = { [weak self] in
            self?.dismissBySwipeUp()
        }
    }

    func syncWithModel() {
        guard let item = model.activeMiniConfirmItem else {
            hide(animated: true)
            return
        }
        showOrUpdate(item: item)
    }

    private func showOrUpdate(item: AgentActivityItem) {
        let token = model.miniConfirmToken(for: item)
        let rootView = AgentMiniConfirmCardView(model: model, item: item)

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hv = TransparentHostingView(rootView: rootView)
            hv.sizingOptions = [.intrinsicContentSize]
            hv.wantsLayer = true
            hv.layer?.backgroundColor = NSColor.clear.cgColor
            hv.layer?.cornerRadius = 10
            hv.layer?.cornerCurve = .continuous
            hv.layer?.masksToBounds = true
            panel.contentView = hv
            self.hostingView = hv
        }

        hostingView?.layoutSubtreeIfNeeded()
        let fitting = hostingView?.fittingSize ?? NSSize(width: 392, height: 128)
        let cardSize = NSSize(width: 392, height: max(112, min(220, fitting.height)))
        panel.setContentSize(cardSize)
        panel.appearance = model.appearanceMode.appKitAppearance
        panel.invalidateShadow()

        let targetOrigin = resolveTargetOrigin(for: cardSize)
        let wasVisible = panel.isVisible && !isDismissing
        currentItemID = item.id
        currentToken = token
        isDismissing = false
        accumulatedUpwardSwipe = 0
        installScrollGestureMonitors()

        if wasVisible {
            panel.setFrameOrigin(targetOrigin)
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.alphaValue = 1
            panel.setFrameOrigin(targetOrigin)
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y + 10))
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(targetOrigin)
            }
        }

        // Re-align once macOS finishes laying out the NSStatusBarWindow frame after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.panel.isVisible, !self.isDismissing else { return }
            let refinedOrigin = self.resolveTargetOrigin(for: self.panel.frame.size)
            if abs(refinedOrigin.x - self.panel.frame.origin.x) > 2 || abs(refinedOrigin.y - self.panel.frame.origin.y) > 2 {
                self.panel.setFrameOrigin(refinedOrigin)
            }
        }
    }

    private func resolveTargetOrigin(for cardSize: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = (activeScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)).insetBy(dx: 10, dy: 6)

        if let statusWin = Self.findStatusBarWindow(for: activeScreen) {
            let statusFrame = statusWin.frame
            let desiredX = statusFrame.maxX - cardSize.width
            let clampedX = min(max(desiredX, visible.minX), visible.maxX - cardSize.width)
            let topEdge = min(visible.maxY, statusFrame.minY - 6)
            return NSPoint(x: clampedX, y: topEdge - cardSize.height)
        }

        return NSPoint(x: visible.maxX - cardSize.width - 12, y: visible.maxY - cardSize.height)
    }

    private static func findStatusBarWindow(for targetScreen: NSScreen?) -> NSWindow? {
        let candidates = NSApplication.shared.windows.filter { win in
            let className = NSStringFromClass(type(of: win))
            guard className.contains("StatusBar") else { return false }
            return win.frame.width > 10 && win.frame.height > 10
        }
        if let targetScreen {
            if let matched = candidates.first(where: { win in
                (win.screen == targetScreen || targetScreen.frame.intersects(win.frame))
                    && win.frame.minX > targetScreen.frame.minX + 40
            }) {
                return matched
            }
        }
        return candidates.first { win in
            guard let screen = win.screen else { return win.frame.minX > 40 }
            return win.frame.minX > screen.frame.minX + 40
        }
    }

    private func installScrollGestureMonitors() {
        guard localScrollMonitor == nil, globalScrollMonitor == nil else { return }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            if self.handleScrollEvent(event) {
                return nil
            }
            return event
        }
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handleScrollEvent(event)
            }
        }
    }

    private func removeScrollGestureMonitors() {
        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
            self.localScrollMonitor = nil
        }
        if let globalScrollMonitor {
            NSEvent.removeMonitor(globalScrollMonitor)
            self.globalScrollMonitor = nil
        }
        accumulatedUpwardSwipe = 0
    }

    private func handleScrollEvent(_ event: NSEvent) -> Bool {
        guard panel.isVisible, !isDismissing else { return false }
        let mouseLoc = NSEvent.mouseLocation
        guard panel.frame.insetBy(dx: -6, dy: -6).contains(mouseLoc) else { return false }

        if event.phase == .began {
            accumulatedUpwardSwipe = 0
        }

        // Physical upward two-finger movement on trackpad (supports both natural and standard scroll directions)
        let dy = event.scrollingDeltaY
        let physicalUpward = event.isDirectionInvertedFromDevice ? -dy : dy
        let upwardComponent = max(physicalUpward, -dy)

        if upwardComponent > 0 {
            accumulatedUpwardSwipe += upwardComponent
        } else if event.phase == .ended || event.phase == .cancelled {
            accumulatedUpwardSwipe = 0
        }

        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 14.0 : 2.0
        if accumulatedUpwardSwipe >= threshold {
            dismissBySwipeUp()
            return true
        }
        return false
    }

    func dismissBySwipeUp() {
        guard panel.isVisible, !isDismissing else { return }
        if let item = model.activeMiniConfirmItem {
            model.dismissMiniConfirmCard(for: item)
        } else {
            hide(animated: true)
        }
    }

    func hide(animated: Bool) {
        removeScrollGestureMonitors()
        guard panel.isVisible, !isDismissing else {
            if !isDismissing {
                panel.orderOut(nil)
            }
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduceMotion else {
            panel.orderOut(nil)
            currentItemID = nil
            currentToken = nil
            return
        }
        isDismissing = true
        let targetFrame = panel.frame.offsetBy(dx: 0, dy: 12)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(targetFrame, display: false)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.isDismissing = false
                self.currentItemID = nil
                self.currentToken = nil
            }
        }
    }

    func stop() {
        hide(animated: false)
    }
}

@MainActor
private final class MiniConfirmWindow: NSPanel {
    var onSwipeUpDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 392, height: 128),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Agent Meter Confirm"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    override func cancelOperation(_ sender: Any?) {
        onSwipeUpDismiss?()
    }
}

@MainActor
final class AgentPiPController: NSObject, NSWindowDelegate {
    private let model: AgentMeterModel
    private let panel: PiPWindow
    private var hostingView: TransparentHostingView<AgentPiPCardView>?
    private var localEventMonitor: Any?
    private var globalScrollMonitor: Any?
    private var isPointerHovering = false
    private var isDraggingWindow = false
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    private var accumulatedUpwardSwipe: CGFloat = 0
    private var isDismissing = false
    private var lastRenderedWasCollapsed: Bool?

    init(model: AgentMeterModel) {
        self.model = model
        self.panel = PiPWindow()
        super.init()
        panel.delegate = self
        panel.onCancel = { [weak self] in
            self?.model.closePiP()
        }
    }

    func syncWithModel() {
        guard let item = model.activePiPItem else {
            hide(animated: true)
            return
        }
        showOrUpdate(item: item)
    }

    private func showOrUpdate(item: AgentActivityItem) {
        let rootView = AgentPiPCardView(
            model: model,
            item: item,
            onCardHoverChange: { [weak self] hovering in
                self?.setHovering(hovering)
            }
        )

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hv = TransparentHostingView(rootView: rootView)
            hv.sizingOptions = [.intrinsicContentSize]
            hv.wantsLayer = true
            hv.layer?.backgroundColor = NSColor.clear.cgColor
            hv.layer?.cornerCurve = .continuous
            hv.layer?.masksToBounds = true
            panel.contentView = hv
            self.hostingView = hv
        }

        hostingView?.layer?.cornerRadius = model.isPiPCollapsedPill ? 18 : 11
        hostingView?.layoutSubtreeIfNeeded()
        let defaultSize = model.isPiPCollapsedPill
            ? NSSize(width: 256, height: 34)
            : NSSize(width: 392, height: 142)
        let fitting = hostingView?.fittingSize ?? defaultSize
        let cardSize = NSSize(
            width: model.isPiPCollapsedPill ? 256 : 392,
            height: max(model.isPiPCollapsedPill ? 32 : 134, min(240, fitting.height))
        )

        let wasVisible = panel.isVisible && !isDismissing
        let collapsedChanged = (lastRenderedWasCollapsed != nil && lastRenderedWasCollapsed != model.isPiPCollapsedPill)
        lastRenderedWasCollapsed = model.isPiPCollapsedPill

        panel.appearance = model.appearanceMode.appKitAppearance
        let targetOrigin = cornerOrigin(for: model.pipCorner, size: cardSize, on: currentScreen())
        let targetAlpha = desiredAlpha(for: item)

        isDismissing = false
        installEventMonitors()

        if wasVisible {
            if !isDraggingWindow {
                let targetFrame = NSRect(origin: targetOrigin, size: cardSize)
                if collapsedChanged {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.18
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        panel.animator().setFrame(targetFrame, display: true)
                        panel.animator().alphaValue = targetAlpha
                    }
                } else {
                    panel.setFrame(targetFrame, display: true)
                    panel.alphaValue = targetAlpha
                }
            }
            panel.invalidateShadow()
            return
        }

        panel.setContentSize(cardSize)
        panel.invalidateShadow()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.alphaValue = targetAlpha
            panel.setFrameOrigin(targetOrigin)
            panel.orderFrontRegardless()
            return
        }

        panel.alphaValue = 0
        let slideOffset: CGFloat = (model.pipCorner == .topRight || model.pipCorner == .topLeft) ? 10 : -10
        panel.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y + slideOffset))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = targetAlpha
            panel.animator().setFrameOrigin(targetOrigin)
        }
    }

    private func desiredAlpha(for item: AgentActivityItem) -> CGFloat {
        if isPointerHovering || isDraggingWindow || item.status == .needsInput {
            return 1.0
        }
        return 0.86
    }

    private func setHovering(_ hovering: Bool) {
        guard isPointerHovering != hovering else { return }
        isPointerHovering = hovering
        guard panel.isVisible, !isDismissing, let item = model.activePiPItem else { return }
        let targetAlpha = desiredAlpha(for: item)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = targetAlpha
        }
    }

    private func currentScreen() -> NSScreen? {
        if panel.isVisible, let screen = panel.screen {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func cornerOrigin(for corner: PiPCorner, size: NSSize, on screen: NSScreen?) -> NSPoint {
        let visible = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)).insetBy(dx: 16, dy: 16)
        switch corner {
        case .bottomRight:
            return NSPoint(x: visible.maxX - size.width, y: visible.minY)
        case .topRight:
            return NSPoint(x: visible.maxX - size.width, y: visible.maxY - size.height)
        case .bottomLeft:
            return NSPoint(x: visible.minX, y: visible.minY)
        case .topLeft:
            return NSPoint(x: visible.minX, y: visible.maxY - size.height)
        }
    }

    private func nearestCorner(for frame: NSRect, on screen: NSScreen?) -> PiPCorner {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let isLeft = frame.midX < visible.midX
        let isBottom = frame.midY < visible.midY
        switch (isLeft, isBottom) {
        case (false, true): return .bottomRight
        case (false, false): return .topRight
        case (true, true): return .bottomLeft
        case (true, false): return .topLeft
        }
    }

    private func installEventMonitors() {
        guard localEventMonitor == nil, globalScrollMonitor == nil else { return }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .scrollWheel {
                if self.handleScrollEvent(event) {
                    return nil
                }
                return event
            }
            if event.window === self.panel {
                self.handleMouseEvent(event)
            }
            return event
        }

        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handleScrollEvent(event)
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalScrollMonitor {
            NSEvent.removeMonitor(globalScrollMonitor)
            self.globalScrollMonitor = nil
        }
        isDraggingWindow = false
        accumulatedUpwardSwipe = 0
    }

    private func handleMouseEvent(_ event: NSEvent) {
        guard panel.isVisible, !isDismissing else { return }

        switch event.type {
        case .leftMouseDown:
            let locInWin = event.locationInWindow
            let isInHeaderBand = locInWin.y >= (panel.frame.height - 32)
            if event.clickCount == 2 && isInHeaderBand {
                model.togglePiPCollapsedPill()
                return
            }
            if let responder = panel.firstResponder,
               (responder is NSTextView) || (responder is NSTextField) {
                let hitView = panel.contentView?.hitTest(locInWin)
                if hitView is NSTextField || hitView is NSTextView {
                    return
                }
            }
            dragStartMouseLocation = NSEvent.mouseLocation
            dragStartWindowOrigin = panel.frame.origin
            isDraggingWindow = false

        case .leftMouseDragged:
            guard dragStartMouseLocation != .zero else { return }
            let currentMouse = NSEvent.mouseLocation
            let dx = currentMouse.x - dragStartMouseLocation.x
            let dy = currentMouse.y - dragStartMouseLocation.y
            if !isDraggingWindow && hypot(dx, dy) >= 3.5 {
                isDraggingWindow = true
                panel.alphaValue = 1.0
            }
            if isDraggingWindow {
                let newOrigin = NSPoint(
                    x: dragStartWindowOrigin.x + dx,
                    y: dragStartWindowOrigin.y + dy
                )
                panel.setFrameOrigin(newOrigin)
            }

        case .leftMouseUp:
            defer {
                dragStartMouseLocation = .zero
            }
            guard isDraggingWindow else { return }
            isDraggingWindow = false
            let screen = panel.screen ?? currentScreen()
            let snappedCorner = nearestCorner(for: panel.frame, on: screen)
            model.pipCorner = snappedCorner
            let targetOrigin = cornerOrigin(for: snappedCorner, size: panel.frame.size, on: screen)
            let targetAlpha = model.activePiPItem.map { desiredAlpha(for: $0) } ?? 1.0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                panel.animator().setFrameOrigin(targetOrigin)
                panel.animator().alphaValue = targetAlpha
            }

        default:
            break
        }
    }

    private func handleScrollEvent(_ event: NSEvent) -> Bool {
        guard panel.isVisible, !isDismissing else { return false }
        let mouseLoc = NSEvent.mouseLocation
        guard panel.frame.insetBy(dx: -6, dy: -6).contains(mouseLoc) else { return false }

        if event.phase == .began {
            accumulatedUpwardSwipe = 0
        }

        let dy = event.scrollingDeltaY
        let physicalUpward = event.isDirectionInvertedFromDevice ? -dy : dy
        let upwardComponent = max(physicalUpward, -dy)

        if upwardComponent > 0 {
            accumulatedUpwardSwipe += upwardComponent
        } else if event.phase == .ended || event.phase == .cancelled {
            accumulatedUpwardSwipe = 0
        }

        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 16.0 : 2.5
        if accumulatedUpwardSwipe >= threshold {
            accumulatedUpwardSwipe = 0
            model.closePiP()
            return true
        }
        return false
    }

    func hide(animated: Bool) {
        removeEventMonitors()
        lastRenderedWasCollapsed = nil
        guard panel.isVisible, !isDismissing else {
            if !isDismissing {
                panel.orderOut(nil)
            }
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduceMotion else {
            panel.orderOut(nil)
            return
        }
        isDismissing = true
        let slideOffset: CGFloat = (model.pipCorner == .topRight || model.pipCorner == .topLeft) ? 10 : -10
        let targetFrame = panel.frame.offsetBy(dx: 0, dy: slideOffset)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(targetFrame, display: false)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.isDismissing = false
            }
        }
    }

    func stop() {
        hide(animated: false)
    }
}

@MainActor
private final class PiPWindow: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 392, height: 142),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Agent Meter PiP"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

