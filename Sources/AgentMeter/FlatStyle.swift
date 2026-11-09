import AppKit
import SwiftUI

/// Pure Stageshow Design System (`kit/stage.css` + `examples/dark-hero` + `references/craft.md`):
/// - Zero blur, zero glass: depth comes from 4 solid surface steps (`--ss-canvas`, `--ss-chrome`, `--ss-surface`, `--ss-raised`) and 1px hairlines.
/// - Opaque text & icon tokens (`--ss-text-strong`, `--ss-text`, `--ss-text-faint`, `--ss-icon`) so strokes never paint darker at intersections.
/// - Single focal accent rule: only the active confirmation / warning state lights up semantic color; running & completed states stay quiet.
enum FlatPalette {
    static let blue = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 147.0 / 255, green: 197.0 / 255, blue: 253.0 / 255, alpha: 1)
            : NSColor(srgbRed: 37.0 / 255, green: 99.0 / 255, blue: 235.0 / 255, alpha: 1)
    })

    // --ss-canvas: #111113 (dark) / #F9F9FB (light Radix Slate 2)
    static func panelBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 17.0 / 255, green: 17.0 / 255, blue: 19.0 / 255)
            : Color(red: 249.0 / 255, green: 249.0 / 255, blue: 251.0 / 255)
    }

    // --ss-chrome: #1D1D20 (dark) / #FFFFFF (light)
    static func chromeBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 29.0 / 255, green: 29.0 / 255, blue: 32.0 / 255)
            : Color.white
    }

    // --ss-surface: #1A1A1D (dark) / #FFFFFF (light)
    static func cardBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 26.0 / 255, green: 26.0 / 255, blue: 29.0 / 255)
            : Color.white
    }

    static func elevatedRowBackground(dark: Bool, hovered: Bool = false) -> Color {
        if dark {
            return hovered
                ? Color(red: 33.0 / 255, green: 33.0 / 255, blue: 37.0 / 255)
                : Color(red: 26.0 / 255, green: 26.0 / 255, blue: 29.0 / 255)
        } else {
            return hovered
                ? Color(red: 249.0 / 255, green: 249.0 / 255, blue: 251.0 / 255)
                : Color.white
        }
    }

    // --ss-raised: #26262A (dark) -> #313134 (hovered) / #FFFFFF (light) -> #E8E8EC (hovered)
    static func raisedBackground(dark: Bool, hovered: Bool = false) -> Color {
        if dark {
            return hovered
                ? Color(red: 49.0 / 255, green: 49.0 / 255, blue: 52.0 / 255)
                : Color(red: 38.0 / 255, green: 38.0 / 255, blue: 42.0 / 255)
        } else {
            return hovered
                ? Color(red: 232.0 / 255, green: 232.0 / 255, blue: 236.0 / 255)
                : Color.white
        }
    }

    // --ss-ink-2: rgba(255, 255, 255, 0.07) (dark) / #E8E8EC (light Radix Slate 4)
    static func trackBackground(dark: Bool) -> Color {
        dark
            ? Color.white.opacity(0.07)
            : Color(red: 232.0 / 255, green: 232.0 / 255, blue: 236.0 / 255)
    }

    // --ss-raised: #26262A (dark) / #FFFFFF (light)
    static func selectedPillBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 38.0 / 255, green: 38.0 / 255, blue: 42.0 / 255)
            : Color.white
    }

    // --ss-term-bg: #141417 (dark) / #F0F0F3 (light Radix Slate 3)
    static func terminalWellBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 20.0 / 255, green: 20.0 / 255, blue: 23.0 / 255)
            : Color(red: 240.0 / 255, green: 240.0 / 255, blue: 243.0 / 255)
    }

    static func controlBackground(dark: Bool, highlighted: Bool) -> Color {
        raisedBackground(dark: dark, hovered: highlighted)
    }

    // --ss-text-strong: #ECECEE (dark) / #1C2024 (light Radix Slate 12)
    static func inkPrimary(dark: Bool) -> Color {
        dark
            ? Color(red: 236.0 / 255, green: 236.0 / 255, blue: 238.0 / 255)
            : Color(red: 28.0 / 255, green: 32.0 / 255, blue: 36.0 / 255)
    }

    // --ss-text: #9D9DA1 (dark) / #60646C (light Radix Slate 11)
    static func inkSecondary(dark: Bool) -> Color {
        dark
            ? Color(red: 157.0 / 255, green: 157.0 / 255, blue: 161.0 / 255)
            : Color(red: 96.0 / 255, green: 100.0 / 255, blue: 108.0 / 255)
    }

    // --ss-text-faint: #6C6C70 (dark) / #8B8D98 (light Radix Slate 9)
    static func inkTertiary(dark: Bool) -> Color {
        dark
            ? Color(red: 108.0 / 255, green: 108.0 / 255, blue: 112.0 / 255)
            : Color(red: 139.0 / 255, green: 141.0 / 255, blue: 152.0 / 255)
    }

    // --ss-icon: #9A9AA0 (dark) / #60646C (light Radix Slate 11)
    static func iconPrimary(dark: Bool) -> Color {
        dark
            ? Color(red: 154.0 / 255, green: 154.0 / 255, blue: 160.0 / 255)
            : Color(red: 96.0 / 255, green: 100.0 / 255, blue: 108.0 / 255)
    }

    // --ss-line: rgba(255, 255, 255, 0.08) (dark) / #E8E8EC (light Radix Slate 4)
    static func hairlineBorder(dark: Bool) -> Color {
        dark
            ? Color.white.opacity(0.08)
            : Color(red: 232.0 / 255, green: 232.0 / 255, blue: 236.0 / 255)
    }

    // --ss-line-faint: rgba(255, 255, 255, 0.05) (dark) / #F0F0F3 (light Radix Slate 3)
    static func faintBorder(dark: Bool) -> Color {
        dark
            ? Color.white.opacity(0.05)
            : Color(red: 240.0 / 255, green: 240.0 / 255, blue: 243.0 / 255)
    }

    // --ss-accent: #3B82F6 (dark) / #3E63DD (light Radix Indigo 9)
    static func accent(dark: Bool) -> Color {
        dark
            ? Color(red: 59.0 / 255, green: 130.0 / 255, blue: 246.0 / 255)
            : Color(red: 62.0 / 255, green: 99.0 / 255, blue: 221.0 / 255)
    }

    // --ss-accent-text: #93C5FD (dark) / #3358D4 (light Radix Indigo)
    static func accentText(dark: Bool) -> Color {
        dark
            ? Color(red: 147.0 / 255, green: 197.0 / 255, blue: 253.0 / 255)
            : Color(red: 51.0 / 255, green: 88.0 / 255, blue: 212.0 / 255)
    }

    // --ss-accent-soft: rgba(59, 130, 246, 0.20) (dark) / #E1E9FF (light Radix Indigo 3)
    static func accentSoftBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 59.0 / 255, green: 130.0 / 255, blue: 246.0 / 255).opacity(0.20)
            : Color(red: 225.0 / 255, green: 233.0 / 255, blue: 255.0 / 255)
    }

    // --ss-term-path: #6F8CCF (dark) / #4B6CB7 (light)
    static func terminalPath(dark: Bool) -> Color {
        dark
            ? Color(red: 111.0 / 255, green: 140.0 / 255, blue: 207.0 / 255)
            : Color(red: 75.0 / 255, green: 108.0 / 255, blue: 183.0 / 255)
    }

    // --ss-term-sigil: #6EE7A8 (dark) / #15803D (light)
    static func terminalSigil(dark: Bool) -> Color {
        dark
            ? Color(red: 110.0 / 255, green: 231.0 / 255, blue: 168.0 / 255)
            : Color(red: 21.0 / 255, green: 128.0 / 255, blue: 61.0 / 255)
    }

    // --ss-warning-text: #FBBF24 (dark) / #B45309 (light)
    static func conflictWarningForeground(dark: Bool) -> Color {
        dark
            ? Color(red: 251.0 / 255, green: 191.0 / 255, blue: 36.0 / 255)
            : Color(red: 180.0 / 255, green: 83.0 / 255, blue: 9.0 / 255)
    }

    // --ss-warning-soft: rgba(245, 158, 11, 0.18) (dark) / rgba(245, 158, 11, 0.14) (light)
    static func conflictWarningBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255).opacity(0.18)
            : Color(red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255).opacity(0.14)
    }

    static func amberAlertForeground(dark: Bool) -> Color {
        conflictWarningForeground(dark: dark)
    }

    static func amberAlertBackground(dark: Bool) -> Color {
        conflictWarningBackground(dark: dark)
    }

    // --ss-danger-text: #F87171 (dark) / #B91C1C (light)
    static func dangerInterruptForeground(dark: Bool) -> Color {
        dark
            ? Color(red: 248.0 / 255, green: 113.0 / 255, blue: 113.0 / 255)
            : Color(red: 185.0 / 255, green: 28.0 / 255, blue: 28.0 / 255)
    }

    // --ss-danger-soft: rgba(239, 68, 68, 0.16..0.24) (dark) / rgba(239, 68, 68, 0.10..0.16) (light)
    static func dangerInterruptBackground(dark: Bool, hovered: Bool) -> Color {
        if dark {
            return Color(red: 239.0 / 255, green: 68.0 / 255, blue: 68.0 / 255).opacity(hovered ? 0.24 : 0.16)
        } else {
            return Color(red: 239.0 / 255, green: 68.0 / 255, blue: 68.0 / 255).opacity(hovered ? 0.16 : 0.10)
        }
    }

    // --ss-success-text: #4ADE80 (dark) / #15803D (light)
    static func softGoodForeground(dark: Bool) -> Color {
        dark
            ? Color(red: 74.0 / 255, green: 222.0 / 255, blue: 128.0 / 255)
            : Color(red: 21.0 / 255, green: 128.0 / 255, blue: 61.0 / 255)
    }

    // --ss-success-soft: rgba(34, 197, 94, 0.16..0.24) (dark) / rgba(34, 197, 94, 0.12..0.18) (light)
    static func softGoodBackground(dark: Bool, hovered: Bool = false) -> Color {
        if dark {
            return Color(red: 34.0 / 255, green: 197.0 / 255, blue: 94.0 / 255).opacity(hovered ? 0.24 : 0.16)
        } else {
            return Color(red: 34.0 / 255, green: 197.0 / 255, blue: 94.0 / 255).opacity(hovered ? 0.18 : 0.12)
        }
    }

    static func diffAddForeground(dark: Bool) -> Color {
        softGoodForeground(dark: dark)
    }

    static func diffDeleteForeground(dark: Bool) -> Color {
        dangerInterruptForeground(dark: dark)
    }
}

