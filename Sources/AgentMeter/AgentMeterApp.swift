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
            NSApplication.shared.activate(ignoringOtherApps: true)
            for window in NSApplication.shared.windows where window.isVisible {
                if let button = Self.statusButton(in: window.contentView) {
                    button.performClick(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        for win in NSApplication.shared.windows where win.isVisible {
                            let className = NSStringFromClass(type(of: win))
                            if !className.contains("StatusBar") {
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
