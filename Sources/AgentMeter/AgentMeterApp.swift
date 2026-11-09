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
            MenuBarStatusLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }

    fileprivate static func accessibilityLabel(for state: MenuBarVisualState, language: AppLanguage) -> String {
        let en = language == .english
        switch state {
        case .needsInput(let count):
            return en ? "Agent Activity (\(count) waiting for confirmation)" : "Agent 动态（\(count) 个会话等待确认）"
        case .stuck(let count):
            return en ? "Agent Activity (\(count) stalled)" : "Agent 动态（\(count) 个会话长时卡住）"
        case .unreadCompleted(let count):
            return en ? "Agent Activity (\(count) newly completed)" : "Agent 动态（\(count) 个已完成的任务）"
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

    fileprivate static func menuBarIcon(visualState: MenuBarVisualState) -> NSImage {
        let countNumber: Int? = {
            switch visualState {
            case .needsInput(let count), .stuck(let count), .unreadCompleted(let count):
                return max(1, count)
            case .working, .idle:
                return nil
            }
        }()

        let countText = countNumber.map { "\($0)" }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .bold)
        let textWidth: CGFloat = {
            guard let countText else { return 0 }
            let attr: [NSAttributedString.Key: Any] = [.font: font]
            return ceil((countText as NSString).size(withAttributes: attr).width)
        }()

        let badgeW: CGFloat = 28.0
        let badgeH: CGFloat = 16.0
        let totalW: CGFloat = countText != nil ? (badgeW + 4.5 + textWidth + 2.0) : (badgeW + 2.0)
        let totalH: CGFloat = 18.0

        let image = NSImage(size: NSSize(width: totalW, height: totalH), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)

            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
                NSColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
            }

            let primaryColor: NSColor
            let secondaryColor: NSColor
            let bgTint: NSColor
            let sideGlow: NSColor
            let borderColor: NSColor

            switch (visualState, isDark) {
            case (.needsInput, true):
                primaryColor = srgb(253, 230, 138)
                secondaryColor = srgb(251, 191, 36)
                bgTint = srgb(33, 24, 9)
                sideGlow = srgb(245, 158, 11, 0.26)
                borderColor = srgb(251, 191, 36, 0.68)
            case (.needsInput, false):
                primaryColor = srgb(180, 83, 9)
                secondaryColor = srgb(217, 119, 6)
                bgTint = srgb(255, 251, 235)
                sideGlow = srgb(245, 158, 11, 0.16)
                borderColor = srgb(217, 119, 6, 0.45)

            case (.unreadCompleted, true):
                primaryColor = srgb(74, 222, 128)
                secondaryColor = srgb(134, 239, 172)
                bgTint = srgb(11, 30, 22)
                sideGlow = srgb(16, 185, 129, 0.24)
                borderColor = srgb(74, 222, 128, 0.56)
            case (.unreadCompleted, false):
                primaryColor = srgb(5, 150, 105)
                secondaryColor = srgb(16, 185, 129)
                bgTint = srgb(236, 253, 245)
                sideGlow = srgb(16, 185, 129, 0.14)
                borderColor = srgb(5, 150, 105, 0.38)

            case (.stuck, true):
                primaryColor = srgb(248, 113, 113)
                secondaryColor = srgb(239, 68, 68)
                bgTint = srgb(34, 13, 16)
                sideGlow = srgb(239, 68, 68, 0.26)
                borderColor = srgb(248, 113, 113, 0.64)
            case (.stuck, false):
                primaryColor = srgb(220, 38, 38)
                secondaryColor = srgb(239, 68, 68)
                bgTint = srgb(254, 242, 242)
                sideGlow = srgb(239, 68, 68, 0.15)
                borderColor = srgb(220, 38, 38, 0.42)

            case (.working, true), (.idle, true):
                primaryColor = srgb(148, 163, 184)
                secondaryColor = srgb(203, 213, 225)
                bgTint = srgb(20, 23, 32)
                sideGlow = srgb(148, 163, 184, 0.10)
                borderColor = srgb(255, 255, 255, 0.20)
            case (.working, false), (.idle, false):
                primaryColor = srgb(100, 116, 139)
                secondaryColor = srgb(71, 85, 105)
                bgTint = srgb(241, 245, 249)
                sideGlow = srgb(100, 116, 139, 0.08)
                borderColor = srgb(15, 23, 42, 0.18)
            }

            let badgeRect = CGRect(x: 1.0, y: (totalH - badgeH) / 2.0, width: badgeW, height: badgeH)
            let cornerRadius: CGFloat = 4.5
            let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

            // 1. Clipped badge background + side glow + glyph
            ctx.saveGState()
            ctx.addPath(badgePath)
            ctx.clip()

            ctx.setFillColor(bgTint.cgColor)
            ctx.fill(badgeRect)

            if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
               let grad = CGGradient(colorsSpace: colorSpace, colors: [sideGlow.cgColor, NSColor.clear.cgColor] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: badgeRect.minX, y: badgeRect.midY),
                    end: CGPoint(x: badgeRect.minX + badgeW * 0.45, y: badgeRect.midY),
                    options: []
                )
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: badgeRect.maxX, y: badgeRect.midY),
                    end: CGPoint(x: badgeRect.maxX - badgeW * 0.45, y: badgeRect.midY),
                    options: []
                )
            }

            let cx = badgeRect.midX
            let cy = badgeRect.midY
            let scale: CGFloat = badgeH / 20.0

            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.scaleBy(x: scale, y: scale)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(1.85)

            switch visualState {
            case .unreadCompleted:
                // Happy eyes `^ ^` (in non-flipped coordinates, y+ is up)
                ctx.setStrokeColor(primaryColor.cgColor)
                let gap: CGFloat = 3.3
                for ox in [-gap, gap] {
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: ox - 2.1, y: -1.1))
                    ctx.addQuadCurve(to: CGPoint(x: ox + 2.1, y: -1.1), control: CGPoint(x: ox, y: 2.2))
                    ctx.strokePath()
                }

            case .stuck:
                // Red dizzy eyes `✕ ✕`
                ctx.setStrokeColor(primaryColor.cgColor)
                let gap: CGFloat = 3.5
                let r: CGFloat = 1.95
                for ox in [-gap, gap] {
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: ox - r, y: -r))
                    ctx.addLine(to: CGPoint(x: ox + r, y: r))
                    ctx.move(to: CGPoint(x: ox + r, y: -r))
                    ctx.addLine(to: CGPoint(x: ox - r, y: r))
                    ctx.strokePath()
                }

            case .needsInput, .working, .idle:
                // Terminal prompt `>_` ( matching the top-right Idle / NeedsInput badge )
                let chX: CGFloat = -3.6
                ctx.setStrokeColor(primaryColor.cgColor)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: chX - 1.4, y: 2.5))
                ctx.addLine(to: CGPoint(x: chX + 1.3, y: 0))
                ctx.addLine(to: CGPoint(x: chX - 1.4, y: -2.5))
                ctx.strokePath()

                ctx.setStrokeColor(secondaryColor.cgColor)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0.8, y: -2.4))
                ctx.addLine(to: CGPoint(x: 4.8, y: -2.4))
                ctx.strokePath()
            }
            ctx.restoreGState()
            ctx.restoreGState()

            // 2. Rounded border
            let insetRect = badgeRect.insetBy(dx: 0.55, dy: 0.55)
            let borderPath = CGPath(roundedRect: insetRect, cornerWidth: cornerRadius - 0.3, cornerHeight: cornerRadius - 0.3, transform: nil)
            ctx.addPath(borderPath)
            ctx.setStrokeColor(borderColor.cgColor)
            ctx.setLineWidth(1.1)
            ctx.strokePath()

            // 3. Optional right-hand count number (ONLY for needsInput / unreadCompleted / stuck)
            if let countText {
                let numberColor: NSColor = {
                    switch visualState {
                    case .needsInput:
                        return secondaryColor
                    case .unreadCompleted, .stuck, .working, .idle:
                        return primaryColor
                    }
                }()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: numberColor,
                ]
                let strSize = (countText as NSString).size(withAttributes: attrs)
                let textRect = NSRect(
                    x: badgeRect.maxX + 4.5,
                    y: (totalH - strSize.height) / 2.0 - 0.3,
                    width: strSize.width + 2.0,
                    height: strSize.height
                )
                (countText as NSString).draw(in: textRect, withAttributes: attrs)
            }

            return true
        }
        image.isTemplate = false
        return image
    }
}