enum FlatGeometry {
    static let panelRadius: CGFloat = 12
    static let cardRadius: CGFloat = 10
}

enum FlatMotion {
    static func snappy(reduceMotion: Bool, duration: TimeInterval = 0.22) -> Animation? {
        reduceMotion ? nil : .snappy(duration: duration, extraBounce: 0)
    }

    static func micro(reduceMotion: Bool, duration: TimeInterval = 0.16) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }
}

struct FlatPanelSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: FlatGeometry.panelRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(FlatPalette.panelBackground(dark: dark))
                    .overlay {
                        shape.strokeBorder(
                            FlatPalette.hairlineBorder(dark: dark),
                            lineWidth: 1
                        )
                    }
            }
            .clipShape(shape)
    }
}

struct FlatCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = FlatGeometry.cardRadius

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(FlatPalette.cardBackground(dark: dark))
                    .overlay {
                        shape.strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(dark ? 0.22 : 0.035), radius: 2, x: 0, y: 1)
            }
    }
}

private struct FlatControlSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let shape: S
    let highlighted: Bool

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        content
            .background {
                shape
                    .fill(FlatPalette.raisedBackground(dark: dark, hovered: highlighted))
                    .overlay {
                        shape.strokeBorder(
                            FlatPalette.hairlineBorder(dark: dark),
                            lineWidth: 1
                        )
                    }
                    .shadow(color: .black.opacity(dark ? 0 : 0.03), radius: 1.5, x: 0, y: 1)
            }
    }
}

