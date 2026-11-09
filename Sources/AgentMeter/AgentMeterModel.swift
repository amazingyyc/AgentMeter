import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation
import ServiceManagement

enum MenuBarVisualState: Equatable {
    case idle(onlineCount: Int)
    case working(count: Int)
    case needsInput(count: Int)
    case stuck(count: Int)
    case unreadCompleted(count: Int)
}

enum PiPCorner: String, CaseIterable, Sendable {
    case bottomRight = "br"
    case topRight = "tr"
    case bottomLeft = "bl"
    case topLeft = "tl"
}

@MainActor @Observable
final class AgentMeterModel {
    static let shared = AgentMeterModel()

    var agentActivities: [AgentActivityItem] = []
    var historicalSessions: [AgentHistorySessionItem] = []
    var recentLaunchWorkspaces: [LaunchWorkspaceItem] = []
    var customLaunchCommands: [String: String] = [:]
    var promptQueues: [String: [String]] = [:]
    var preferredLaunchFamily: AgentFamily {
        didSet {
            UserDefaults.standard.set(preferredLaunchFamily.rawValue, forKey: "preferredLaunchFamily")
        }
    }
    var preferredTerminalHost: PreferredTerminalHost {
        didSet {
            UserDefaults.standard.set(preferredTerminalHost.rawValue, forKey: "preferredTerminalHost")
        }
    }
    var hasUnseenMenuBarCompletion = false
    var isSleeping = false
    var isPanelOpen = false
    var isDemo = false
    var completionSoundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(completionSoundEnabled, forKey: "completionSoundEnabled")
            if completionSoundEnabled && !oldValue {
                playCompletionSound()
            }
        }
    }
    var globalHotkeysEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalHotkeysEnabled, forKey: "globalHotkeysEnabled")
            onGlobalHotkeysPreferenceChanged?(globalHotkeysEnabled)
        }
    }
    var launchAtLoginEnabled: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLoginEnabled, forKey: "launchAtLoginEnabled")
            applyLaunchAtLogin(launchAtLoginEnabled)
        }
    }
    var preventSleepWhileWorking: Bool {
        didSet {
            UserDefaults.standard.set(preventSleepWhileWorking, forKey: "preventSleepWhileWorking")
            updateKeepAwakeAssertion()
        }
    }
    var isKeepAwakeAssertionActive = false
    var dismissedMiniConfirmTokens: Set<String> = []
    var pinnedPiPActivityID: String? = nil
    var isPiPCollapsedPill = false
    var pipCorner: PiPCorner {
        didSet {
            UserDefaults.standard.set(pipCorner.rawValue, forKey: "pipCorner")
        }
    }
    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
            onMenuBarStateChanged?()
            onPiPStateChanged?()
        }
    }
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            onMenuBarStateChanged?()
            Task { @MainActor in await pollAgents() }
        }
    }

    @ObservationIgnored private let agentTracker = AgentActivityTracker()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var agentTimerTask: Task<Void, Never>?
    @ObservationIgnored private var activeSound: NSSound?
    @ObservationIgnored private var pausedQueueKeys: Set<String> = []
    @ObservationIgnored private var dispatchingQueueKeys: Set<String> = []
    @ObservationIgnored private var hasSeededDemoQueue = false
    @ObservationIgnored private var hasDemoConfirmItem = false
    @ObservationIgnored private var sleepAssertionID: IOPMAssertionID = IOPMAssertionID(0)
    @ObservationIgnored var onGlobalHotkeysPreferenceChanged: (@MainActor (Bool) -> Void)?
    @ObservationIgnored var onMenuBarStateChanged: (@MainActor () -> Void)?
    @ObservationIgnored var onMiniConfirmStateChanged: (@MainActor () -> Void)?
    @ObservationIgnored var onPiPStateChanged: (@MainActor () -> Void)?

    init() {
        let defaults = UserDefaults.standard
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .automatic
        language = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .english
        preferredLaunchFamily = AgentFamily(rawValue: defaults.string(forKey: "preferredLaunchFamily") ?? "") ?? .claude
        preferredTerminalHost = PreferredTerminalHost(rawValue: defaults.string(forKey: "preferredTerminalHost") ?? "") ?? .auto
        pipCorner = PiPCorner(rawValue: defaults.string(forKey: "pipCorner") ?? "") ?? .bottomRight
        if let savedCmds = defaults.dictionary(forKey: "customLaunchCommands") as? [String: String] {
            customLaunchCommands = savedCmds
        }
        if defaults.object(forKey: "completionSoundEnabled") == nil {
            completionSoundEnabled = true
        } else {
            completionSoundEnabled = defaults.bool(forKey: "completionSoundEnabled")
        }
        if defaults.object(forKey: "globalHotkeysEnabled") == nil {
            globalHotkeysEnabled = true
        } else {
            globalHotkeysEnabled = defaults.bool(forKey: "globalHotkeysEnabled")
        }
        if defaults.object(forKey: "launchAtLoginEnabled") == nil {
            launchAtLoginEnabled = true
            defaults.set(true, forKey: "launchAtLoginEnabled")
        } else {
            launchAtLoginEnabled = defaults.bool(forKey: "launchAtLoginEnabled")
        }
        if defaults.object(forKey: "preventSleepWhileWorking") == nil {
            preventSleepWhileWorking = true
            defaults.set(true, forKey: "preventSleepWhileWorking")
        } else {
            preventSleepWhileWorking = defaults.bool(forKey: "preventSleepWhileWorking")
        }
        applyLaunchAtLogin(launchAtLoginEnabled)
    }

    func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            // Ignore registration errors when running as an unbundled swift build binary
        }
    }

    func launchCommand(for family: AgentFamily) -> String {
        if let custom = customLaunchCommands[family.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return family.defaultLaunchCommand
    }

    func setLaunchCommand(_ command: String, for family: AgentFamily) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == family.defaultLaunchCommand {
            customLaunchCommands.removeValue(forKey: family.rawValue)
        } else {
            customLaunchCommands[family.rawValue] = command
        }
        UserDefaults.standard.set(customLaunchCommands, forKey: "customLaunchCommands")
    }

    func resetLaunchCommandsToDefault() {
        customLaunchCommands.removeAll()
        UserDefaults.standard.removeObject(forKey: "customLaunchCommands")
    }

    var hasCustomLaunchCommands: Bool {
        !customLaunchCommands.isEmpty
    }

    func applyAppearance() {
        NSApplication.shared.appearance = nil
    }

    func playCompletionSound() {
        guard completionSoundEnabled else { return }
        if let sound = NSSound(named: NSSound.Name("Glass")) ?? NSSound(named: NSSound.Name("Ping")) {
            activeSound?.stop()
            let copy = sound.copy() as? NSSound ?? sound
            activeSound = copy
            copy.play()
        } else {
            NSSound.beep()
        }
    }

    var activeAgentWorkingCount: Int {
        agentActivities.filter { $0.status == .working || $0.status == .needsInput }.count
    }

    var activeAgentNeedsInputCount: Int {
        agentActivities.filter { $0.status == .needsInput }.count
    }

    var activeAgentStuckCount: Int {
        let now = Date()
        return agentActivities.filter { $0.status == .working && $0.isLongRunningWorking(now: now) }.count
    }

    var unreadCompletionCount: Int {
        agentActivities.filter { $0.isUnreadCompletion }.count
    }

    var completedSessionCount: Int {
        agentActivities.filter { $0.status == .completed }.count
    }

    var showMenuBarCompletionDot: Bool {
        (hasUnseenMenuBarCompletion && unreadCompletionCount > 0) || activeAgentNeedsInputCount > 0 || activeAgentStuckCount > 0
    }

    var menuBarVisualState: MenuBarVisualState {
        let needsInput = activeAgentNeedsInputCount
        if needsInput > 0 {
            return .needsInput(count: needsInput)
        }
        let stuck = activeAgentStuckCount
        if stuck > 0 {
            return .stuck(count: stuck)
        }
        let completed = completedSessionCount
        if completed > 0 {
            return .unreadCompleted(count: completed)
        }
        return .idle(onlineCount: agentActivities.count)
    }

    func miniConfirmToken(for item: AgentActivityItem) -> String {
        let lastLine = item.terminalPreviewLines.last ?? ""
        return "\(item.id)|\(lastLine)"
    }

    var activeMiniConfirmItem: AgentActivityItem? {
        guard !isPanelOpen else { return nil }
        return agentActivities.first { item in
            guard item.status == .needsInput else { return false }
            if item.id == pinnedPiPActivityID { return false }
            return !dismissedMiniConfirmTokens.contains(miniConfirmToken(for: item))
        }
    }

    func dismissMiniConfirmCard(for item: AgentActivityItem) {
        dismissedMiniConfirmTokens.insert(miniConfirmToken(for: item))
        onMiniConfirmStateChanged?()
    }

    var activePiPItem: AgentActivityItem? {
        guard let pinnedID = pinnedPiPActivityID else { return nil }
        return agentActivities.first { $0.id == pinnedID }
    }

    func isSessionPinnedInPiP(_ item: AgentActivityItem) -> Bool {
        pinnedPiPActivityID == item.id
    }

    func togglePiPSession(_ item: AgentActivityItem) {
        if pinnedPiPActivityID == item.id {
            pinnedPiPActivityID = nil
            isPiPCollapsedPill = false
        } else {
            pinnedPiPActivityID = item.id
            isPiPCollapsedPill = false
        }
        onPiPStateChanged?()
        onMiniConfirmStateChanged?()
    }

    func closePiP() {
        guard pinnedPiPActivityID != nil else { return }
        pinnedPiPActivityID = nil
        isPiPCollapsedPill = false
        onPiPStateChanged?()
        onMiniConfirmStateChanged?()
    }

    func togglePiPCollapsedPill() {
        isPiPCollapsedPill.toggle()
        onPiPStateChanged?()
    }

    func updateKeepAwakeAssertion() {
        let now = Date()
        let hasActiveNonStuckWorking = agentActivities.contains { item in
            item.status == .working && !item.isLongRunningWorking(now: now)
        }
        let shouldHoldAssertion = preventSleepWhileWorking && !isSleeping && hasActiveNonStuckWorking

        if shouldHoldAssertion {
            if sleepAssertionID == 0 {
                let reason = "AgentMeter: Active CLI Agent Task Running" as CFString
                var newID: IOPMAssertionID = 0
                let kr = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reason,
                    &newID
                )
                if kr == kIOReturnSuccess {
                    sleepAssertionID = newID
                    isKeepAwakeAssertionActive = true
                }
            }
        } else {
            releaseKeepAwakeAssertion()
        }
    }

    func releaseKeepAwakeAssertion() {
        if sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }
        if isKeepAwakeAssertionActive {
            isKeepAwakeAssertionActive = false
        }
    }

    func markAllAsRead() {
        for idx in agentActivities.indices {
            agentActivities[idx].isUnreadCompletion = false
        }
        hasUnseenMenuBarCompletion = false
        agentTracker.clearUnreadCompletions()
        onMenuBarStateChanged?()
    }

    func menuTitle() -> String {
        let en = language == .english
        let needsInput = activeAgentNeedsInputCount
        let stuck = activeAgentStuckCount
        let working = activeAgentWorkingCount
        if needsInput > 0 {
            return en ? "Agent · \(needsInput) Confirm" : "Agent · \(needsInput) 待确认"
        } else if stuck > 0 {
            return en ? "Agent · \(stuck) Stalled" : "Agent · \(stuck) 长时卡住"
        } else if working > 0 {
            return en ? "Agent · \(working) Running" : "Agent · \(working) 运行中"
        } else if showMenuBarCompletionDot {
            return en ? "Agent · Completed" : "Agent · 任务已完成"
        } else if !agentActivities.isEmpty {
            return en ? "Agent · \(agentActivities.count) Online" : "Agent · \(agentActivities.count) 在线"
        } else {
            return "Agent Meter"
        }
    }

    func makeDemoConfirmItem() -> AgentActivityItem {
        let en = language == .english
        return AgentActivityItem(
            id: "demo-live-confirm",
            family: .claude,
            workspace: "AgentMeter",
            cwdPath: "~/code/AgentMeter",
            title: en ? "Run release build & verify IOKit assertion" : "编译打包并验证 IOKit 电源保活断言",
            status: .needsInput,
            isUnreadCompletion: false,
            detail: en ? "Awaiting confirmation" : "等待确认",
            updatedAt: Date().addingTimeInterval(-6),
            pid: nil,
            tty: nil,
            rexPane: nil,
            terminalPreviewLines: [
                "⏺ Bash(./scripts/build-app.sh && pmset -g assertions | grep AgentMeter)",
                "  Build release app bundle and verify PreventUserIdleSystemSleep",
                "Do you want to proceed with running this command?",
                "❯ 1. Yes, allow once",
                "  2. Yes, and don't ask again for ./scripts/build-app.sh in ~/code/AgentMeter",
            ],
            contextPercentUsed: 42,
            gitDiff: GitDiffSummary(changedFiles: 3, insertions: 148, deletions: 19),
            gitBranch: "main"
        )
    }

    func start() {
        guard !started else { return }
        started = true
        if ProcessInfo.processInfo.arguments.contains("--demo-confirm") {
            hasDemoConfirmItem = true
            agentActivities = [makeDemoConfirmItem()]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.onMenuBarStateChanged?()
                self?.onMiniConfirmStateChanged?()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            isDemo = true
            Task { @MainActor in await pollAgents() }
            return
        }
        startAgentMonitor()
    }

    func panelDidOpen() {
        isPanelOpen = true
        hasUnseenMenuBarCompletion = false
        onMenuBarStateChanged?()
        onMiniConfirmStateChanged?()
        Task { @MainActor in await pollAgents() }
    }

    func panelDidClose() {
        isPanelOpen = false
        onMenuBarStateChanged?()
        onMiniConfirmStateChanged?()
    }

    func sleep() {
        isSleeping = true
        releaseKeepAwakeAssertion()
        agentTimerTask?.cancel()
        agentTimerTask = nil
    }

    func wake() {
        isSleeping = false
        startAgentMonitor()
    }

    func jumpToAgentSession(_ item: AgentActivityItem) {
        if let idx = agentActivities.firstIndex(where: { $0.id == item.id }) {
            agentActivities[idx].isUnreadCompletion = false
        }
        if !agentActivities.contains(where: { $0.isUnreadCompletion }) {
            hasUnseenMenuBarCompletion = false
        }
        onMenuBarStateChanged?()
        onMiniConfirmStateChanged?()
        Task { @MainActor in
            _ = await agentTracker.jumpToSession(item)
        }
    }

    func jumpToMostUrgentAgentSession() {
        Task { @MainActor in
            if agentActivities.isEmpty {
                await pollAgents()
            }
            guard let topItem = agentActivities.first else { return }
            jumpToAgentSession(topItem)
        }
    }

    func respondToPermission(_ item: AgentActivityItem, choice: AgentApprovalChoice) {
        let previousActivities = agentActivities
        let previousUnseenCompletion = hasUnseenMenuBarCompletion
        let en = language == .english
        dismissedMiniConfirmTokens.remove(miniConfirmToken(for: item))
        if let idx = agentActivities.firstIndex(where: { $0.id == item.id }) {
            agentActivities[idx].isUnreadCompletion = false
            switch choice {
            case .approvePrimary, .approveSecondary:
                agentActivities[idx].status = .working
                agentActivities[idx].detail = en ? "Running task" : "正在执行任务"
                agentActivities[idx].updatedAt = Date()
            case .deny:
                agentActivities[idx].status = .idle
                agentActivities[idx].detail = en ? "Terminal idle" : "终端待命"
            }
        }
        if !agentActivities.contains(where: { $0.isUnreadCompletion }) && activeAgentNeedsInputCount == 0 {
            hasUnseenMenuBarCompletion = false
        }
        if item.id == "demo-live-confirm" {
            hasDemoConfirmItem = false
            agentActivities.removeAll { $0.id == "demo-live-confirm" }
            updateKeepAwakeAssertion()
            onMenuBarStateChanged?()
            onMiniConfirmStateChanged?()
            onPiPStateChanged?()
            return
        }
        updateKeepAwakeAssertion()
        onMenuBarStateChanged?()
        onMiniConfirmStateChanged?()
        onPiPStateChanged?()
        Task { @MainActor in
            let ok = await agentTracker.respondToPermissionPrompt(item, choice: choice)
            if !isDemo {
                if !ok {
                    agentActivities = previousActivities
                    hasUnseenMenuBarCompletion = previousUnseenCompletion
                    await pollAgents()
                    return
                }
                try? await Task.sleep(for: .milliseconds(650))
                await pollAgents()
            }
        }
    }

    func queueKey(for item: AgentActivityItem) -> String {
        if let sid = item.sessionID, !sid.isEmpty {
            return "sid:\(sid)"
        }
        return "id:\(item.id)"
    }

    func queuedPrompts(for item: AgentActivityItem) -> [String] {
        promptQueues[queueKey(for: item)] ?? []
    }

    func enqueuePrompt(_ item: AgentActivityItem, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = queueKey(for: item)
        pausedQueueKeys.remove(key)
        var current = promptQueues[key] ?? []
        current.append(trimmed)
        promptQueues[key] = current
    }

    func submitOrQueueReply(_ item: AgentActivityItem, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if item.status == .working {
            enqueuePrompt(item, text: trimmed)
        } else {
            pausedQueueKeys.remove(queueKey(for: item))
            sendQuickReply(item, text: trimmed)
        }
    }

    func removeQueuedPrompt(for item: AgentActivityItem, at index: Int) {
        let key = queueKey(for: item)
        guard var current = promptQueues[key], current.indices.contains(index) else { return }
        current.remove(at: index)
        if current.isEmpty {
            promptQueues.removeValue(forKey: key)
            pausedQueueKeys.remove(key)
        } else {
            promptQueues[key] = current
        }
    }

    func popQueuedPromptForEditing(for item: AgentActivityItem, at index: Int = 0) -> String? {
        let key = queueKey(for: item)
        guard var current = promptQueues[key], current.indices.contains(index) else { return nil }
        let popped = current.remove(at: index)
        if current.isEmpty {
            promptQueues.removeValue(forKey: key)
            pausedQueueKeys.remove(key)
        } else {
            promptQueues[key] = current
        }
        return popped
    }

    func dispatchNextQueuedPromptNow(_ item: AgentActivityItem) {
        let key = queueKey(for: item)
        guard var current = promptQueues[key], !current.isEmpty else { return }
        let next = current.removeFirst()
        if current.isEmpty {
            promptQueues.removeValue(forKey: key)
        } else {
            promptQueues[key] = current
        }
        pausedQueueKeys.remove(key)
        sendQuickReply(item, text: next)
    }

    func sendQuickReply(_ item: AgentActivityItem, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = queueKey(for: item)
        pausedQueueKeys.remove(key)
        dispatchingQueueKeys.insert(key)
        dismissedMiniConfirmTokens.remove(miniConfirmToken(for: item))
        let previousActivities = agentActivities
        let previousUnseenCompletion = hasUnseenMenuBarCompletion
        let en = language == .english
        if let idx = agentActivities.firstIndex(where: { $0.id == item.id }) {
            agentActivities[idx].isUnreadCompletion = false
            agentActivities[idx].status = .working
            agentActivities[idx].detail = en ? "Running task" : "正在执行任务"
            agentActivities[idx].updatedAt = Date()
            agentActivities[idx].terminalPreviewLines.append("› \(trimmed)")
        }
        if !agentActivities.contains(where: { $0.isUnreadCompletion }) && activeAgentNeedsInputCount == 0 {
            hasUnseenMenuBarCompletion = false
        }
        if item.id == "demo-live-confirm" {
            hasDemoConfirmItem = false
            agentActivities.removeAll { $0.id == "demo-live-confirm" }
            updateKeepAwakeAssertion()
            onMenuBarStateChanged?()
            onMiniConfirmStateChanged?()
            onPiPStateChanged?()
            return
        }
        updateKeepAwakeAssertion()
        onMenuBarStateChanged?()
        onMiniConfirmStateChanged?()
        onPiPStateChanged?()
        Task { @MainActor in
            defer { dispatchingQueueKeys.remove(key) }
            let ok = await agentTracker.sendInlinePrompt(item, text: trimmed)
            if !isDemo {
                if !ok {
                    agentActivities = previousActivities
                    hasUnseenMenuBarCompletion = previousUnseenCompletion
                    await pollAgents()
                    return
                }
                try? await Task.sleep(for: .milliseconds(700))
                await pollAgents()
            }
        }
    }

    func interruptAgentSession(_ item: AgentActivityItem) {
        let key = queueKey(for: item)
        pausedQueueKeys.insert(key)
        dismissedMiniConfirmTokens.remove(miniConfirmToken(for: item))
        let previousActivities = agentActivities
        let previousUnseenCompletion = hasUnseenMenuBarCompletion
        let en = language == .english
        if let idx = agentActivities.firstIndex(where: { $0.id == item.id }) {
            agentActivities[idx].isUnreadCompletion = false
            agentActivities[idx].status = .idle
            agentActivities[idx].detail = en ? "Interrupted" : "已中断"
            agentActivities[idx].updatedAt = Date()
            agentActivities[idx].terminalPreviewLines.append(en ? "› ^C Interrupted" : "› ^C 已发送中断")
        }
        if !agentActivities.contains(where: { $0.isUnreadCompletion }) && activeAgentNeedsInputCount == 0 {
            hasUnseenMenuBarCompletion = false
        }
        updateKeepAwakeAssertion()
        onMenuBarStateChanged?()
        onMiniConfirmStateChanged?()
        onPiPStateChanged?()
        Task { @MainActor in
            let ok = await agentTracker.interruptSession(item)
            if !isDemo {
                if !ok {
                    agentActivities = previousActivities
                    hasUnseenMenuBarCompletion = previousUnseenCompletion
                    await pollAgents()
                    return
                }
                try? await Task.sleep(for: .milliseconds(650))
                await pollAgents()
            }
        }
    }

    func closeAgentSession(_ item: AgentActivityItem) {
        let key = queueKey(for: item)
        promptQueues.removeValue(forKey: key)
        pausedQueueKeys.remove(key)
        dismissedMiniConfirmTokens.remove(miniConfirmToken(for: item))
        let previousActivities = agentActivities
        let previousUnseenCompletion = hasUnseenMenuBarCompletion
        if pinnedPiPActivityID == item.id {
            pinnedPiPActivityID = nil
            isPiPCollapsedPill = false
        }
        agentActivities.removeAll { $0.id == item.id }
        if !agentActivities.contains(where: { $0.isUnreadCompletion }) {
            hasUnseenMenuBarCompletion = false
        }
        updateKeepAwakeAssertion()
        onMenuBarStateChanged?()
        onMiniConfirmStateChanged?()
        onPiPStateChanged?()
        Task { @MainActor in
            let ok = await agentTracker.closeSession(item)
            if !isDemo {
                if !ok {
                    agentActivities = previousActivities
                    hasUnseenMenuBarCompletion = previousUnseenCompletion
                }
                await pollAgents()
            }
        }
    }

    func refreshLaunchWorkspaces() {
        recentLaunchWorkspaces = agentTracker.discoverLaunchWorkspaceItems(liveItems: agentActivities)
        refreshHistoricalSessions()
    }

    func refreshHistoricalSessions() {
        let liveSnapshot = agentActivities
        let demoFlag = isDemo
        Task { @MainActor in
            historicalSessions = await agentTracker.discoverHistoricalSessions(liveItems: liveSnapshot, isDemo: demoFlag)
        }
    }

    func resolvedLaunchTerminalHost() -> TerminalHostKind {
        switch preferredTerminalHost {
        case .rex:
            return .rex
        case .ghostty:
            return .ghostty
        case .auto:
            // 1. Focused session in host
            if let focusedItem = agentActivities.first(where: \.isFocusedInHost) {
                return focusedItem.terminalHost
            }

            // 2 & 3. Frontmost application check
            if let frontmost = NSWorkspace.shared.frontmostApplication {
                let bundleID = frontmost.bundleIdentifier?.lowercased() ?? ""
                let name = frontmost.localizedName?.lowercased() ?? ""
                if bundleID == "com.mitchellh.ghostty" || name == "ghostty" {
                    return .ghostty
                }
                if bundleID.contains("com.superlogical.rex") || name == "rex beta" || name == "rex" {
                    return .rex
                }
            }

            // 4. Online sessions in agentActivities
            let hasGhosttySession = agentActivities.contains { $0.terminalHost == .ghostty }
            let hasRexSession = agentActivities.contains { $0.terminalHost == .rex }
            if hasGhosttySession && !hasRexSession {
                return .ghostty
            }
            if hasGhosttySession,
               let mostRecent = agentActivities.max(by: { $0.updatedAt < $1.updatedAt }),
               mostRecent.terminalHost == .ghostty {
                return .ghostty
            }
            if hasRexSession && !hasGhosttySession {
                return .rex
            }

            // 5 & 6. Running applications check
            let runningApps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
            let isGhosttyRunning = runningApps.contains { app in
                app.bundleIdentifier?.lowercased() == "com.mitchellh.ghostty" ||
                app.localizedName?.lowercased() == "ghostty"
            }
            let isRexRunning = runningApps.contains { app in
                app.bundleIdentifier?.lowercased().contains("com.superlogical.rex") == true ||
                app.localizedName?.lowercased() == "rex beta" ||
                app.localizedName?.lowercased() == "rex"
            }
            if isGhosttyRunning && !isRexRunning {
                return .ghostty
            }
            if isRexRunning && !isGhosttyRunning {
                return .rex
            }
            if isGhosttyRunning && isRexRunning {
                if let firstHost = agentActivities.first?.terminalHost {
                    return firstHost
                }
                return .ghostty
            }

            if AgentActivityTracker.isGhosttyAppInstalled() && !AgentActivityTracker.isRexBinaryAvailable() {
                return .ghostty
            }
            return .rex
        }
    }

    func resumeOrFocusHistoricalSession(_ item: AgentHistorySessionItem) {
        if let onlineID = item.onlineActivityID,
           let liveItem = agentActivities.first(where: { $0.id == onlineID }) {
            jumpToAgentSession(liveItem)
            return
        }
        recordRecentWorkspace(LaunchWorkspaceItem(path: item.cwdPath, sshTarget: nil))
        let baseCmd = launchCommand(for: item.family)
        let host = resolvedLaunchTerminalHost()
        Task { @MainActor in
            _ = await agentTracker.resumeHistoricalSession(item, baseCommand: baseCmd, preferredHost: host)
            try? await Task.sleep(for: .milliseconds(900))
            await pollAgents()
        }
    }

    func deleteHistoricalSession(_ item: AgentHistorySessionItem) {
        historicalSessions.removeAll { $0.id == item.id || $0.sessionID == item.sessionID }
        Task { @MainActor in
            _ = await agentTracker.deleteHistoricalSession(item)
        }
    }

    func recordRecentWorkspace(_ workspace: LaunchWorkspaceItem) {
        let normalizedPath: String = {
            if workspace.isSSH {
                let trimmed = workspace.path.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "~" : trimmed
            }
            return URL(fileURLWithPath: workspace.path).standardizedFileURL.path
        }()
        let entry: [String: String] = [
            "path": normalizedPath,
            "ssh": workspace.sshTarget ?? "",
        ]
        var current = (UserDefaults.standard.array(forKey: "recentLaunchWorkspaceRecords") as? [[String: String]]) ?? []
        current.removeAll { rec in
            (rec["path"] ?? "") == normalizedPath && (rec["ssh"] ?? "") == (workspace.sshTarget ?? "")
        }
        current.insert(entry, at: 0)
        if current.count > 16 {
            current = Array(current.prefix(16))
        }
        UserDefaults.standard.set(current, forKey: "recentLaunchWorkspaceRecords")
        refreshLaunchWorkspaces()
    }

    func launchWorkspaceSession(family: AgentFamily, workspace: LaunchWorkspaceItem) {
        preferredLaunchFamily = family
        recordRecentWorkspace(workspace)
        let command = launchCommand(for: family)
        let host = resolvedLaunchTerminalHost()
        Task { @MainActor in
            _ = await agentTracker.launchWorkspaceSession(
                family: family,
                workspace: workspace,
                customCommand: command,
                preferredHost: host
            )
            try? await Task.sleep(for: .milliseconds(900))
            await pollAgents()
        }
    }

    func launchNewAgentSession(family: AgentFamily, cwdPath: String) {
        launchWorkspaceSession(family: family, workspace: LaunchWorkspaceItem(path: cwdPath, sshTarget: nil))
    }

    private func startAgentMonitor() {
        guard agentTimerTask == nil, !isDemo, !isSleeping else { return }
        agentTimerTask = Task {
            await pollAgents()
            while !Task.isCancelled {
                let interval: Double = {
                    if isPanelOpen || pinnedPiPActivityID != nil {
                        return 1.8
                    } else if activeAgentWorkingCount > 0 {
                        return 2.2
                    } else if !agentActivities.isEmpty {
                        return 4.5
                    } else {
                        return 8.0
                    }
                }()
                do { try await Task.sleep(for: .seconds(interval)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await pollAgents()
            }
        }
    }

    private func pollAgents() async {
        let result = await agentTracker.poll(isDemo: isDemo)
        var items = result.items
        if hasDemoConfirmItem {
            items.insert(makeDemoConfirmItem(), at: 0)
        }
        agentActivities = items
        if isDemo, !hasSeededDemoQueue, let demoCodex = result.items.first(where: { $0.id == "demo-codex" }) {
            hasSeededDemoQueue = true
            let en = language == .english
            promptQueues[queueKey(for: demoCodex)] = [
                en ? "Run cargo test --release and commit benchmark results" : "运行 cargo test --release 并提交基准测试结果"
            ]
        }
        if recentLaunchWorkspaces.isEmpty {
            recentLaunchWorkspaces = agentTracker.discoverLaunchWorkspaceItems(liveItems: result.items)
        }
        if historicalSessions.isEmpty {
            refreshHistoricalSessions()
        } else {
            var onlineBySid: [String: String] = [:]
            for live in result.items {
                if let sid = live.sessionID, !sid.isEmpty {
                    onlineBySid[sid] = live.id
                }
            }
            for idx in historicalSessions.indices {
                historicalSessions[idx].onlineActivityID = onlineBySid[historicalSessions[idx].sessionID]
            }
        }
        if result.hadNewUnreadCompletion && !isPanelOpen {
            hasUnseenMenuBarCompletion = true
        }
        if result.hadNewCompletion && completionSoundEnabled {
            playCompletionSound()
        }
        if !agentActivities.contains(where: { $0.isUnreadCompletion }) {
            hasUnseenMenuBarCompletion = false
        }
        if !dismissedMiniConfirmTokens.isEmpty {
            let activeTokens = Set(
                items
                    .filter { $0.status == .needsInput }
                    .map { miniConfirmToken(for: $0) }
            )
            dismissedMiniConfirmTokens.formIntersection(activeTokens)
        }
        if let pinnedID = pinnedPiPActivityID,
           !items.contains(where: { $0.id == pinnedID }) {
            pinnedPiPActivityID = nil
            isPiPCollapsedPill = false
        }
        if let pinnedID = pinnedPiPActivityID,
           let pinnedItem = items.first(where: { $0.id == pinnedID }),
           pinnedItem.status == .needsInput,
           isPiPCollapsedPill {
            isPiPCollapsedPill = false
        }
        updateKeepAwakeAssertion()
        onMenuBarStateChanged?()
        onMiniConfirmStateChanged?()
        onPiPStateChanged?()
        flushReadyPromptQueues()
    }

    private func flushReadyPromptQueues() {
        guard !isDemo, !promptQueues.isEmpty else { return }
        for item in agentActivities {
            guard item.status == .completed || item.status == .idle else { continue }
            let key = queueKey(for: item)
            guard !pausedQueueKeys.contains(key),
                  !dispatchingQueueKeys.contains(key),
                  var queued = promptQueues[key],
                  !queued.isEmpty else { continue }
            let nextPrompt = queued.removeFirst()
            if queued.isEmpty {
                promptQueues.removeValue(forKey: key)
            } else {
                promptQueues[key] = queued
            }
            sendQuickReply(item, text: nextPrompt)
        }
    }
}
