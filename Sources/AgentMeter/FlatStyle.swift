import AppKit
import SwiftUI

/// Bencho-inspired design system:
/// - Light mode: warm stone paper (`#F7F7F6`) + crisp white board (`#FFFFFF`) + deep ink (`#17181A`) + warm grey secondary (`#5C5B56`)
/// - Dark mode: neutral obsidian (`#0F0F0F`) + graphite board (`#1A1A1A`) + deep inlay (`#121212`) + crisp white ink (`#FFFFFF`)
enum FlatPalette {
    static let blue = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 58.0 / 255, green: 169.0 / 255, blue: 255.0 / 255, alpha: 1)
            : NSColor(srgbRed: 13.0 / 255, green: 153.0 / 255, blue: 255.0 / 255, alpha: 1)
    })

    // --surface: #0F0F0F (dark) / #F7F7F6 (light warm stone)
    static func panelBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 15.0 / 255, green: 15.0 / 255, blue: 15.0 / 255)
            : Color(red: 247.0 / 255, green: 247.0 / 255, blue: 246.0 / 255)
    }

    // --board: #1A1A1A (dark) / #FFFFFF (light)
    static func cardBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 26.0 / 255, green: 26.0 / 255, blue: 26.0 / 255)
            : Color.white
    }

    static func elevatedRowBackground(dark: Bool, hovered: Bool = false) -> Color {
        if dark {
            return hovered
                ? Color(red: 33.0 / 255, green: 33.0 / 255, blue: 33.0 / 255)
                : Color(red: 26.0 / 255, green: 26.0 / 255, blue: 26.0 / 255)
        } else {
            return hovered
                ? Color(red: 252.0 / 255, green: 252.0 / 255, blue: 251.0 / 255)
                : Color.white
        }
    }

    // --surface-2 / --surface-3 recessed tracks & wells
    static func trackBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 22.0 / 255, green: 22.0 / 255, blue: 22.0 / 255)
            : Color(red: 233.0 / 255, green: 231.0 / 255, blue: 226.0 / 255)
    }

    // --pill-thumb: crisp white in light mode, elevated graphite in dark mode
    static func selectedPillBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 46.0 / 255, green: 46.0 / 255, blue: 46.0 / 255)
            : Color.white
    }

    static func terminalWellBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 16.0 / 255, green: 16.0 / 255, blue: 16.0 / 255)
            : Color(red: 246.0 / 255, green: 245.0 / 255, blue: 242.0 / 255)
    }

    static func controlBackground(dark: Bool, highlighted: Bool) -> Color {
        if dark {
            return highlighted
                ? Color(red: 42.0 / 255, green: 42.0 / 255, blue: 42.0 / 255)
                : Color(red: 26.0 / 255, green: 26.0 / 255, blue: 26.0 / 255)
        } else {
            return highlighted
                ? Color(red: 236.0 / 255, green: 235.0 / 255, blue: 231.0 / 255)
                : Color.white
        }
    }

    // --ink: #FFFFFF (dark) / #17181A (light)
    static func inkPrimary(dark: Bool) -> Color {
        dark
            ? Color.white
            : Color(red: 23.0 / 255, green: 24.0 / 255, blue: 26.0 / 255)
    }

    // --ink-3: #9A9A9A (dark) / #5C5B56 (light warm charcoal)
    static func inkSecondary(dark: Bool) -> Color {
        dark
            ? Color(red: 154.0 / 255, green: 154.0 / 255, blue: 154.0 / 255)
            : Color(red: 92.0 / 255, green: 91.0 / 255, blue: 86.0 / 255)
    }

    // --ink-5: #6B6B6B (dark) / #85847E (light muted stone)
    static func inkTertiary(dark: Bool) -> Color {
        dark
            ? Color(red: 107.0 / 255, green: 107.0 / 255, blue: 107.0 / 255)
            : Color(red: 133.0 / 255, green: 132.0 / 255, blue: 126.0 / 255)
    }

    static func hairlineBorder(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.08) : Color(red: 23.0 / 255, green: 24.0 / 255, blue: 26.0 / 255).opacity(0.075)
    }

    static func conflictWarningForeground(dark: Bool) -> Color {
        dark
            ? Color(red: 0.98, green: 0.68, blue: 0.22)
            : Color(red: 0.80, green: 0.38, blue: 0.04)
    }

    static func conflictWarningBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 0.32, green: 0.20, blue: 0.08)
            : Color(red: 1.0, green: 0.93, blue: 0.82)
    }

    static func amberAlertForeground(dark: Bool) -> Color {
        dark
            ? Color(red: 0.98, green: 0.70, blue: 0.24)
            : Color(red: 0.82, green: 0.44, blue: 0.06)
    }

    static func amberAlertBackground(dark: Bool) -> Color {
        dark
            ? Color(red: 0.28, green: 0.18, blue: 0.07)
            : Color(red: 1.0, green: 0.95, blue: 0.86)
    }

    static func dangerInterruptForeground(dark: Bool) -> Color {
        dark
            ? Color(red: 0.98, green: 0.44, blue: 0.48)
            : Color(red: 0.82, green: 0.18, blue: 0.24)
    }

    static func dangerInterruptBackground(dark: Bool, hovered: Bool) -> Color {
        if dark {
            return hovered
                ? Color(red: 0.42, green: 0.14, blue: 0.18)
                : Color(red: 0.28, green: 0.11, blue: 0.14)
        } else {
            return hovered
                ? Color(red: 1.0, green: 0.84, blue: 0.86)
                : Color(red: 1.0, green: 0.91, blue: 0.92)
        }
    }
}