/// A Stageshow rounded-square icon button (`.ss-icon-btn`, 6pt radius) backed directly by `PointingHandCursorOverlay`.
struct FlatIconButton: View {
    let icon: String
    var size: CGFloat = 26
    var iconSize: CGFloat = 12.5
    var rotatesOnHover: Bool = false
    var tooltip: String? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(hovered ? FlatPalette.inkPrimary(dark: dark) : FlatPalette.iconPrimary(dark: dark))
            .rotationEffect(.degrees(rotatesOnHover && hovered && !reduceMotion ? 20 : 0))
            .frame(width: size, height: size)
            .background(
                shape.fill(
                    dark
                        ? Color.white.opacity(hovered ? 0.10 : 0.07)
                        : Color.black.opacity(hovered ? 0.08 : 0.06)
                )
            )
            .contentShape(shape)
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: tooltip,
                    onHoverChange: { isHovering in
                        hovered = isHovering
                    },
                    onClick: action
                )
            }
            .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16), value: hovered)
            .accessibilityLabel(tooltip ?? icon)
    }
}

/// A Stageshow rounded-rect text button (`.ss-btn`, 6pt radius) backed directly by `PointingHandCursorOverlay`.
struct FlatCapsuleButton: View {
    let title: String
    var compact: Bool = true
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(title)
            .font(.system(size: compact ? 11.5 : 13, weight: .medium))
            .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.vertical, compact ? 4.5 : 8)
            .modifier(FlatControlSurface(shape: shape, highlighted: hovered))
            .contentShape(shape)
            .overlay {
                PointingHandCursorOverlay(
                    onHoverChange: { isHovering in
                        hovered = isHovering
                    },
                    onClick: action
                )
            }
            .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16), value: hovered)
    }
}

