import AppKit
import Foundation
import Observation
import ServiceManagement

enum MenuBarVisualState: Equatable {
    case idle(onlineCount: Int)
    case working(count: Int)
    case needsInput(count: Int)
    case unreadCompleted(count: Int)
}

@MainActor @Observable
final class AgentMeterModel {
    static let shared = AgentMeterModel()

    var agentActivities: [AgentActivityItem] = []
    var historicalSessions: [AgentHistorySessionItem] = []
    var recentLaunchWorkspaces: [LaunchWorkspaceItem] = []
    var customLaunchCommands: [String: String] = [:]
    var preferredLaunchFamily: AgentFamily {
        didSet {
            UserDefaults.standard.set(preferredLaunchFamily.rawValue, forKey: "preferredLaunchFamily")
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
    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            Task { @MainActor in await pollAgents() }
        }
    }

    @ObservationIgnored private let agentTracker = AgentActivityTracker()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var agentTimerTask: Task<Void, Never>?
    @ObservationIgnored private var activeSound: NSSound?
    @ObservationIgnored var onGlobalHotkeysPreferenceChanged: (@MainActor (Bool) -> Void)?

    init() {
        let defaults = UserDefaults.standard
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .automatic
        language = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .english
        preferredLaunchFamily = AgentFamily(rawValue: defaults.string(forKey: "preferredLaunchFamily") ?? "") ?? .claude
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

    var unreadCompletionCount: Int {
        agentActivities.filter { $0.isUnreadCompletion }.count
    }

    var showMenuBarCompletionDot: Bool {
        (hasUnseenMenuBarCompletion && unreadCompletionCount > 0) || activeAgentNeedsInputCount > 0
    }

    var menuBarVisualState: MenuBarVisualState {
        let needsInput = activeAgentNeedsInputCount
        if needsInput > 0 {
            return .needsInput(count: needsInput)
        }
        if hasUnseenMenuBarCompletion && unreadCompletionCount > 0 {
            return .unreadCompleted(count: unreadCompletionCount)
        }
        return .idle(onlineCount: agentActivities.count)
    }

    func markAllAsRead() {
        for idx in agentActivities.indices {
            agentActivities[idx].isUnreadCompletion = false
        }
        hasUnseenMenuBarCompletion = false
        agentTracker.clearUnreadCompletions()
    }

    func menuTitle() -> String {
        let en = language == .english
        let needsInput = activeAgentNeedsInputCount
        let working = activeAgentWorkingCount
        if needsInput > 0 {
            return en ? "Agent · \(needsInput) Confirm" : "Agent · \(needsInput) 待确认"
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

    func start() {
        guard !started else { return }
        started = true
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
        Task { @MainActor in await pollAgents() }
    }

    func panelDidClose() {
        isPanelOpen = false
    }

    func sleep() {
        isSleeping = true
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
        let en = language == .english
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
        Task { @MainActor in
            _ = await agentTracker.respondToPermissionPrompt(item, choice: choice)
            try? await Task.sleep(for: .milliseconds(650))
            await pollAgents()
        }
    }

    func sendQuickReply(_ item: AgentActivityItem, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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
        Task { @MainActor in
            _ = await agentTracker.sendInlinePrompt(item, text: trimmed)
            try? await Task.sleep(for: .milliseconds(700))
            await pollAgents()
        }
    }

    func closeAgentSession(_ item: AgentActivityItem) {
        agentActivities.removeAll { $0.id == item.id }
        if !agentActivities.contains(where: { $0.isUnreadCompletion }) {
            hasUnseenMenuBarCompletion = false
        }
        Task { @MainActor in
            _ = await agentTracker.closeSession(item)
            await pollAgents()
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

    func resumeOrFocusHistoricalSession(_ item: AgentHistorySessionItem) {
        if let onlineID = item.onlineActivityID,
           let liveItem = agentActivities.first(where: { $0.id == onlineID }) {
            jumpToAgentSession(liveItem)
            return
        }
        recordRecentWorkspace(LaunchWorkspaceItem(path: item.cwdPath, sshTarget: nil))
        let baseCmd = launchCommand(for: item.family)
        Task { @MainActor in
            _ = await agentTracker.resumeHistoricalSession(item, baseCommand: baseCmd)
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
        Task { @MainActor in
            _ = await agentTracker.launchWorkspaceSession(family: family, workspace: workspace, customCommand: command)
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
                    if isPanelOpen {
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
        agentActivities = result.items
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
    }
}