private struct MenuBarStatusLabel: View {
    @Bindable var model: AgentMeterModel

    var body: some View {
        let visualState = model.menuBarVisualState
        Image(nsImage: AgentMeterApp.menuBarIcon(visualState: visualState))
            .accessibilityLabel(AgentMeterApp.accessibilityLabel(for: visualState, language: model.language))
            .help(model.menuTitle())
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: AgentMeterPanelController?
    private var miniConfirmController: AgentMiniConfirmController?
    private var pipController: AgentPiPController?
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--dump") {
            let isDemoFlag = ProcessInfo.processInfo.arguments.contains("--demo")
            Task { @MainActor in
                let tracker = AgentActivityTracker()
                let res = await tracker.poll(isDemo: isDemoFlag)
                for item in res.items {
                    let ctxStr = item.contextPercentUsed.map { "\($0)%" } ?? "-"
                    let diffStr = item.gitDiff.map { "+\($0.insertions)/-\($0.deletions)(\($0.changedFiles)f)" } ?? "-"
                    let branchStr = item.gitBranch ?? "-"
                    let collisionCount = item.hasWorkspaceCollision ? item.collisionPeerCount : 0
                    let previewStr = item.terminalPreviewLines.joined(separator: " // ")
                    let hostStr = item.terminalHost.rawValue.lowercased()
                    print("DUMP_ITEM | id=\(item.id) | host=\(hostStr) | family=\(item.family.rawValue) | status=\(item.status.rawValue) | pid=\(item.pid ?? 0) | branch=\(branchStr) | worktree=\(item.isGitWorktree) | collision=\(collisionCount) | ctx=\(ctxStr) | diff=\(diffStr) | title=\(item.title) | subtitle=\(item.subtitleText()) | preview=\(previewStr)")
                }
                NSApplication.shared.terminate(nil)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--test-ghostty") {
            Task { @MainActor in
                let savedHost = UserDefaults.standard.string(forKey: "preferredTerminalHost")
                defer {
                    if let savedHost {
                        UserDefaults.standard.set(savedHost, forKey: "preferredTerminalHost")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "preferredTerminalHost")
                    }
                    UserDefaults.standard.synchronize()
                }
                let model = AgentMeterModel.shared
                model.preferredTerminalHost = .rex
                let resolvedRex = model.resolvedLaunchTerminalHost()
                model.preferredTerminalHost = .ghostty
                let resolvedGhostty = model.resolvedLaunchTerminalHost()
                model.preferredTerminalHost = .auto
                let resolvedAuto = model.resolvedLaunchTerminalHost()
                let prefOK = (resolvedRex == .rex) && (resolvedGhostty == .ghostty)
                print("TEST_GHOSTTY_PREFS | success=\(prefOK) | rex=\(resolvedRex.rawValue) | ghostty=\(resolvedGhostty.rawValue) | auto=\(resolvedAuto.rawValue)")
                let selfTestOK = AgentActivityTracker.runGhosttySelfTest()
                print("TEST_GHOSTTY_ALL | success=\(prefOK && selfTestOK)")
                NSApplication.shared.terminate(nil)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--test-history") {
            Task { @MainActor in
                let tracker = AgentActivityTracker()
                let savedKeys = UserDefaults.standard.stringArray(forKey: AgentActivityTracker.deletedHistoryDefaultsKey)
                func restoreSavedKeys() {
                    if let savedKeys {
                        UserDefaults.standard.set(savedKeys, forKey: AgentActivityTracker.deletedHistoryDefaultsKey)
                    } else {
                        UserDefaults.standard.removeObject(forKey: AgentActivityTracker.deletedHistoryDefaultsKey)
                    }
                    UserDefaults.standard.synchronize()
                }

                // 1. Verify live history discovery across all 4 CLI Agent families
                let liveHist = await tracker.discoverHistoricalSessions(liveItems: [], isDemo: false)
                let codexCount = liveHist.filter { $0.family == .codex }.count
                let claudeCount = liveHist.filter { $0.family == .claude }.count
                let copilotCount = liveHist.filter { $0.family == .copilot }.count
                let agyCount = liveHist.filter { $0.family == .antigravity }.count
                print("TEST_HISTORY | total=\(liveHist.count) | codex=\(codexCount) | claude=\(claudeCount) | copilot=\(copilotCount) | antigravity=\(agyCount)")
                for family in AgentFamily.allCases {
                    for h in liveHist.filter({ $0.family == family }).prefix(2) {
                        print("TEST_SAMPLE | family=\(family.shortName) | sid=\(h.sessionID) | cwd=\(h.cwdPath) | title=\(h.title)")
                    }
                }

                // 2. Verify delete behavior on demo/synthetic history item
                let beforeDemo = await tracker.discoverHistoricalSessions(liveItems: [], isDemo: true)
                guard let target = beforeDemo.first else {
                    print("TEST_DELETE_FAIL | empty demo history")
                    restoreSavedKeys()
                    NSApplication.shared.terminate(nil)
                    return
                }
                let ok = await tracker.deleteHistoricalSession(target)
                let afterDemo = await tracker.discoverHistoricalSessions(liveItems: [], isDemo: true)
                let removed = !afterDemo.contains(where: { $0.id == target.id || $0.sessionID == target.sessionID })
                print("TEST_DELETE_RESULT | success=\(ok && removed) | before=\(beforeDemo.count) | after=\(afterDemo.count) | deleted_id=\(target.id)")

                // 3. Verify physical file-backed deletion on a temporary synthetic entry
                let tempSid = "00000000-test-delete-session-9999"
                let home = FileManager.default.homeDirectoryForCurrentUser
                let dummyProjectDir = home.appendingPathComponent(".claude/projects/-Users-yyc-code-AgentMeter")
                let dummyJsonl = dummyProjectDir.appendingPathComponent("\(tempSid).jsonl")
                try? FileManager.default.createDirectory(at: dummyProjectDir, withIntermediateDirectories: true)
                try? "{\"type\":\"test\"}\n".write(to: dummyJsonl, atomically: true, encoding: .utf8)
                let existedBefore = FileManager.default.fileExists(atPath: dummyJsonl.path)

                let tempItem = AgentHistorySessionItem(
                    id: "claude:\(tempSid)",
                    sessionID: tempSid,
                    family: .claude,
                    title: "Temp Test Session",
                    workspace: "AgentMeter",
                    cwdPath: "/Users/yyc/code/AgentMeter",
                    gitBranch: nil,
                    updatedAt: Date()
                )
                let model = AgentMeterModel.shared
                model.historicalSessions.insert(tempItem, at: 0)
                model.deleteHistoricalSession(tempItem)
                try? await Task.sleep(for: .milliseconds(350))
                let modelRemoved = !model.historicalSessions.contains(where: { $0.sessionID == tempSid })
                let persistedDeleted = AgentActivityTracker.loadDeletedHistoryKeys().contains(tempSid)
                let filePhysicallyDeleted = !FileManager.default.fileExists(atPath: dummyJsonl.path)
                print("TEST_PHYSICAL_DELETE | success=\(existedBefore && modelRemoved && persistedDeleted && filePhysicallyDeleted) | file_existed_before=\(existedBefore) | file_deleted=\(filePhysicallyDeleted)")

                restoreSavedKeys()
                NSApplication.shared.terminate(nil)
            }
            return
        }
        let isPreview = ProcessInfo.processInfo.arguments.contains("--preview")
        NSApplication.shared.setActivationPolicy(isPreview ? .regular : .accessory)
        AgentMeterModel.shared.applyAppearance()
        panelController = AgentMeterPanelController(model: AgentMeterModel.shared)
        miniConfirmController = AgentMiniConfirmController(model: AgentMeterModel.shared)
        pipController = AgentPiPController(model: AgentMeterModel.shared)
        AgentMeterModel.shared.onMenuBarStateChanged = { [weak self] in
            self?.syncMenuBarButtons()
        }
        AgentMeterModel.shared.onMiniConfirmStateChanged = { [weak self] in
            self?.miniConfirmController?.syncWithModel()
        }
        AgentMeterModel.shared.onPiPStateChanged = { [weak self] in
            self?.pipController?.syncWithModel()
        }
        AgentMeterModel.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.syncMenuBarButtons()
        }

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
            self?.miniConfirmController?.hide(animated: false)
            NSApplication.shared.activate(ignoringOtherApps: true)
            for window in NSApplication.shared.windows where window.isVisible {
                if let button = Self.statusButton(in: window.contentView) {
                    button.performClick(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        for win in NSApplication.shared.windows where win.isVisible {
                            let className = NSStringFromClass(type(of: win))
                            if !className.contains("StatusBar") && !className.contains("MiniConfirm") && !className.contains("PiPWindow") {
                                win.makeKey()
                            }
                        }
                    }
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
                return !className.contains("StatusBar") && !className.contains("MiniConfirm") && !className.contains("PiPWindow")
            }
            if hasVisibleMenuWindow || AgentMeterModel.shared.isPanelOpen {
                for window in NSApplication.shared.windows where window.isVisible {
                    let className = NSStringFromClass(type(of: window))
                    if className.contains("StatusBar") || className.contains("MiniConfirm") || className.contains("PiPWindow") { continue }
                    window.orderOut(nil)
                }
                self.panelController?.stop()
                AgentMeterModel.shared.panelDidClose()
            } else {
                self.openPanel()
            }
        }
    }

    func syncMenuBarButtons() {
        let model = AgentMeterModel.shared
        let state = model.menuBarVisualState
        let icon = AgentMeterApp.menuBarIcon(visualState: state)
        let title = model.menuTitle()
        for window in NSApplication.shared.windows {
            let className = NSStringFromClass(type(of: window))
            guard className.contains("StatusBar") else { continue }
            if let button = Self.statusButton(in: window.contentView) {
                if button.image != nil {
                    button.image = icon
                }
                button.toolTip = title
                button.needsDisplay = true
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
        AgentMeterModel.shared.releaseKeepAwakeAssertion()
        pipController?.stop()
        miniConfirmController?.stop()
        panelController?.stop()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