/// A native AppKit tracking view that owns hit-testing, cursor rects, and click handling inside `NSHostingView`.
struct PointingHandCursorOverlay: NSViewRepresentable {
    var tooltip: String? = nil
    var onHoverChange: ((Bool) -> Void)? = nil
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> CursorAreaView {
        let view = CursorAreaView(frame: .zero)
        view.toolTip = tooltip
        view.onHoverChange = onHoverChange
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: CursorAreaView, context: Context) {
        if nsView.toolTip != tooltip {
            nsView.toolTip = tooltip
        }
        nsView.onHoverChange = onHoverChange
        nsView.onClick = onClick
    }

    final class CursorAreaView: NSView {
        var onHoverChange: ((Bool) -> Void)?
        var onClick: (() -> Void)?
        private var trackingArea: NSTrackingArea?
        private var isMouseInside = false
        private static let allViews = NSHashTable<CursorAreaView>.weakObjects()

        private static func isMouseInsideAnyView(in window: NSWindow?) -> Bool {
            guard let window, window.isVisible else { return false }
            let mouseInWindow = window.mouseLocationOutsideOfEventStream
            for view in allViews.allObjects {
                guard view.window === window, !view.isHiddenOrHasHiddenAncestor else { continue }
                let localPoint = view.convert(mouseInWindow, from: nil)
                if view.bounds.contains(localPoint) {
                    return true
                }
            }
            return false
        }