enum FlatGeometry {
    static let panelRadius: CGFloat = 20
    static let cardRadius: CGFloat = 15
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
                            dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08),
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
                    .fill(FlatPalette.controlBackground(dark: dark, highlighted: highlighted))
                    .overlay {
                        shape.strokeBorder(
                            dark
                                ? Color.white.opacity(highlighted ? 0.16 : 0.08)
                                : Color(red: 23.0 / 255, green: 24.0 / 255, blue: 26.0 / 255).opacity(highlighted ? 0.14 : 0.075),
                            lineWidth: 1
                        )
                    }
                    .shadow(color: .black.opacity(dark ? 0 : 0.03), radius: 1.5, x: 0, y: 1)
            }
    }
}

/// A circular icon button backed directly by `PointingHandCursorOverlay` so its pointing-hand cursor
/// and hover state work 100% reliably inside non-activating `MenuBarExtra` panels.
struct FlatIconButton: View {
    let icon: String
    var size: CGFloat = 32
    var iconSize: CGFloat = 13
    var rotatesOnHover: Bool = false
    var tooltip: String? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(.primary.opacity(hovered ? 1.0 : 0.86))
            .rotationEffect(.degrees(rotatesOnHover && hovered && !reduceMotion ? 20 : 0))
            .frame(width: size, height: size)
            .modifier(FlatControlSurface(shape: Circle(), highlighted: hovered))
            .contentShape(Circle())
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

/// A capsule text button backed directly by `PointingHandCursorOverlay`.
struct FlatCapsuleButton: View {
    let title: String
    var compact: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        Text(title)
            .font(.system(size: compact ? 12 : 13.5, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, compact ? 14 : 20)
            .padding(.vertical, compact ? 7 : 11)
            .modifier(FlatControlSurface(shape: Capsule(), highlighted: hovered))
            .contentShape(Capsule())
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
                options: [.inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways],
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
            if !isMouseInside {
                isMouseInside = true
                onHoverChange?(true)
            }
            NSCursor.pointingHand.set()
        }

        override func mouseEntered(with event: NSEvent) {
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
        private var keyMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                for name in [NSWindow.didUpdateNotification, NSWindow.didResizeNotification,
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
            updateWindow()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            updateWindow()
        }

        override func layout() {
            super.layout()
            updateWindow()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateWindow()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        @objc private func windowUpdated(_ notification: Notification) { updateWindow() }

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

        func updateWindow() {
            let isVisible = window?.isVisible == true
            if isVisible != lastWindowVisible {
                lastWindowVisible = isVisible
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
            guard !updatingWindow, let window, let contentView = window.contentView,
                  bounds.width > 0, bounds.height > 0 else { return }
            updatingWindow = true
            defer { updatingWindow = false }
            let desiredAppearance = appearanceMode.appKitAppearance
            if window.appearance?.name != desiredAppearance?.name {
                window.appearance = desiredAppearance
            }
            if window.isOpaque { window.isOpaque = false }
            if window.backgroundColor != .clear { window.backgroundColor = .clear }

            let frameView = contentView.superview ?? contentView
            Self.hideVisualEffectBackgrounds(in: frameView, stoppingAt: self)

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
        field.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
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

        field.textColor = dark ? NSColor(white: 0.94, alpha: 1.0) : NSColor(white: 0.12, alpha: 1.0)
        let placeholderColor = dark ? NSColor(white: 0.46, alpha: 1.0) : NSColor(white: 0.54, alpha: 1.0)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
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