        private static func reconcileHoveredViews(in window: NSWindow?, excluding activeView: CursorAreaView? = nil) {
            guard let window else { return }
            let mouseInWindow = window.mouseLocationOutsideOfEventStream
            for view in allViews.allObjects {
                guard view.window === window, view.isMouseInside, view !== activeView else { continue }
                let localPoint = view.convert(mouseInWindow, from: nil)
                let stillInside = window.isVisible && !view.isHiddenOrHasHiddenAncestor && view.bounds.contains(localPoint)
                if !stillInside {
                    view.isMouseInside = false
                    view.onHoverChange?(false)
                }
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.inVisibleRect, .mouseEnteredAndExited, .cursorUpdate, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
            Self.allViews.add(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                Self.allViews.add(self)
                window.acceptsMouseMovedEvents = true
                if !window.areCursorRectsEnabled { window.enableCursorRects() }
                window.invalidateCursorRects(for: self)
            } else {
                if isMouseInside {
                    isMouseInside = false
                    onHoverChange?(false)
                }
            }
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.pointingHand.set()
        }

        override func mouseMoved(with event: NSEvent) {
            Self.reconcileHoveredViews(in: self.window, excluding: self)
            if !isMouseInside {
                isMouseInside = true
                onHoverChange?(true)
            }
            NSCursor.pointingHand.set()
        }

        override func mouseEntered(with event: NSEvent) {
            Self.reconcileHoveredViews(in: self.window, excluding: self)
            if !isMouseInside {
                isMouseInside = true
                onHoverChange?(true)
            }
            NSCursor.pointingHand.set()
            DispatchQueue.main.async { [weak self] in
                guard let self, Self.isMouseInsideAnyView(in: self.window) else { return }
                NSCursor.pointingHand.set()
            }
        }

        override func mouseExited(with event: NSEvent) {
            if let window = self.window, window.isVisible {
                let localPoint = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if self.bounds.contains(localPoint) {
                    NSCursor.pointingHand.set()
                    return
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { [weak self] in
                guard let self else { return }
                if let window = self.window, window.isVisible {
                    let localPoint = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                    if self.bounds.contains(localPoint) {
                        if !self.isMouseInside {
                            self.isMouseInside = true
                            self.onHoverChange?(true)
                        }
                        return
                    }
                }
                if self.isMouseInside {
                    self.isMouseInside = false
                    self.onHoverChange?(false)
                }
                let hostWindow = self.window
                Self.reconcileHoveredViews(in: hostWindow)
                if Self.isMouseInsideAnyView(in: hostWindow) {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }

        override func mouseDown(with event: NSEvent) {
            onClick?()
        }
    }
}

enum PanelKeyNavigationCommand {
    case moveUp
    case moveDown
    case moveLeft
    case moveRight
    case confirmSelection
    case openInlineReply
    case togglePiP
    case escape
}

/// Synchronizes the native window and SwiftUI appearance, hides MenuBarExtra's internal NSVisualEffectView backdrop,
/// and provides keyboard navigation monitoring while the panel is open.
struct PanelWindowMask: NSViewRepresentable {
    let appearanceMode: AppearanceMode
    var onVisibilityChange: (@MainActor (Bool) -> Void)? = nil
    var onKeyCommand: (@MainActor (PanelKeyNavigationCommand) -> Bool)? = nil

    func makeNSView(context: Context) -> MaskView {
        let view = MaskView(frame: .zero)
        view.appearanceMode = appearanceMode
        view.onVisibilityChange = onVisibilityChange
        view.onKeyCommand = onKeyCommand
        return view
    }

    func updateNSView(_ view: MaskView, context: Context) {
        view.appearanceMode = appearanceMode
        view.onVisibilityChange = onVisibilityChange
        view.onKeyCommand = onKeyCommand
        view.updateWindow()
    }

    final class MaskView: NSView {
        var appearanceMode: AppearanceMode = .automatic
        var onVisibilityChange: (@MainActor (Bool) -> Void)?
        var onKeyCommand: (@MainActor (PanelKeyNavigationCommand) -> Bool)?
        private var updatingWindow = false
        private var lastWindowVisible = false
        private var lastConfiguredAppearanceName: NSAppearance.Name?
        private weak var lastConfiguredWindow: NSWindow?
        private var keyMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                for name in [NSWindow.didResizeNotification,
                             NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                             NSWindow.willCloseNotification, NSWindow.didChangeOcclusionStateNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(windowUpdated), name: name, object: window)
                }
            } else {
                removeKeyMonitor()
                if lastWindowVisible {
                    lastWindowVisible = false
                    onVisibilityChange?(false)
                }
            }
            updateWindow(forceChrome: true)
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateWindow(forceChrome: true)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        @objc private func windowUpdated(_ notification: Notification) {
            let isResize = notification.name == NSWindow.didResizeNotification
            updateWindow(forceChrome: isResize)
        }

        private func installKeyMonitor() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let consumed = MainActor.assumeIsolated {
                    self.handleKeyEvent(event)
                }
                return consumed ? nil : event
            }
        }

        private func removeKeyMonitor() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }

        @MainActor
        private func handleKeyEvent(_ event: NSEvent) -> Bool {
            guard let window = self.window, window.isVisible else { return false }

            let isEditingText: Bool = {
                guard let responder = window.firstResponder else { return false }
                return (responder is NSTextView) || (responder is NSTextField)
            }()

            let hasMarkedIME: Bool = {
                if let textView = window.firstResponder as? NSTextView {
                    return textView.hasMarkedText()
                }
                return false
            }()

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCmdOrCtrlOrOpt = !modifiers.intersection([.command, .control, .option]).isEmpty

            if isEditingText {
                if !hasMarkedIME {
                    if event.keyCode == 53 { // Escape exits text editing first
                        window.makeFirstResponder(nil)
                        _ = onKeyCommand?(.escape)
                        return true
                    }
                    if !hasCmdOrCtrlOrOpt && (event.keyCode == 126 || event.keyCode == 125) {
                        // Up/Down arrow exits text editing and navigates items
                        window.makeFirstResponder(nil)
                        _ = onKeyCommand?(event.keyCode == 126 ? .moveUp : .moveDown)
                        return true
                    }
                }
                return false
            }

            guard !hasCmdOrCtrlOrOpt else { return false }

            switch event.keyCode {
            case 126: // Up arrow
                return onKeyCommand?(.moveUp) == true
            case 125: // Down arrow
                return onKeyCommand?(.moveDown) == true
            case 123: // Left arrow
                return onKeyCommand?(.moveLeft) == true
            case 124: // Right arrow
                return onKeyCommand?(.moveRight) == true
            case 36, 76: // Return / Enter
                return onKeyCommand?(.confirmSelection) == true
            case 44: // '/' key (without Shift)
                if !modifiers.contains(.shift) {
                    return onKeyCommand?(.openInlineReply) == true
                }
                return false
            case 35: // 'p' key (Pin/Unpin Picture-in-Picture)
                if !modifiers.contains(.shift) {
                    return onKeyCommand?(.togglePiP) == true
                }
                return false
            case 53: // Escape
                if onKeyCommand?(.escape) == true {
                    return true
                } else {
                    window.orderOut(nil)
                    return true
                }
            default:
                return false
            }
        }

        func updateWindow(forceChrome: Bool = false) {
            let isVisible = window?.isVisible == true
            var visibilityJustChanged = false
            if isVisible != lastWindowVisible {
                lastWindowVisible = isVisible
                visibilityJustChanged = true
                if isVisible {
                    installKeyMonitor()
                    let targetWindow = window
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        targetWindow?.makeKey()
                    }
                } else {
                    removeKeyMonitor()
                }
                onVisibilityChange?(isVisible)
            }
            guard !updatingWindow, let window, let contentView = window.contentView else { return }
            let desiredAppearance = appearanceMode.appKitAppearance
            let appearanceChanged = window.appearance?.name != desiredAppearance?.name || lastConfiguredAppearanceName != desiredAppearance?.name
            let windowChanged = lastConfiguredWindow !== window
            guard forceChrome || visibilityJustChanged || appearanceChanged || windowChanged else { return }

            updatingWindow = true
            defer { updatingWindow = false }
            lastConfiguredWindow = window
            lastConfiguredAppearanceName = desiredAppearance?.name

            if window.appearance?.name != desiredAppearance?.name {
                window.appearance = desiredAppearance
            }
            if window.isOpaque { window.isOpaque = false }
            if window.backgroundColor != .clear { window.backgroundColor = .clear }

            let frameView = contentView.superview ?? contentView
            Self.hideVisualEffectBackgrounds(in: frameView, stoppingAt: self)
            Self.hideScrollIndicators(in: frameView)

            if !frameView.wantsLayer { frameView.wantsLayer = true }
            if let layer = frameView.layer {
                if layer.cornerRadius != FlatGeometry.panelRadius {
                    layer.cornerRadius = FlatGeometry.panelRadius
                }
                if layer.cornerCurve != .continuous {
                    layer.cornerCurve = .continuous
                }
                if !layer.masksToBounds {
                    layer.masksToBounds = true
                }
            }
            window.invalidateShadow()
        }

        private static func hideVisualEffectBackgrounds(in view: NSView, stoppingAt stopView: NSView) {
            if view === stopView { return }
            if let effectView = view as? NSVisualEffectView {
                if !effectView.isHidden {
                    effectView.state = .inactive
                    effectView.isHidden = true
                }
                return
            }
            for child in view.subviews {
                hideVisualEffectBackgrounds(in: child, stoppingAt: stopView)
            }
        }

        private static func hideScrollIndicators(in view: NSView) {
            if let scrollView = view as? NSScrollView {
                if !scrollView.hasVerticalScroller {
                    scrollView.hasVerticalScroller = true
                }
                if scrollView.verticalScrollElasticity != .allowed {
                    scrollView.verticalScrollElasticity = .allowed
                }
                if scrollView.hasHorizontalScroller {
                    scrollView.hasHorizontalScroller = false
                }
                if scrollView.horizontalScrollElasticity != .none {
                    scrollView.horizontalScrollElasticity = .none
                }
                if scrollView.scrollerStyle != .overlay {
                    scrollView.scrollerStyle = .overlay
                }
                if !scrollView.autohidesScrollers {
                    scrollView.autohidesScrollers = true
                }
                if let vScroller = scrollView.verticalScroller {
                    if vScroller.alphaValue != 0 {
                        vScroller.alphaValue = 0
                    }
                    if !vScroller.isHidden {
                        vScroller.isHidden = true
                    }
                }
            }
            for child in view.subviews {
                hideScrollIndicators(in: child)
            }
        }
    }
}

/// A native AppKit text field for inline terminal prompts inside non-activating `MenuBarExtra` panels.
/// Handles hit-testing above `PointingHandCursorOverlay`, activates key focus on click, and tracks hover state.
struct InlinePromptTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var dark: Bool
    var requestFocus: Bool = false
    var onHoverChange: ((Bool) -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PromptNSTextField {
        let field = PromptNSTextField(frame: .zero)
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.onHoverChange = onHoverChange
        field.onFocusChange = onFocusChange
        field.shouldRequestFocus = requestFocus
        updateAppearance(field, force: true)
        return field
    }

    func updateNSView(_ nsView: PromptNSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.onHoverChange = onHoverChange
        nsView.onFocusChange = onFocusChange
        nsView.shouldRequestFocus = requestFocus
        updateAppearance(nsView, force: false)

        let isEditing: Bool = {
            guard let window = nsView.window else { return false }
            if let editor = nsView.currentEditor() {
                if window.firstResponder === editor { return true }
                if let textView = editor as? NSTextView, textView.hasMarkedText() { return true }
            }
            return window.firstResponder === nsView
        }()

        // Never overwrite stringValue while the field editor is active or has IME marked text
        if !isEditing && nsView.stringValue != text {
            nsView.stringValue = text
        }

        if requestFocus, let window = nsView.window, !isEditing {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(nsView)
            }
        }
    }

    private func updateAppearance(_ field: PromptNSTextField, force: Bool) {
        let appearanceChanged = force || field.lastDark != dark || field.lastPlaceholder != placeholder
        guard appearanceChanged else { return }
        field.lastDark = dark
        field.lastPlaceholder = placeholder

        field.textColor = dark
            ? NSColor(srgbRed: 236.0 / 255, green: 236.0 / 255, blue: 238.0 / 255, alpha: 1.0)
            : NSColor(srgbRed: 38.0 / 255, green: 38.0 / 255, blue: 40.0 / 255, alpha: 1.0)
        let placeholderColor = dark
            ? NSColor(srgbRed: 108.0 / 255, green: 108.0 / 255, blue: 112.0 / 255, alpha: 1.0)
            : NSColor(srgbRed: 154.0 / 255, green: 154.0 / 255, blue: 157.0 / 255, alpha: 1.0)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
            ]
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlinePromptTextField

        init(_ parent: InlinePromptTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocusChange?(true)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if let textView = field.currentEditor() as? NSTextView, textView.hasMarkedText() {
                return
            }
            let current = field.stringValue
            if parent.text != current {
                parent.text = current
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                let current = field.stringValue
                if parent.text != current {
                    parent.text = current
                }
            }
            parent.onFocusChange?(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if textView.hasMarkedText() {
                    return false
                }
                let current = control.stringValue
                if parent.text != current {
                    parent.text = current
                }
                parent.onSubmit?()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if textView.hasMarkedText() {
                    return false
                }
                control.window?.makeFirstResponder(nil)
                parent.onFocusChange?(false)
                return true
            }
            return false
        }
    }

    final class PromptNSTextField: NSTextField {
        var onHoverChange: ((Bool) -> Void)?
        var onFocusChange: ((Bool) -> Void)?
        var lastDark: Bool?
        var lastPlaceholder: String?
        var shouldRequestFocus = false
        private var trackingArea: NSTrackingArea?
        private var isMouseInside = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if shouldRequestFocus, let window {
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window, self.shouldRequestFocus else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(self)
                }
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .iBeam)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.iBeam.set()
        }

        override func mouseEntered(with event: NSEvent) {
            if !isMouseInside {
                isMouseInside = true
                onHoverChange?(true)
            }
            NSCursor.iBeam.set()
        }

        override func mouseMoved(with event: NSEvent) {
            if !isMouseInside {
                isMouseInside = true
                onHoverChange?(true)
            }
            NSCursor.iBeam.set()
        }

        override func mouseExited(with event: NSEvent) {
            if isMouseInside {
                isMouseInside = false
                onHoverChange?(false)
            }
        }

        override func mouseDown(with event: NSEvent) {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            onFocusChange?(true)
            super.mouseDown(with: event)
        }
    }
}
