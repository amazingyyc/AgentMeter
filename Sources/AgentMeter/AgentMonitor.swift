import AppKit
import ApplicationServices
import Darwin
import Foundation
import SQLite3
import SwiftUI

enum AgentFamily: String, CaseIterable, Identifiable, Sendable {
    case codex = "Codex CLI"
    case claude = "Claude Code"
    case copilot = "Copilot CLI"
    case antigravity = "Antigravity CLI"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .copilot: "Copilot"
        case .antigravity: "Antigravity"
        }
    }

    var badgeTitle: String {
        switch self {
        case .codex: "Codex CLI"
        case .claude: "Claude Code"
        case .copilot: "Copilot CLI"
        case .antigravity: "Antigravity"
        }
    }

    var iconName: String {
        switch self {
        case .codex: "terminal.fill"
        case .claude: "sparkle"
        case .copilot: "sparkles"
        case .antigravity: "atom"
        }
    }

    var defaultLaunchCommand: String {
        switch self {
        case .codex: "codex --sandbox danger-full-access -a on-request"
        case .claude: "claude"
        case .copilot: "copilot"
        case .antigravity: "agy"
        }
    }

    func accentColor(dark: Bool) -> Color {
        switch self {
        case .codex:
            return dark
                ? Color(red: 52.0 / 255, green: 211.0 / 255, blue: 153.0 / 255)
                : Color(red: 16.0 / 255, green: 163.0 / 255, blue: 127.0 / 255)
        case .claude:
            return dark
                ? Color(red: 232.0 / 255, green: 130.0 / 255, blue: 90.0 / 255)
                : Color(red: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255)
        case .copilot:
            return dark
                ? Color(red: 96.0 / 255, green: 165.0 / 255, blue: 250.0 / 255)
                : Color(red: 59.0 / 255, green: 130.0 / 255, blue: 246.0 / 255)
        case .antigravity:
            return dark
                ? Color(red: 167.0 / 255, green: 139.0 / 255, blue: 250.0 / 255)
                : Color(red: 139.0 / 255, green: 92.0 / 255, blue: 246.0 / 255)
        }
    }

    func tintFill(dark: Bool, highlighted: Bool = false) -> Color {
        accentColor(dark: dark).opacity(
            dark
                ? (highlighted ? 0.18 : 0.11)
                : (highlighted ? 0.12 : 0.07)
        )
    }
}

enum AgentTaskStatus: String, Sendable, Equatable {
    case working
    case needsInput
    case idle
    case completed
}

enum AgentApprovalChoice: Sendable {
    case approvePrimary
    case approveSecondary
    case deny
}

enum TerminalHostKind: String, CaseIterable, Identifiable, Sendable {
    case rex = "Rex"
    case ghostty = "Ghostty"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

enum PreferredTerminalHost: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case rex = "rex"
    case ghostty = "ghostty"

    var id: String { rawValue }
    func title(language: AppLanguage) -> String {
        switch self {
        case .auto: return language == .english ? "Auto" : "自动"
        case .rex: return "Rex"
        case .ghostty: return "Ghostty"
        }
    }
}

struct RexPaneLocation: Sendable, Equatable {
    let sessionID: String
    let windowID: String?
    let blockID: String
}

struct GhosttyPaneLocation: Sendable, Equatable {
    let windowID: String
    let tabID: String?
    let terminalID: String
    let ttyPath: String?
}

struct GitDiffSummary: Equatable, Sendable {
    let changedFiles: Int
    let insertions: Int
    let deletions: Int

    var isEmpty: Bool {
        changedFiles == 0 && insertions == 0 && deletions == 0
    }
}

struct LaunchWorkspaceItem: Identifiable, Equatable, Sendable {
    let path: String
    var sshTarget: String? = nil

    var id: String {
        if let sshTarget, !sshTarget.isEmpty {
            return "ssh://\(sshTarget):\(path)"
        }
        return "local:\(path)"
    }

    var isSSH: Bool {
        if let sshTarget, !sshTarget.isEmpty {
            return true
        }
        return false
    }
}

struct AgentHistorySessionItem: Identifiable, Equatable, Sendable {
    let id: String
    let sessionID: String
    let family: AgentFamily
    let title: String
    let workspace: String
    let cwdPath: String
    var gitBranch: String? = nil
    let updatedAt: Date
    var onlineActivityID: String? = nil
}

struct AgentActivityItem: Identifiable, Equatable, Sendable {
    let id: String
    var sessionID: String? = nil
    let family: AgentFamily
    let workspace: String
    var cwdPath: String = ""
    var sshTarget: String? = nil
    var title: String
    var status: AgentTaskStatus
    var isUnreadCompletion: Bool = false
    var isFocusedInHost: Bool = false
    var detail: String?
    var updatedAt: Date
    var pid: Int32?
    var tty: String?
    var rexPane: RexPaneLocation?
    var ghosttyPane: GhosttyPaneLocation? = nil
    var terminalPreviewLines: [String] = []
    var contextPercentUsed: Int? = nil
    var gitDiff: GitDiffSummary? = nil
    var gitBranch: String? = nil
    var isGitWorktree: Bool = false
    var hasWorkspaceCollision: Bool = false
    var collisionPeerCount: Int = 0

    var terminalHost: TerminalHostKind {
        if ghosttyPane != nil { return .ghostty }
        return .rex
    }

    static let promptCacheWarmTTLSeconds: Int = 300
    static let longRunningWorkingThresholdSeconds: Int = 1800

    func isLongRunningWorking(now: Date = Date()) -> Bool {
        guard status == .working else { return false }
        guard updatedAt > Date(timeIntervalSince1970: 1000) else { return false }
        return Int(now.timeIntervalSince(updatedAt)) >= Self.longRunningWorkingThresholdSeconds
    }

    func cacheWarmRemainingSeconds(now: Date = Date()) -> Int? {
        guard status != .working else { return nil }
        guard updatedAt > Date(timeIntervalSince1970: 1000) else { return nil }
        let elapsed = max(0, Int(now.timeIntervalSince(updatedAt)))
        let remaining = Self.promptCacheWarmTTLSeconds - elapsed
        guard remaining > 0 else { return nil }
        return remaining
    }

    func subtitleText(now: Date = Date()) -> String {
        let en = AppLanguage.current == .english
        var parts: [String] = [family.badgeTitle]
        if terminalHost == .ghostty {
            parts.append("Ghostty")
        }
        if let sshTarget, !sshTarget.isEmpty {
            parts.append(sshTarget)
        } else if !workspace.isEmpty,
                  workspace != "默认目录",
                  workspace != "Default",
                  workspace.lowercased() != family.shortName.lowercased() {
            parts.append(workspace)
        }
        let elapsed = max(0, Int(now.timeIntervalSince(updatedAt)))
        if updatedAt > Date(timeIntervalSince1970: 1000) {
            switch status {
            case .working:
                parts.append(Self.formatDuration(elapsed))
            case .needsInput:
                parts.append(en ? "Confirm \(Self.formatDuration(elapsed))" : "等待确认 \(Self.formatDuration(elapsed))")
            case .completed:
                parts.append(Self.formatRelativeAgo(elapsed, en: en))
            case .idle:
                break
            }
        }
        return parts.joined(separator: " · ")
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let mins = seconds / 60
        let secs = seconds % 60
        if mins < 60 {
            return String(format: "%d:%02d", mins, secs)
        }
        let hours = mins / 60
        let remMins = mins % 60
        return String(format: "%dh%02dm", hours, remMins)
    }

    private static func formatRelativeAgo(_ seconds: Int, en: Bool) -> String {
        if seconds < 15 {
            return en ? "just now" : "刚刚"
        }
        if seconds < 60 {
            return en ? "\(seconds)s ago" : "\(seconds)s前"
        }
        let mins = seconds / 60
        if mins < 60 {
            return en ? "\(mins)m ago" : "\(mins)m前"
        }
        let hours = mins / 60
        return en ? "\(hours)h ago" : "\(hours)h前"
    }
}

@MainActor
final class AgentActivityTracker {
    private var previousStates: [String: AgentTaskStatus] = [:]
    private var workingStreakCounts: [String: Int] = [:]
    private var pendingCompletionConfirmations: [String: Int] = [:]
    private var workingAnchorDates: [String: Date] = [:]
    private var stableFallbackDates: [String: Date] = [:]
    private var recentCompletions: [String: AgentActivityItem] = [:]
    private var unreadCompletionIDs: Set<String> = []
    private var dismissedIDs: [String: Date] = [:]
    private var hasSeededInitialSnapshot = false
    private let requiredWorkingPollsBeforeCompletion = 2
    private let requiredCompletionConfirmationPolls = 2
    private nonisolated static let syntheticTimestampSentinel = Date(timeIntervalSince1970: 0)

    struct PollResult {
        let items: [AgentActivityItem]
        let hadNewUnreadCompletion: Bool
        let hadNewCompletion: Bool
    }

    func poll(isDemo: Bool = false) async -> PollResult {
        if isDemo {
            let en = AppLanguage.current == .english
            let isInitialDemoPoll = !hasSeededInitialSnapshot
            hasSeededInitialSnapshot = true
            let now = Date()
            return PollResult(
                items: [
                    AgentActivityItem(
                        id: "demo-codex",
                        family: .codex,
                        workspace: "runtime-rs",
                        cwdPath: "~/dev/runtime-rs",
                        sshTarget: "gpu-node-01",
                        title: en ? "Optimize lock-free work-stealing scheduler" : "优化无锁 work-stealing 调度器",
                        status: .working,
                        isUnreadCompletion: false,
                        detail: en ? "Running task" : "正在执行任务",
                        updatedAt: now.addingTimeInterval(-215),
                        pid: 70086,
                        tty: "ttys004",
                        rexPane: nil,
                        terminalPreviewLines: [
                            "› cargo bench --release ... 412 ns/iter",
                            "  Updated src/scheduler/work_stealing.rs (+64 -22)",
                        ],
                        contextPercentUsed: 38,
                        gitDiff: GitDiffSummary(changedFiles: 4, insertions: 64, deletions: 22),
                        gitBranch: "feat/worktree-sched",
                        isGitWorktree: true
                    ),
                    AgentActivityItem(
                        id: "demo-claude",
                        family: .claude,
                        workspace: "api-server",
                        cwdPath: "~/dev/api-server",
                        title: en ? "Refactor async router & middleware pipeline" : "重构异步路由与中间件管线",
                        status: .needsInput,
                        isUnreadCompletion: true,
                        detail: en ? "Awaiting confirmation" : "等待确认",
                        updatedAt: now.addingTimeInterval(-8),
                        pid: 22915,
                        tty: "ttys003",
                        rexPane: nil,
                        terminalPreviewLines: [
                            "⏺ Bash(npm test -- --grep router)",
                            "Do you want to run this command in ~/dev/api-server?",
                            "❯ 1. Yes, allow",
                            "  2. Yes, and don't ask again for this session",
                            "  3. No, cancel (Esc)",
                        ],
                        contextPercentUsed: 64,
                        gitDiff: GitDiffSummary(changedFiles: 3, insertions: 142, deletions: 28),
                        gitBranch: "refactor/router",
                        isGitWorktree: false,
                        hasWorkspaceCollision: true,
                        collisionPeerCount: 1
                    ),
                    AgentActivityItem(
                        id: "demo-copilot",
                        family: .copilot,
                        workspace: "auth-gateway",
                        cwdPath: "~/dev/auth-gateway",
                        title: "Fix OAuth token refresh race condition",
                        status: .completed,
                        isUnreadCompletion: true,
                        detail: en ? "Completed" : "已完成",
                        updatedAt: now.addingTimeInterval(-18),
                        pid: nil,
                        tty: nil,
                        rexPane: nil,
                        terminalPreviewLines: [
                            en ? "✓ Fixed token refresh lock and passed all unit tests" : "✓ 已修复 Token 刷新锁并通过全部单元测试",
                            "  Updated src/middleware/oauth.ts (+18 -4)",
                            "  Worked for 42s · All checks passed",
                        ],
                        contextPercentUsed: 22,
                        gitDiff: GitDiffSummary(changedFiles: 1, insertions: 18, deletions: 4),
                        gitBranch: "fix/oauth-race",
                        isGitWorktree: false
                    ),
                    AgentActivityItem(
                        id: "demo-agy",
                        family: .antigravity,
                        workspace: "web-client",
                        cwdPath: "~/dev/web-client",
                        title: en ? "GraphQL schema & codegen pipeline" : "GraphQL Schema 与代码生成管线",
                        status: .idle,
                        isUnreadCompletion: false,
                        detail: en ? "Terminal idle" : "终端待命",
                        updatedAt: now.addingTimeInterval(-120),
                        pid: 39562,
                        tty: "ttys016",
                        rexPane: nil,
                        ghosttyPane: GhosttyPaneLocation(
                            windowID: "demo-win",
                            tabID: "demo-tab",
                            terminalID: "demo-term",
                            ttyPath: "/dev/ttys016"
                        ),
                        terminalPreviewLines: [
                            en ? "• Generated typed hooks in src/graphql/generated.ts" : "• 已在 src/graphql/generated.ts 生成类型化 Hooks",
                        ],
                        contextPercentUsed: 15,
                        gitBranch: "main",
                        isGitWorktree: false
                    ),
                ],
                hadNewUnreadCompletion: isInitialDemoPoll,
                hadNewCompletion: isInitialDemoPoll
            )
        }

        let discovered = await Task.detached(priority: .utility) {
            Self.collectLiveActivities()
        }.value

        let en = AppLanguage.current == .english
        let now = Date()
        dismissedIDs = dismissedIDs.filter { now.timeIntervalSince($0.value) < 6.0 }
        let filteredDiscovered = discovered.filter { dismissedIDs[$0.id] == nil }
        var currentStates: [String: AgentTaskStatus] = [:]
        var hadNewUnreadCompletion = false
        var hadNewCompletion = false

        for item in filteredDiscovered {
            if stableFallbackDates[item.id] == nil {
                stableFallbackDates[item.id] = item.updatedAt > Self.syntheticTimestampSentinel ? item.updatedAt : now
            }

            if item.status == .needsInput {
                currentStates[item.id] = .needsInput
                workingStreakCounts[item.id, default: 0] += 1
                pendingCompletionConfirmations.removeValue(forKey: item.id)
                if workingAnchorDates[item.id] == nil {
                    workingAnchorDates[item.id] = previousStates[item.id] == nil
                        ? (item.updatedAt > Self.syntheticTimestampSentinel ? item.updatedAt : now)
                        : now
                }
                recentCompletions.removeValue(forKey: item.id)
                if !item.isFocusedInHost && previousStates[item.id] != .needsInput && hasSeededInitialSnapshot {
                    unreadCompletionIDs.insert(item.id)
                    hadNewUnreadCompletion = true
                }
            } else if item.status == .working {
                currentStates[item.id] = .working
                workingStreakCounts[item.id, default: 0] += 1
                pendingCompletionConfirmations.removeValue(forKey: item.id)
                if workingAnchorDates[item.id] == nil {
                    workingAnchorDates[item.id] = previousStates[item.id] == nil
                        ? (item.updatedAt > Self.syntheticTimestampSentinel ? item.updatedAt : now)
                        : now
                }
                recentCompletions.removeValue(forKey: item.id)
                unreadCompletionIDs.remove(item.id)
            } else if hasSeededInitialSnapshot, (previousStates[item.id] == .working || previousStates[item.id] == .needsInput) {
                let workingStreak = workingStreakCounts[item.id, default: 0]
                if workingStreak >= requiredWorkingPollsBeforeCompletion {
                    let confirmations = pendingCompletionConfirmations[item.id, default: 0] + 1
                    if confirmations < requiredCompletionConfirmationPolls {
                        pendingCompletionConfirmations[item.id] = confirmations
                        currentStates[item.id] = .working
                    } else {
                        pendingCompletionConfirmations.removeValue(forKey: item.id)
                        workingStreakCounts[item.id] = 0
                        workingAnchorDates.removeValue(forKey: item.id)
                        stableFallbackDates[item.id] = now
                        currentStates[item.id] = .completed
                        var completedItem = item
                        completedItem.status = .completed
                        completedItem.detail = en ? "Completed" : "已完成"
                        completedItem.updatedAt = now
                        recentCompletions[item.id] = completedItem
                        hadNewCompletion = true
                        if !item.isFocusedInHost {
                            unreadCompletionIDs.insert(item.id)
                            hadNewUnreadCompletion = true
                        }
                    }
                } else {
                    // Initial/transient working spike: settle back without firing completion alert
                    pendingCompletionConfirmations.removeValue(forKey: item.id)
                    workingStreakCounts[item.id] = 0
                    workingAnchorDates.removeValue(forKey: item.id)
                    currentStates[item.id] = item.status
                }
            } else {
                pendingCompletionConfirmations.removeValue(forKey: item.id)
                workingStreakCounts[item.id] = 0
                workingAnchorDates.removeValue(forKey: item.id)
                currentStates[item.id] = item.status
            }

            if item.isFocusedInHost {
                unreadCompletionIDs.remove(item.id)
            }
        }

        recentCompletions = recentCompletions.filter { now.timeIntervalSince($0.value.updatedAt) < 3600 }
        let liveIDs = Set(filteredDiscovered.map(\.id))
        unreadCompletionIDs = unreadCompletionIDs.intersection(liveIDs)
        workingStreakCounts = workingStreakCounts.filter { liveIDs.contains($0.key) }
        pendingCompletionConfirmations = pendingCompletionConfirmations.filter { liveIDs.contains($0.key) }
        workingAnchorDates = workingAnchorDates.filter { liveIDs.contains($0.key) }
        stableFallbackDates = stableFallbackDates.filter { liveIDs.contains($0.key) }

        var merged: [AgentActivityItem] = []
        for var item in filteredDiscovered {
            if item.updatedAt <= Self.syntheticTimestampSentinel {
                item.updatedAt = stableFallbackDates[item.id] ?? now
            } else {
                stableFallbackDates[item.id] = item.updatedAt
            }

            let effectiveStatus = currentStates[item.id] ?? item.status
            if effectiveStatus == .needsInput {
                item.status = .needsInput
                item.detail = en ? "Awaiting confirmation" : "等待确认"
            } else if effectiveStatus == .working && item.status != .working {
                item.status = .working
                item.detail = en ? "Running task" : "正在执行任务"
            } else if effectiveStatus != .working && effectiveStatus != .needsInput, let completed = recentCompletions[item.id] {
                item.status = .completed
                item.detail = completed.detail
                item.updatedAt = completed.updatedAt
            }

            if (item.status == .working || item.status == .needsInput), let anchorDate = workingAnchorDates[item.id] {
                item.updatedAt = anchorDate
            }

            item.isUnreadCompletion = (item.status != .working) && unreadCompletionIDs.contains(item.id)
            merged.append(item)
        }

        previousStates = currentStates
        hasSeededInitialSnapshot = true

        Self.annotateWorkspaceCollisions(&merged, homePath: FileManager.default.homeDirectoryForCurrentUser.path)

        merged.sort { lhs, rhs in
            let rankL = Self.sortPriorityRank(for: lhs)
            let rankR = Self.sortPriorityRank(for: rhs)
            if rankL != rankR { return rankL < rankR }
            let timeDelta = lhs.updatedAt.timeIntervalSince(rhs.updatedAt)
            if abs(timeDelta) >= 1.0 {
                return timeDelta > 0
            }
            if lhs.isFocusedInHost != rhs.isFocusedInHost {
                return lhs.isFocusedInHost && !rhs.isFocusedInHost
            }
            return lhs.id < rhs.id
        }

        return PollResult(
            items: merged,
            hadNewUnreadCompletion: hadNewUnreadCompletion,
            hadNewCompletion: hadNewCompletion
        )
    }

    func jumpToSession(_ item: AgentActivityItem) async -> Bool {
        unreadCompletionIDs.remove(item.id)
        return await Task.detached(priority: .userInitiated) {
            Self.performJump(for: item)
        }.value
    }

    func clearUnreadCompletions() {
        unreadCompletionIDs.removeAll()
    }

    func respondToPermissionPrompt(_ item: AgentActivityItem, choice: AgentApprovalChoice) async -> Bool {
        unreadCompletionIDs.remove(item.id)
        let ok = await Task.detached(priority: .userInitiated) {
            Self.performApprovalWrite(for: item, choice: choice)
        }.value
        if ok {
            if choice == .approvePrimary || choice == .approveSecondary {
                previousStates[item.id] = .working
                workingAnchorDates[item.id] = Date()
            } else {
                previousStates[item.id] = .idle
            }
        }
        return ok
    }

    func sendInlinePrompt(_ item: AgentActivityItem, text: String) async -> Bool {
        unreadCompletionIDs.remove(item.id)
        let ok = await Task.detached(priority: .userInitiated) {
            Self.performPromptWrite(for: item, text: text)
        }.value
        if ok {
            recentCompletions.removeValue(forKey: item.id)
            previousStates[item.id] = .working
            workingAnchorDates[item.id] = Date()
        }
        return ok
    }

    func interruptSession(_ item: AgentActivityItem) async -> Bool {
        unreadCompletionIDs.remove(item.id)
        let ok = await Task.detached(priority: .userInitiated) {
            Self.performInterrupt(for: item)
        }.value
        if ok {
            workingStreakCounts.removeValue(forKey: item.id)
            pendingCompletionConfirmations.removeValue(forKey: item.id)
            workingAnchorDates.removeValue(forKey: item.id)
            recentCompletions.removeValue(forKey: item.id)
            previousStates[item.id] = .idle
            stableFallbackDates[item.id] = Date()
        }
        return ok
    }

    func launchNewSession(
        family: AgentFamily,
        cwdPath: String,
        customCommand: String,
        preferredHost: TerminalHostKind = .rex
    ) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            Self.performLaunch(
                family: family,
                cwdPath: cwdPath,
                customCommand: customCommand,
                preferredHost: preferredHost
            )
        }.value
    }

    func launchWorkspaceSession(
        family: AgentFamily,
        workspace: LaunchWorkspaceItem,
        customCommand: String,
        preferredHost: TerminalHostKind = .rex
    ) async -> Bool {
        if let sshTarget = workspace.sshTarget, !sshTarget.isEmpty {
            return await Task.detached(priority: .userInitiated) {
                Self.performSSHLaunch(
                    family: family,
                    sshTarget: sshTarget,
                    remotePath: workspace.path,
                    customCommand: customCommand,
                    preferredHost: preferredHost
                )
            }.value
        } else {
            return await Task.detached(priority: .userInitiated) {
                Self.performLaunch(
                    family: family,
                    cwdPath: workspace.path,
                    customCommand: customCommand,
                    preferredHost: preferredHost
                )
            }.value
        }
    }

    func resumeHistoricalSession(
        _ item: AgentHistorySessionItem,
        baseCommand: String,
        preferredHost: TerminalHostKind = .rex
    ) async -> Bool {
        let resumeCommand = Self.buildResumeCommand(for: item, baseCommand: baseCommand)
        return await Task.detached(priority: .userInitiated) {
            Self.performLaunch(
                family: item.family,
                cwdPath: item.cwdPath,
                customCommand: resumeCommand,
                preferredTabTitle: item.title,
                preferredHost: preferredHost
            )
        }.value
    }

    nonisolated static let deletedHistoryDefaultsKey = "deletedHistoricalSessionKeys"

    nonisolated static func loadDeletedHistoryKeys() -> Set<String> {
        let saved = UserDefaults.standard.stringArray(forKey: deletedHistoryDefaultsKey) ?? []
        return Set(saved)
    }

    nonisolated static func recordDeletedHistorySession(_ item: AgentHistorySessionItem) {
        var current = UserDefaults.standard.stringArray(forKey: deletedHistoryDefaultsKey) ?? []
        let keysToInsert = [
            item.id,
            "\(item.family.rawValue):\(item.sessionID)",
            item.sessionID,
        ]
        for key in keysToInsert where !key.isEmpty {
            current.removeAll { $0 == key }
            current.insert(key, at: 0)
        }
        if current.count > 400 {
            current = Array(current.prefix(400))
        }
        UserDefaults.standard.set(current, forKey: deletedHistoryDefaultsKey)
    }

    func deleteHistoricalSession(_ item: AgentHistorySessionItem) async -> Bool {
        Self.recordDeletedHistorySession(item)
        return await Task.detached(priority: .userInitiated) {
            Self.performDeleteHistoricalSession(item)
        }.value
    }

    func discoverHistoricalSessions(liveItems: [AgentActivityItem], isDemo: Bool = false) async -> [AgentHistorySessionItem] {
        let deletedKeys = Self.loadDeletedHistoryKeys()
        if isDemo {
            let now = Date()
            let en = AppLanguage.current == .english
            let demoItems = [
                AgentHistorySessionItem(
                    id: "claude:demo-hist-1",
                    sessionID: "demo-uuid-claude-0001",
                    family: .claude,
                    title: en ? "Async connection pool & retry backoff" : "异步连接池与重试退避策略优化",
                    workspace: "api-server",
                    cwdPath: "~/dev/api-server",
                    gitBranch: "main",
                    updatedAt: now.addingTimeInterval(-3600 * 2)
                ),
                AgentHistorySessionItem(
                    id: "codex:demo-hist-2",
                    sessionID: "demo-uuid-codex-0002",
                    family: .codex,
                    title: en ? "Optimize lock-free work stealing scheduler latency" : "优化无锁 work-stealing 调度器延迟",
                    workspace: "runtime-rs",
                    cwdPath: "~/dev/runtime-rs",
                    gitBranch: "feat/lockfree",
                    updatedAt: now.addingTimeInterval(-3600 * 18)
                ),
                AgentHistorySessionItem(
                    id: "copilot:demo-hist-3",
                    sessionID: "demo-uuid-copilot-0003",
                    family: .copilot,
                    title: en ? "Fix OAuth token refresh middleware race condition" : "修复 OAuth Token 刷新中间件竞态问题",
                    workspace: "auth-gateway",
                    cwdPath: "~/dev/auth-gateway",
                    gitBranch: nil,
                    updatedAt: now.addingTimeInterval(-86400 * 2)
                ),
            ]
            return demoItems.filter { item in
                !deletedKeys.contains(item.id)
                    && !deletedKeys.contains("\(item.family.rawValue):\(item.sessionID)")
                    && !deletedKeys.contains(item.sessionID)
            }
        }

        return await Task.detached(priority: .utility) {
            Self.collectHistoricalSessions(liveItems: liveItems)
        }.value
    }

    func discoverLaunchWorkspaceItems(liveItems: [AgentActivityItem]) -> [LaunchWorkspaceItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sshConfig = Self.parseSSHConfig(home: home)
        var seenIDs = Set<String>()
        var seenSSHHosts = Set<String>()
        var result: [LaunchWorkspaceItem] = []

        func appendLocalIfValid(_ rawPath: String) {
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "/" else { return }
            let standardized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir), isDir.boolValue else {
                return
            }
            let item = LaunchWorkspaceItem(path: standardized, sshTarget: nil)
            guard !seenIDs.contains(item.id) else { return }
            seenIDs.insert(item.id)
            result.append(item)
        }

        func appendSSHIfValid(host rawHost: String, remotePath rawPath: String) {
            let trimmedHost = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedHost.isEmpty else { return }
            let canonicalHost = Self.resolveSSHHostAlias(trimmedHost, ipToAlias: sshConfig.ipToAlias)
            let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPath = trimmedPath.isEmpty ? "~" : trimmedPath
            let item = LaunchWorkspaceItem(path: normalizedPath, sshTarget: canonicalHost)
            guard !seenIDs.contains(item.id) else { return }
            seenIDs.insert(item.id)
            seenSSHHosts.insert(canonicalHost)
            result.append(item)
        }

        // 1. User-saved recent launch workspace records (supports both local and SSH)
        if let savedRecords = UserDefaults.standard.array(forKey: "recentLaunchWorkspaceRecords") as? [[String: String]] {
            for rec in savedRecords {
                let path = rec["path"] ?? ""
                if let ssh = rec["ssh"], !ssh.isEmpty {
                    appendSSHIfValid(host: ssh, remotePath: path)
                } else {
                    appendLocalIfValid(path)
                }
            }
        } else if let legacyLocal = UserDefaults.standard.stringArray(forKey: "recentLaunchWorkspaces") {
            for path in legacyLocal {
                appendLocalIfValid(path)
            }
        }

        // 2. Currently active live sessions (both local and remote SSH)
        for item in liveItems {
            if let ssh = item.sshTarget, !ssh.isEmpty {
                appendSSHIfValid(host: ssh, remotePath: item.cwdPath)
            } else {
                appendLocalIfValid(item.cwdPath)
            }
        }

        // 3. Configured SSH hosts from ~/.ssh/config
        for host in sshConfig.hosts {
            if !seenSSHHosts.contains(host) {
                appendSSHIfValid(host: host, remotePath: "~")
            }
        }

        // 4. Recent Codex thread cwds from SQLite
        let codexTitles = Self.loadCodexTitles(home: home)
        for cwd in codexTitles.byCwd.keys.sorted() {
            appendLocalIfValid(cwd)
        }

        // 5. Common fallback directories (~/code subdirectories & home)
        let codeDir = home.appendingPathComponent("code")
        if let subdirs = try? FileManager.default.contentsOfDirectory(
            at: codeDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let sorted = subdirs.compactMap { url -> (String, Date)? in
                guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                      vals.isDirectory == true else { return nil }
                return (url.path, vals.contentModificationDate ?? .distantPast)
            }.sorted { $0.1 > $1.1 }
            for (path, _) in sorted.prefix(6) {
                appendLocalIfValid(path)
            }
        }
        appendLocalIfValid(codeDir.path)
        appendLocalIfValid(home.path)

        return Array(result.prefix(16))
    }

    private nonisolated static func parseSSHConfig(home: URL) -> (hosts: [String], ipToAlias: [String: String]) {
        let configURL = home.appendingPathComponent(".ssh/config")
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            return ([], [:])
        }
        var hosts: [String] = []
        var ipToAlias: [String: String] = [:]
        var currentAliases: [String] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let key = parts[0].lowercased()
            if key == "host" {
                currentAliases = []
                for token in parts.dropFirst() {
                    guard !token.contains("*"), !token.contains("?"), !token.hasPrefix("!") else { continue }
                    currentAliases.append(token)
                    if !hosts.contains(token) {
                        hosts.append(token)
                    }
                }
            } else if key == "hostname", let firstAlias = currentAliases.first {
                let hostNameVal = parts[1]
                if !hostNameVal.isEmpty {
                    ipToAlias[hostNameVal] = firstAlias
                }
            }
        }
        return (hosts, ipToAlias)
    }

    private nonisolated static func resolveSSHHostAlias(_ target: String, ipToAlias: [String: String]) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if let alias = ipToAlias[trimmed] {
            return alias
        }
        if let atIdx = trimmed.firstIndex(of: "@") {
            let hostPart = String(trimmed[trimmed.index(after: atIdx)...])
            if let alias = ipToAlias[hostPart] {
                return alias
            }
        }
        return trimmed
    }

    func closeSession(_ item: AgentActivityItem) async -> Bool {
        let ok = await Task.detached(priority: .userInitiated) {
            Self.performCloseSession(for: item)
        }.value
        if ok {
            dismissedIDs[item.id] = Date()
            previousStates.removeValue(forKey: item.id)
            workingStreakCounts.removeValue(forKey: item.id)
            pendingCompletionConfirmations.removeValue(forKey: item.id)
            workingAnchorDates.removeValue(forKey: item.id)
            stableFallbackDates.removeValue(forKey: item.id)
            recentCompletions.removeValue(forKey: item.id)
            unreadCompletionIDs.remove(item.id)
        }
        return ok
    }

    private static func sortPriorityRank(for item: AgentActivityItem) -> Int {
        switch item.status {
        case .needsInput:
            return 0
        case .working:
            return 1
        case .completed:
            return item.isUnreadCompletion ? 2 : 3
        case .idle:
            return 4
        }
    }

    // MARK: - Subprocess Execution with Timeout & Local TTY Fallback

    private struct ProcessExecutionResult {
        let terminationStatus: Int32
        let outputData: Data
        let timedOut: Bool
        var succeeded: Bool { !timedOut && terminationStatus == 0 }
    }

    private final class ProcessTimeoutBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _timedOut = false
        var timedOut: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _timedOut
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _timedOut = newValue
            }
        }
    }

    private nonisolated static func runProcessWithTimeout(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        captureStdout: Bool = false,
        timeoutSeconds: TimeInterval
    ) -> ProcessExecutionResult {
        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        if let environment {
            proc.environment = environment
        }
        proc.standardInput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        let outPipe: Pipe? = captureStdout ? Pipe() : nil
        if let outPipe {
            proc.standardOutput = outPipe
        } else {
            proc.standardOutput = FileHandle.nullDevice
        }

        let timeoutBox = ProcessTimeoutBox()
        let timeoutItem = DispatchWorkItem { [weak proc] in
            guard let proc, proc.isRunning else { return }
            timeoutBox.timedOut = true
            proc.terminate()
            let pid = proc.processIdentifier
            if pid > 1 {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
                    _ = Darwin.kill(pid, SIGKILL)
                }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutItem)

        do {
            try proc.run()
        } catch {
            timeoutItem.cancel()
            return ProcessExecutionResult(terminationStatus: -1, outputData: Data(), timedOut: false)
        }

        let data = outPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        proc.waitUntilExit()
        timeoutItem.cancel()

        return ProcessExecutionResult(
            terminationStatus: proc.terminationStatus,
            outputData: data,
            timedOut: timeoutBox.timedOut
        )
    }

    private nonisolated static func rexCleanEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "REX_SESSION")
        env.removeValue(forKey: "REX_BLOCK")
        env.removeValue(forKey: "REX_SERVER")
        return env
    }

    private nonisolated static func writeToLocalTTY(ttyName: String, data: Data) -> Bool {
        let cleanTTY = ttyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTTY.isEmpty,
              !cleanTTY.contains("/"),
              !cleanTTY.contains(".."),
              !data.isEmpty else {
            return false
        }
        let devPath = "/dev/\(cleanTTY)"
        let fd = Darwin.open(devPath, O_WRONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { _ = Darwin.close(fd) }
        return data.withUnsafeBytes { rawBuf -> Bool in
            guard let base = rawBuf.baseAddress else { return false }
            let written = Darwin.write(fd, base, rawBuf.count)
            return written == rawBuf.count
        }
    }

    // MARK: - Background Discovery (Rex Blocks + Live Processes + Session Metadata)

    private struct RemoteGitMetadata: Sendable {
        let branch: String?
        let isWorktree: Bool
        let diff: GitDiffSummary?
        let gitRoot: String?
        var isValidResponse: Bool = true
    }

    private final class DiscoveryCache: @unchecked Sendable {
        static let shared = DiscoveryCache()
        private let lock = NSLock()

        private var cpuSampleByPID: [Int32: (totalTimeNs: UInt64, wallTime: TimeInterval)] = [:]
        private var codexThreadByPID: [Int32: String] = [:]
        private var codexTitlesCache: (stamp: String, index: CodexTitleIndex)?
        private var codexRolloutCache: [String: (modDate: Date, info: CodexSessionInfo)] = [:]
        private var claudeTranscriptCache: [String: (modDate: Date, summary: ClaudeTranscriptSummary)] = [:]
        private var claudeHistoryCache: (modDate: Date, bySession: [String: String])?
        private var gitDiffCache: [String: (timestamp: TimeInterval, summary: GitDiffSummary?)] = [:]
        private var gitBranchCache: [String: (timestamp: TimeInterval, branch: String?, isWorktree: Bool)] = [:]
        private var remoteGitCache: [String: (timestamp: TimeInterval, metadata: RemoteGitMetadata)] = [:]
        private var remoteGitInFlight: Set<String> = []
        private var lastKnownRemoteCwdByBlock: [String: String] = [:]
        private var lastGoodRexBlocks: (timestamp: TimeInterval, map: [Int32: RexBlockEntry])?
        private var lastGoodGhosttyTerminals: (timestamp: TimeInterval, entries: [GhosttyTerminalEntry])?

        func cachedRexBlocksFallback(now: TimeInterval, maxAge: TimeInterval = 6.0) -> [Int32: RexBlockEntry]? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = lastGoodRexBlocks, (now - entry.timestamp) < maxAge else {
                return nil
            }
            return entry.map
        }

        func setLastGoodRexBlocks(_ map: [Int32: RexBlockEntry], now: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            lastGoodRexBlocks = (now, map)
        }

        func cachedGhosttyTerminalsFallback(now: TimeInterval, maxAge: TimeInterval = 6.0) -> [GhosttyTerminalEntry]? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = lastGoodGhosttyTerminals, (now - entry.timestamp) < maxAge else {
                return nil
            }
            return entry.entries
        }

        func setCachedGhosttyTerminals(_ entries: [GhosttyTerminalEntry], now: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            lastGoodGhosttyTerminals = (now, entries)
        }

        func cachedRemoteGit(
            for key: String,
            now: TimeInterval,
            ttl: TimeInterval = 12.0,
            negativeTTL: TimeInterval = 15.0
        ) -> (freshHit: Bool, staleMetadata: RemoteGitMetadata?) {
            lock.lock()
            defer { lock.unlock() }
            if let entry = remoteGitCache[key] {
                let effectiveTTL = entry.metadata.isValidResponse ? ttl : negativeTTL
                let isFresh = (now - entry.timestamp) < effectiveTTL
                return (isFresh, entry.metadata)
            }
            return (false, nil)
        }

        func setCachedRemoteGit(_ metadata: RemoteGitMetadata, for key: String, now: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            if remoteGitCache.count > 64 { remoteGitCache.removeAll(keepingCapacity: true) }
            if !metadata.isValidResponse, let existing = remoteGitCache[key], existing.metadata.isValidResponse {
                remoteGitCache[key] = (now, existing.metadata)
                return
            }
            remoteGitCache[key] = (now, metadata)
        }

        func markRemoteGitInFlight(_ key: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if remoteGitInFlight.contains(key) {
                return false
            }
            remoteGitInFlight.insert(key)
            return true
        }

        func clearRemoteGitInFlight(_ key: String) {
            lock.lock()
            defer { lock.unlock() }
            remoteGitInFlight.remove(key)
        }

        func rememberRemoteCwd(_ cwd: String, forBlock blockID: String) {
            lock.lock()
            defer { lock.unlock() }
            if lastKnownRemoteCwdByBlock.count > 128 {
                lastKnownRemoteCwdByBlock.removeAll(keepingCapacity: true)
            }
            lastKnownRemoteCwdByBlock[blockID] = cwd
        }

        func lastKnownRemoteCwd(forBlock blockID: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return lastKnownRemoteCwdByBlock[blockID]
        }

        func cachedGitDiff(for gitRoot: String, now: TimeInterval, ttl: TimeInterval = 3.5) -> (hit: Bool, summary: GitDiffSummary?, staleSummary: GitDiffSummary?) {
            lock.lock()
            defer { lock.unlock() }
            if let entry = gitDiffCache[gitRoot] {
                let isFresh = (now - entry.timestamp) < ttl
                return (isFresh, entry.summary, entry.summary)
            }
            return (false, nil, nil)
        }

        func setCachedGitDiff(_ summary: GitDiffSummary?, for gitRoot: String, now: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            if gitDiffCache.count > 64 { gitDiffCache.removeAll(keepingCapacity: true) }
            gitDiffCache[gitRoot] = (now, summary)
        }

        func cachedGitBranch(for gitRoot: String, now: TimeInterval, ttl: TimeInterval = 3.5) -> (hit: Bool, branch: String?, isWorktree: Bool) {
            lock.lock()
            defer { lock.unlock() }
            if let entry = gitBranchCache[gitRoot], now - entry.timestamp < ttl {
                return (true, entry.branch, entry.isWorktree)
            }
            return (false, nil, false)
        }

        func setCachedGitBranch(branch: String?, isWorktree: Bool, for gitRoot: String, now: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            if gitBranchCache.count > 64 { gitBranchCache.removeAll(keepingCapacity: true) }
            gitBranchCache[gitRoot] = (now, branch, isWorktree)
        }

        func computeCPUPercent(pid: Int32, totalTimeNs: UInt64, now: TimeInterval) -> Double {
            lock.lock()
            defer { lock.unlock() }
            defer { cpuSampleByPID[pid] = (totalTimeNs, now) }
            guard let prev = cpuSampleByPID[pid], now > prev.wallTime, totalTimeNs >= prev.totalTimeNs else {
                return 0.0
            }
            let deltaWall = now - prev.wallTime
            guard deltaWall > 0.05 else { return 0.0 }
            let deltaCPU = Double(totalTimeNs - prev.totalTimeNs) / 1_000_000_000.0
            return (deltaCPU / deltaWall) * 100.0
        }

        func pruneDeadPIDs(_ livePIDs: Set<Int32>) {
            lock.lock()
            defer { lock.unlock() }
            cpuSampleByPID = cpuSampleByPID.filter { livePIDs.contains($0.key) }
            codexThreadByPID = codexThreadByPID.filter { livePIDs.contains($0.key) }
        }

        func cachedCodexThreadID(for pid: Int32) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return codexThreadByPID[pid]
        }

        func setCachedCodexThreadID(_ tid: String, for pid: Int32) {
            lock.lock()
            defer { lock.unlock() }
            codexThreadByPID[pid] = tid
        }

        func cachedCodexTitles(stamp: String) -> CodexTitleIndex? {
            lock.lock()
            defer { lock.unlock() }
            guard let cached = codexTitlesCache, cached.stamp == stamp else { return nil }
            return cached.index
        }

        func setCachedCodexTitles(_ index: CodexTitleIndex, stamp: String) {
            lock.lock()
            defer { lock.unlock() }
            codexTitlesCache = (stamp, index)
        }

        func cachedCodexRollout(path: String, modDate: Date) -> CodexSessionInfo? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = codexRolloutCache[path], entry.modDate == modDate else { return nil }
            return entry.info
        }

        func setCachedCodexRollout(_ info: CodexSessionInfo, path: String, modDate: Date) {
            lock.lock()
            defer { lock.unlock() }
            if codexRolloutCache.count > 64 { codexRolloutCache.removeAll(keepingCapacity: true) }
            codexRolloutCache[path] = (modDate, info)
        }

        func cachedClaudeTranscript(path: String, modDate: Date) -> ClaudeTranscriptSummary? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = claudeTranscriptCache[path], entry.modDate == modDate else { return nil }
            return entry.summary
        }

        func setCachedClaudeTranscript(_ summary: ClaudeTranscriptSummary, path: String, modDate: Date) {
            lock.lock()
            defer { lock.unlock() }
            if claudeTranscriptCache.count > 64 { claudeTranscriptCache.removeAll(keepingCapacity: true) }
            claudeTranscriptCache[path] = (modDate, summary)
        }

        func cachedClaudeHistory(modDate: Date) -> [String: String]? {
            lock.lock()
            defer { lock.unlock() }
            guard let cached = claudeHistoryCache, cached.modDate == modDate else { return nil }
            return cached.bySession
        }

        func setCachedClaudeHistory(_ bySession: [String: String], modDate: Date) {
            lock.lock()
            defer { lock.unlock() }
            claudeHistoryCache = (modDate, bySession)
        }
    }

    private nonisolated static func collectLiveActivities() -> [AgentActivityItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let rexMap = queryRexBlocks(home: home)
        let regularPIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map(\.processIdentifier)
        )
        let scanned = scanAgentProcesses()
        DiscoveryCache.shared.pruneDeadPIDs(Set(scanned.candidates.map(\.pid)))

        let ghosttyAppPID = runningGhosttyApplication()?.processIdentifier
        let isGhosttyFront = isGhosttyFrontmostOrRecentlyActive()
        let ghosttyEntries = queryGhosttyTerminals(
            sshPIDsByTTY: scanned.sshPIDsByTTY,
            ppidMap: scanned.ppidMap
        )
        var ghosttyMap: [Int32: GhosttyTerminalEntry] = [:]
        var ghosttyByTermID: [String: GhosttyTerminalEntry] = [:]
        for entry in ghosttyEntries {
            ghosttyByTermID[entry.location.terminalID] = entry
        }
        for proc in scanned.candidates {
            if let matched = matchGhosttyEntry(for: proc, ppidMap: scanned.ppidMap, entries: ghosttyEntries) {
                ghosttyMap[proc.pid] = matched
            } else if rexMap[proc.pid] == nil,
                      isDescendantOfGhostty(pid: proc.pid, ghosttyAppPID: ghosttyAppPID, ppidMap: scanned.ppidMap) {
                let fallbackLocation = GhosttyPaneLocation(
                    windowID: "",
                    tabID: nil,
                    terminalID: "pid-\(proc.pid)",
                    ttyPath: proc.tty.map { "/dev/\($0)" }
                )
                let fallbackEntry = GhosttyTerminalEntry(
                    location: fallbackLocation,
                    pid: proc.pid,
                    ttyName: proc.tty,
                    cwdPath: proc.cwdPath,
                    rawTitle: nil,
                    isFocusedInActiveWindow: isGhosttyFront,
                    screenTail: nil
                )
                ghosttyMap[proc.pid] = fallbackEntry
                ghosttyByTermID[fallbackLocation.terminalID] = fallbackEntry
            }
        }

        let processes = scanned.candidates.filter { proc in
            rexMap[proc.pid] != nil || ghosttyMap[proc.pid] != nil || hasInteractiveHostApplication(
                pid: proc.pid,
                ppidMap: scanned.ppidMap,
                regularPIDs: regularPIDs
            )
        }
        var results: [AgentActivityItem] = []

        // 1. Codex CLI sessions (lazily loaded only when Codex processes are alive)
        let codexProcs = processes.filter { $0.family == .codex }
        if !codexProcs.isEmpty {
            let codexSessions = inspectCodexSessions(home: home)
            let codexTitles = loadCodexTitles(home: home)
            let pidThreadMap = mapCodexPIDsToThreadIDs(
                home: home,
                pids: codexProcs.map(\.pid),
                validThreadIDs: Set(codexTitles.bySessionID.keys)
            )
            var matchedCodexSessionIDs = Set<String>()

            for proc in codexProcs {
                let rexEntry = rexMap[proc.pid]
                let ghosttyEntry = rexEntry == nil ? ghosttyMap[proc.pid] : nil
                let matchingSession = matchCodexSession(
                    for: proc,
                    rexEntry: rexEntry,
                    ghosttyEntry: ghosttyEntry,
                    exactThreadID: pidThreadMap[proc.pid],
                    sessions: codexSessions,
                    titles: codexTitles,
                    matchedSessionIDs: &matchedCodexSessionIDs
                )

                let status: AgentTaskStatus
                if let rexEntry {
                    status = rexEntry.inferredStatus
                } else if let ghosttyEntry {
                    let inferred = ghosttyEntry.inferredStatus
                    let isSessionWorking = matchingSession?.isTaskRunning == true
                    let isProcBusy = proc.cpu > 3.5
                    if inferred == .needsInput {
                        status = .needsInput
                    } else if isSessionWorking || isProcBusy || inferred == .working {
                        status = .working
                    } else {
                        status = inferred
                    }
                } else {
                    let isSessionWorking = matchingSession?.isTaskRunning == true
                    let isProcBusy = proc.cpu > 3.5
                    status = (isSessionWorking || isProcBusy) ? .working : .idle
                }
                let en = AppLanguage.current == .english
                let detail = status == .needsInput
                    ? (en ? "Awaiting confirmation" : "等待确认")
                    : (status == .working ? (en ? "Running task" : "正在执行任务") : (en ? "Terminal idle" : "终端待命"))
                let effectiveCwd = !proc.cwdPath.isEmpty ? proc.cwdPath : (ghosttyEntry?.cwdPath ?? "")
                let effectiveWorkspace: String = {
                    let name = URL(fileURLWithPath: effectiveCwd).lastPathComponent
                    return name.isEmpty || name == "/" ? proc.workspaceName : name
                }()
                let sessionTitle = matchingSession.flatMap { codexTitles.bySessionID[$0.sessionID] ?? $0.fallbackTitle }
                let primaryTitle: String? = rexEntry?.descriptiveTitle
                    ?? ghosttyEntry?.descriptiveTitle
                    ?? sessionTitle
                    ?? rexEntry?.latestScreenPrompt
                    ?? ghosttyEntry?.latestScreenPrompt
                let fallbackTitle: String? = codexTitles.byCwd[effectiveCwd]
                    ?? rexEntry?.cleanTitle
                    ?? ghosttyEntry?.cleanTitle
                let resolvedTitle = primaryTitle ?? fallbackTitle ?? effectiveWorkspace
                let itemID: String = {
                    if let rexEntry {
                        return "rex-block-\(rexEntry.location.blockID)"
                    }
                    if let matchingSession {
                        return "codex-\(matchingSession.sessionID)-pid-\(proc.pid)"
                    }
                    if let ghosttyEntry {
                        return "ghostty-term-\(ghosttyEntry.location.terminalID)-pid-\(proc.pid)"
                    }
                    return "codex-pid-\(proc.pid)"
                }()
                results.append(
                    AgentActivityItem(
                        id: itemID,
                        sessionID: matchingSession?.sessionID,
                        family: .codex,
                        workspace: effectiveWorkspace,
                        cwdPath: effectiveCwd,
                        title: resolvedTitle,
                        status: status,
                        isFocusedInHost: rexEntry?.isFocusedInActiveWindow ?? ghosttyEntry?.isFocusedInActiveWindow ?? false,
                        detail: detail,
                        updatedAt: matchingSession?.updatedAt ?? syntheticTimestampSentinel,
                        pid: proc.pid,
                        tty: proc.tty ?? ghosttyEntry?.ttyName,
                        rexPane: rexEntry?.location,
                        ghosttyPane: ghosttyEntry?.location
                    )
                )
            }
        }

        // 2. Claude Code CLI sessions
        let claudeProcs = processes.filter { $0.family == .claude }
        let claudeSessions = inspectClaudeSessions(home: home, liveProcesses: claudeProcs, rexMap: rexMap, ghosttyMap: ghosttyMap)
        results.append(contentsOf: claudeSessions)

        // 3. Copilot CLI sessions
        let copilotProcs = processes.filter { $0.family == .copilot }
        let copilotSessions = inspectCopilotSessions(home: home, liveProcesses: copilotProcs, rexMap: rexMap, ghosttyMap: ghosttyMap)
        results.append(contentsOf: copilotSessions)

        // 4. Antigravity CLI sessions
        let agyProcs = processes.filter { $0.family == .antigravity }
        let agySessions = inspectAntigravitySessions(home: home, liveProcesses: agyProcs, rexMap: rexMap, ghosttyMap: ghosttyMap)
        results.append(contentsOf: agySessions)

        // 5. Rex panes reporting agent status via OSC 7501 (e.g., remote SSH sessions running Codex/Claude/Copilot/Antigravity)
        let sshConfig = parseSSHConfig(home: home)
        let coveredPIDs = Set(results.compactMap(\.pid))
        for (pid, rexEntry) in rexMap where !coveredPIDs.contains(pid) {
            guard let family = rexEntry.detectedFamily else { continue }
            let en = AppLanguage.current == .english
            let status = rexEntry.inferredStatus
            let effectiveCwd: String = {
                guard rexEntry.isSSH else { return rexEntry.cwdPath }
                if let remoteCwd = rexEntry.remoteCwdPath, !remoteCwd.isEmpty, remoteCwd != "~" {
                    DiscoveryCache.shared.rememberRemoteCwd(remoteCwd, forBlock: rexEntry.location.blockID)
                    return remoteCwd
                }
                if let remembered = DiscoveryCache.shared.lastKnownRemoteCwd(forBlock: rexEntry.location.blockID),
                   !remembered.isEmpty {
                    return remembered
                }
                return rexEntry.remoteCwdPath ?? "~"
            }()
            let wsName = URL(fileURLWithPath: effectiveCwd).lastPathComponent
            let baseTitle = rexEntry.cleanTitle ?? rexEntry.latestScreenPrompt ?? (en ? "\(family.shortName) Session" : "\(family.shortName) 会话")
            let displayTitle: String = {
                if rexEntry.isSSH, !baseTitle.uppercased().hasPrefix("SSH ") && !baseTitle.uppercased().hasPrefix("[SSH]") {
                    return "SSH · \(baseTitle)"
                }
                return baseTitle
            }()
            let resolvedSSHTarget = rexEntry.sshTarget.map { resolveSSHHostAlias($0, ipToAlias: sshConfig.ipToAlias) }
            results.append(
                AgentActivityItem(
                    id: "rex-block-\(rexEntry.location.blockID)",
                    family: family,
                    workspace: wsName.isEmpty || wsName == "/" || wsName == "~" ? family.shortName : wsName,
                    cwdPath: effectiveCwd,
                    sshTarget: resolvedSSHTarget,
                    title: displayTitle,
                    status: status,
                    isFocusedInHost: rexEntry.isFocusedInActiveWindow,
                    detail: status == .needsInput
                        ? (en ? "Awaiting confirmation" : "等待确认")
                        : (status == .working ? (en ? "Running task" : "正在执行任务") : (en ? "Terminal idle" : "终端待命")),
                    updatedAt: syntheticTimestampSentinel,
                    pid: pid,
                    tty: nil,
                    rexPane: rexEntry.location
                )
            )
        }

        // 6. Ghostty terminals running remote SSH sessions (or standalone TUI sessions) reporting Agent title/screen status
        let coveredGhosttyTermIDs = Set(results.compactMap { $0.ghosttyPane?.terminalID })
        let updatedCoveredPIDs = Set(results.compactMap(\.pid))
        for ghosttyEntry in ghosttyEntries where !coveredGhosttyTermIDs.contains(ghosttyEntry.location.terminalID) && !updatedCoveredPIDs.contains(ghosttyEntry.pid) {
            guard let family = ghosttyEntry.detectedFamily else { continue }
            let en = AppLanguage.current == .english
            let status = ghosttyEntry.inferredStatus
            let blockCacheKey = "ghostty:\(ghosttyEntry.location.terminalID)"
            let effectiveCwd: String = {
                guard ghosttyEntry.isSSH else { return ghosttyEntry.cwdPath }
                if let remoteCwd = ghosttyEntry.remoteCwdPath, !remoteCwd.isEmpty, remoteCwd != "~" {
                    DiscoveryCache.shared.rememberRemoteCwd(remoteCwd, forBlock: blockCacheKey)
                    return remoteCwd
                }
                if let remembered = DiscoveryCache.shared.lastKnownRemoteCwd(forBlock: blockCacheKey),
                   !remembered.isEmpty {
                    return remembered
                }
                return ghosttyEntry.remoteCwdPath ?? "~"
            }()
            let wsName = URL(fileURLWithPath: effectiveCwd).lastPathComponent
            let baseTitle = ghosttyEntry.cleanTitle ?? ghosttyEntry.latestScreenPrompt ?? (en ? "\(family.shortName) Session" : "\(family.shortName) 会话")
            let displayTitle: String = {
                if ghosttyEntry.isSSH, !baseTitle.uppercased().hasPrefix("SSH ") && !baseTitle.uppercased().hasPrefix("[SSH]") {
                    return "SSH · \(baseTitle)"
                }
                return baseTitle
            }()
            let resolvedSSHTarget = ghosttyEntry.sshTarget.map { resolveSSHHostAlias($0, ipToAlias: sshConfig.ipToAlias) }
            results.append(
                AgentActivityItem(
                    id: "ghostty-term-\(ghosttyEntry.location.terminalID)",
                    family: family,
                    workspace: wsName.isEmpty || wsName == "/" || wsName == "~" ? family.shortName : wsName,
                    cwdPath: effectiveCwd,
                    sshTarget: resolvedSSHTarget,
                    title: displayTitle,
                    status: status,
                    isFocusedInHost: ghosttyEntry.isFocusedInActiveWindow,
                    detail: status == .needsInput
                        ? (en ? "Awaiting confirmation" : "等待确认")
                        : (status == .working ? (en ? "Running task" : "正在执行任务") : (en ? "Terminal idle" : "终端待命")),
                    updatedAt: syntheticTimestampSentinel,
                    pid: ghosttyEntry.sshPID ?? ghosttyEntry.pid,
                    tty: ghosttyEntry.ttyName,
                    rexPane: nil,
                    ghosttyPane: ghosttyEntry.location
                )
            )
        }

        // Normalize SSH prefix, remote target, and live terminal preview if any matched Rex or Ghostty pane is available
        for idx in results.indices {
            let matchedGhostty: GhosttyTerminalEntry? = {
                if let termID = results[idx].ghosttyPane?.terminalID, let entry = ghosttyByTermID[termID] {
                    return entry
                }
                if let pid = results[idx].pid, let entry = ghosttyMap[pid] {
                    return entry
                }
                return nil
            }()

            if let pid = results[idx].pid,
               let rexEntry = rexMap[pid] {
                if results[idx].terminalPreviewLines.isEmpty {
                    let preview = rexEntry.previewLines
                    if !preview.isEmpty {
                        results[idx].terminalPreviewLines = preview
                    }
                }
                if results[idx].contextPercentUsed == nil {
                    results[idx].contextPercentUsed = rexEntry.contextPercentUsed
                }
                if rexEntry.isSSH {
                    results[idx].sshTarget = rexEntry.sshTarget.map { resolveSSHHostAlias($0, ipToAlias: sshConfig.ipToAlias) }
                    if let remoteCwd = rexEntry.remoteCwdPath, !remoteCwd.isEmpty, remoteCwd != "~" {
                        DiscoveryCache.shared.rememberRemoteCwd(remoteCwd, forBlock: rexEntry.location.blockID)
                        results[idx].cwdPath = remoteCwd
                    } else if let remembered = DiscoveryCache.shared.lastKnownRemoteCwd(forBlock: rexEntry.location.blockID),
                              !remembered.isEmpty {
                        results[idx].cwdPath = remembered
                    } else if let remoteCwd = rexEntry.remoteCwdPath, !remoteCwd.isEmpty {
                        results[idx].cwdPath = remoteCwd
                    }
                    if !results[idx].title.uppercased().hasPrefix("SSH ") && !results[idx].title.uppercased().hasPrefix("[SSH]") {
                        results[idx].title = "SSH · \(results[idx].title)"
                    }
                }
            } else if let ghosttyEntry = matchedGhostty {
                if results[idx].terminalPreviewLines.isEmpty {
                    let preview = ghosttyEntry.previewLines
                    if !preview.isEmpty {
                        results[idx].terminalPreviewLines = preview
                    }
                }
                if results[idx].contextPercentUsed == nil {
                    results[idx].contextPercentUsed = ghosttyEntry.contextPercentUsed
                }
                if ghosttyEntry.isSSH {
                    let blockCacheKey = "ghostty:\(ghosttyEntry.location.terminalID)"
                    results[idx].sshTarget = ghosttyEntry.sshTarget.map { resolveSSHHostAlias($0, ipToAlias: sshConfig.ipToAlias) }
                    if let remoteCwd = ghosttyEntry.remoteCwdPath, !remoteCwd.isEmpty, remoteCwd != "~" {
                        DiscoveryCache.shared.rememberRemoteCwd(remoteCwd, forBlock: blockCacheKey)
                        results[idx].cwdPath = remoteCwd
                    } else if let remembered = DiscoveryCache.shared.lastKnownRemoteCwd(forBlock: blockCacheKey),
                              !remembered.isEmpty {
                        results[idx].cwdPath = remembered
                    } else if let remoteCwd = ghosttyEntry.remoteCwdPath, !remoteCwd.isEmpty {
                        results[idx].cwdPath = remoteCwd
                    }
                    if !results[idx].title.uppercased().hasPrefix("SSH ") && !results[idx].title.uppercased().hasPrefix("[SSH]") {
                        results[idx].title = "SSH · \(results[idx].title)"
                    }
                }
            }
            if results[idx].terminalPreviewLines.isEmpty, let detail = results[idx].detail, !detail.isEmpty {
                results[idx].terminalPreviewLines = [detail]
            }
            if let sshTarget = results[idx].sshTarget?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sshTarget.isEmpty {
                let remoteCwd = results[idx].cwdPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if !remoteCwd.isEmpty, remoteCwd != "~", remoteCwd != "/",
                   let remoteMeta = inspectRemoteSSHGitMetadata(sshTarget: sshTarget, remoteCwd: remoteCwd) {
                    if let branch = remoteMeta.branch, !branch.isEmpty {
                        results[idx].gitBranch = branch
                    }
                    results[idx].isGitWorktree = remoteMeta.isWorktree
                    if results[idx].gitDiff == nil {
                        results[idx].gitDiff = remoteMeta.diff
                    }
                }
                if results[idx].gitBranch == nil {
                    let rexEntry = results[idx].pid.flatMap { rexMap[$0] }
                    results[idx].gitBranch = extractGitBranchFromTerminal(
                        tail: rexEntry?.screenTail ?? matchedGhostty?.screenTail,
                        title: rexEntry?.rawTitle ?? matchedGhostty?.rawTitle ?? results[idx].title
                    )
                }
                if results[idx].gitDiff == nil {
                    results[idx].gitDiff = extractDiffFromPreviewLines(results[idx].terminalPreviewLines)
                }
            } else {
                if results[idx].gitDiff == nil {
                    if !results[idx].cwdPath.isEmpty {
                        results[idx].gitDiff = inspectGitDiff(cwdPath: results[idx].cwdPath, homePath: home.path)
                    }
                    if results[idx].gitDiff == nil {
                        results[idx].gitDiff = extractDiffFromPreviewLines(results[idx].terminalPreviewLines)
                    }
                }
                if !results[idx].cwdPath.isEmpty {
                    let gitInfo = inspectGitBranchAndWorktree(cwdPath: results[idx].cwdPath, homePath: home.path)
                    if let branch = gitInfo.branch, !branch.isEmpty {
                        results[idx].gitBranch = branch
                    }
                    results[idx].isGitWorktree = gitInfo.isWorktree
                }
                if results[idx].gitBranch == nil {
                    let rexEntry = results[idx].pid.flatMap { rexMap[$0] }
                    results[idx].gitBranch = extractGitBranchFromTerminal(
                        tail: rexEntry?.screenTail ?? matchedGhostty?.screenTail,
                        title: rexEntry?.rawTitle ?? matchedGhostty?.rawTitle ?? results[idx].title
                    )
                }
            }
        }

        annotateWorkspaceCollisions(&results, homePath: home.path)
        return results
    }

    // MARK: - Git Working Tree Diff, Branch, Worktree & Collision Inspection

    private nonisolated static func inspectGitBranchAndWorktree(cwdPath: String, homePath: String) -> (branch: String?, isWorktree: Bool) {
        guard let gitRoot = resolveGitRepositoryRoot(for: cwdPath, homePath: homePath) else {
            return (nil, false)
        }
        let now = ProcessInfo.processInfo.systemUptime
        let cached = DiscoveryCache.shared.cachedGitBranch(for: gitRoot, now: now)
        if cached.hit {
            return (cached.branch, cached.isWorktree)
        }

        let fm = FileManager.default
        let dotGitPath = (gitRoot as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dotGitPath, isDirectory: &isDir) else {
            DiscoveryCache.shared.setCachedGitBranch(branch: nil, isWorktree: false, for: gitRoot, now: now)
            return (nil, false)
        }

        var isWorktree = false
        var headPath: String? = nil

        if isDir.boolValue {
            isWorktree = false
            headPath = (dotGitPath as NSString).appendingPathComponent("HEAD")
        } else if let text = try? String(contentsOfFile: dotGitPath, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.lowercased().hasPrefix("gitdir:") {
                    let rawTarget = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !rawTarget.isEmpty else { continue }
                    let resolvedGitDir: String
                    if rawTarget.hasPrefix("/") {
                        resolvedGitDir = URL(fileURLWithPath: rawTarget).standardizedFileURL.path
                    } else {
                        resolvedGitDir = URL(
                            fileURLWithPath: rawTarget,
                            relativeTo: URL(fileURLWithPath: gitRoot, isDirectory: true)
                        ).standardizedFileURL.path
                    }
                    if resolvedGitDir.contains("/worktrees/") || rawTarget.contains("/worktrees/") {
                        isWorktree = true
                    }
                    let candidateHead = (resolvedGitDir as NSString).appendingPathComponent("HEAD")
                    if fm.fileExists(atPath: candidateHead) {
                        headPath = candidateHead
                    } else {
                        let commonDirFile = (resolvedGitDir as NSString).appendingPathComponent("commondir")
                        if let rawCommon = try? String(contentsOfFile: commonDirFile, encoding: .utf8) {
                            let trimmedCommon = rawCommon.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedCommon.isEmpty {
                                let resolvedCommon = trimmedCommon.hasPrefix("/")
                                    ? URL(fileURLWithPath: trimmedCommon).standardizedFileURL.path
                                    : URL(
                                        fileURLWithPath: trimmedCommon,
                                        relativeTo: URL(fileURLWithPath: resolvedGitDir, isDirectory: true)
                                    ).standardizedFileURL.path
                                let commonHead = (resolvedCommon as NSString).appendingPathComponent("HEAD")
                                if fm.fileExists(atPath: commonHead) {
                                    headPath = commonHead
                                }
                            }
                        }
                    }
                    break
                }
            }
        }

        var branch: String? = nil
        if let headPath,
           let rawHead = try? String(contentsOfFile: headPath, encoding: .utf8) {
            let trimmedHead = rawHead.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedHead.hasPrefix("ref: refs/heads/") {
                let name = String(trimmedHead.dropFirst("ref: refs/heads/".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    branch = name
                }
            } else if trimmedHead.hasPrefix("ref: ") {
                let refPath = String(trimmedHead.dropFirst("ref: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                let lastComp = (refPath as NSString).lastPathComponent
                if !lastComp.isEmpty {
                    branch = lastComp
                }
            } else if trimmedHead.count >= 7 && trimmedHead.allSatisfy({ $0.isHexDigit }) {
                branch = String(trimmedHead.prefix(7))
            }
        }

        DiscoveryCache.shared.setCachedGitBranch(branch: branch, isWorktree: isWorktree, for: gitRoot, now: now)
        return (branch, isWorktree)
    }

    private nonisolated static func annotateWorkspaceCollisions(_ items: inout [AgentActivityItem], homePath: String) {
        for idx in items.indices {
            items[idx].hasWorkspaceCollision = false
            items[idx].collisionPeerCount = 0
        }

        var groupsByCheckoutKey: [String: [Int]] = [:]
        let standardizedHome = URL(fileURLWithPath: homePath).standardizedFileURL.path

        for idx in items.indices {
            let item = items[idx]
            // Only consider online process sessions
            guard item.pid != nil || item.rexPane != nil || item.ghosttyPane != nil else { continue }

            let checkoutKey: String? = {
                if let sshTarget = item.sshTarget?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !sshTarget.isEmpty {
                    let trimmedCwd = item.cwdPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedCwd.isEmpty, trimmedCwd != "~", trimmedCwd != "/" else { return nil }
                    let cacheKey = remoteGitCacheKey(sshTarget: sshTarget, remoteCwd: trimmedCwd)
                    let now = ProcessInfo.processInfo.systemUptime
                    if let cachedRoot = DiscoveryCache.shared.cachedRemoteGit(for: cacheKey, now: now).staleMetadata?.gitRoot,
                       !cachedRoot.isEmpty {
                        return "ssh://\(sshTarget.lowercased()):\(cachedRoot)"
                    }
                    return "ssh://\(sshTarget.lowercased()):\(trimmedCwd)"
                } else {
                    let trimmedCwd = item.cwdPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedCwd.isEmpty, trimmedCwd != "/", trimmedCwd != "~" else { return nil }
                    if let gitRoot = resolveGitRepositoryRoot(for: trimmedCwd, homePath: standardizedHome) {
                        return "local:\(gitRoot)"
                    }
                    let stdPath = URL(fileURLWithPath: trimmedCwd).standardizedFileURL.path
                    guard !stdPath.isEmpty, stdPath != "/", stdPath != standardizedHome else { return nil }
                    return "local:\(stdPath)"
                }
            }()

            if let key = checkoutKey {
                groupsByCheckoutKey[key, default: []].append(idx)
            }
        }

        for (_, indices) in groupsByCheckoutKey where indices.count >= 2 {
            let hasActiveWriter = indices.contains { i in
                items[i].status == .working || items[i].status == .needsInput
            }
            guard hasActiveWriter else { continue }
            let peerCount = indices.count - 1
            for i in indices {
                items[i].hasWorkspaceCollision = true
                items[i].collisionPeerCount = peerCount
            }
        }
    }

    private nonisolated static func resolveGitRepositoryRoot(for cwdPath: String, homePath: String) -> String? {
        let trimmed = cwdPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/" else { return nil }
        var current = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        let fm = FileManager.default
        var depth = 0
        while !current.isEmpty && current != "/" && current != homePath && depth < 12 {
            let dotGit = (current as NSString).appendingPathComponent(".git")
            if fm.fileExists(atPath: dotGit) {
                return current
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
            depth += 1
        }
        return nil
    }

    private nonisolated static func inspectGitDiff(cwdPath: String, homePath: String) -> GitDiffSummary? {
        guard let gitRoot = resolveGitRepositoryRoot(for: cwdPath, homePath: homePath) else {
            return nil
        }
        let now = ProcessInfo.processInfo.systemUptime
        let cached = DiscoveryCache.shared.cachedGitDiff(for: gitRoot, now: now)
        if cached.hit {
            return cached.summary
        }

        let execResult = runProcessWithTimeout(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["--no-optional-locks", "-C", gitRoot, "diff", "HEAD", "--numstat"],
            captureStdout: true,
            timeoutSeconds: 2.0
        )

        guard execResult.succeeded, let text = String(data: execResult.outputData, encoding: .utf8) else {
            let fallback = cached.staleSummary
            DiscoveryCache.shared.setCachedGitDiff(fallback, for: gitRoot, now: now)
            return fallback
        }

        var summary: GitDiffSummary? = nil
        var files = 0
        var ins = 0
        var del = 0
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count >= 3 else { continue }
            files += 1
            if let a = Int(parts[0]) { ins += a }
            if let d = Int(parts[1]) { del += d }
        }
        let candidate = GitDiffSummary(changedFiles: files, insertions: ins, deletions: del)
        if !candidate.isEmpty {
            summary = candidate
        }

        DiscoveryCache.shared.setCachedGitDiff(summary, for: gitRoot, now: now)
        return summary
    }

    private nonisolated static func remoteGitCacheKey(sshTarget: String, remoteCwd: String) -> String {
        let host = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let path = remoteCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        return "ssh://\(host):\(path)"
    }

    private nonisolated static func inspectRemoteSSHGitMetadata(sshTarget: String, remoteCwd: String) -> RemoteGitMetadata? {
        let trimmedTarget = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCwd = remoteCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty, !trimmedCwd.isEmpty, trimmedCwd != "~", trimmedCwd != "/" else {
            return nil
        }

        let cacheKey = remoteGitCacheKey(sshTarget: trimmedTarget, remoteCwd: trimmedCwd)
        let now = ProcessInfo.processInfo.systemUptime
        let cached = DiscoveryCache.shared.cachedRemoteGit(for: cacheKey, now: now, ttl: 12.0, negativeTTL: 15.0)

        if cached.freshHit {
            guard let meta = cached.staleMetadata, meta.isValidResponse else { return nil }
            return meta
        }

        if let stale = cached.staleMetadata {
            if DiscoveryCache.shared.markRemoteGitInFlight(cacheKey) {
                Task.detached(priority: .utility) {
                    defer { DiscoveryCache.shared.clearRemoteGitInFlight(cacheKey) }
                    let refreshed = Self.fetchRemoteSSHGitMetadata(sshTarget: trimmedTarget, remoteCwd: trimmedCwd)
                    let updatedNow = ProcessInfo.processInfo.systemUptime
                    DiscoveryCache.shared.setCachedRemoteGit(refreshed, for: cacheKey, now: updatedNow)
                }
            }
            return stale.isValidResponse ? stale : nil
        }

        guard DiscoveryCache.shared.markRemoteGitInFlight(cacheKey) else {
            return nil
        }
        defer { DiscoveryCache.shared.clearRemoteGitInFlight(cacheKey) }
        let fetched = fetchRemoteSSHGitMetadata(sshTarget: trimmedTarget, remoteCwd: trimmedCwd)
        let finishedNow = ProcessInfo.processInfo.systemUptime
        DiscoveryCache.shared.setCachedRemoteGit(fetched, for: cacheKey, now: finishedNow)
        return fetched.isValidResponse ? fetched : nil
    }

    private nonisolated static func fetchRemoteSSHGitMetadata(sshTarget: String, remoteCwd: String) -> RemoteGitMetadata {
        let cdExpr: String = {
            if remoteCwd.hasPrefix("~/") {
                let rel = String(remoteCwd.dropFirst(2))
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "cd \"$HOME/\(rel)\""
            } else {
                let escaped = remoteCwd
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "cd \"\(escaped)\""
            }
        }()

        let remoteScript = "\(cdExpr) 2>/dev/null || exit 0; git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0; echo \"AM_ROOT:$(git rev-parse --show-toplevel 2>/dev/null)\"; echo \"AM_GITDIR:$(git rev-parse --git-dir 2>/dev/null)\"; br=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short=7 HEAD 2>/dev/null); echo \"AM_BRANCH:$br\"; git --no-optional-locks diff HEAD --numstat 2>/dev/null"

        let sshURL = URL(fileURLWithPath: "/usr/bin/ssh")
        let controlPathOpt = "ControlPath=/tmp/agentmeter-ssh-%C"
        var execResult = runProcessWithTimeout(
            executableURL: sshURL,
            arguments: [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=3",
                "-o", "ControlMaster=auto",
                "-o", controlPathOpt,
                "-o", "ControlPersist=300s",
                sshTarget,
                remoteScript,
            ],
            captureStdout: true,
            timeoutSeconds: 4.5
        )

        if !execResult.succeeded && !execResult.timedOut {
            _ = runProcessWithTimeout(
                executableURL: sshURL,
                arguments: ["-O", "exit", "-o", controlPathOpt, sshTarget],
                captureStdout: false,
                timeoutSeconds: 1.0
            )
            execResult = runProcessWithTimeout(
                executableURL: sshURL,
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=2",
                    sshTarget,
                    remoteScript,
                ],
                captureStdout: true,
                timeoutSeconds: 2.5
            )
        }

        guard execResult.succeeded,
              let text = String(data: execResult.outputData, encoding: .utf8) else {
            return RemoteGitMetadata(branch: nil, isWorktree: false, diff: nil, gitRoot: nil, isValidResponse: false)
        }

        guard !text.isEmpty else {
            return RemoteGitMetadata(branch: nil, isWorktree: false, diff: nil, gitRoot: nil, isValidResponse: true)
        }

        var gitRoot: String? = nil
        var isWorktree = false
        var branch: String? = nil
        var files = 0
        var ins = 0
        var del = 0

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("AM_ROOT:") {
                let val = String(line.dropFirst("AM_ROOT:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !val.isEmpty {
                    gitRoot = val
                }
            } else if line.hasPrefix("AM_GITDIR:") {
                let val = String(line.dropFirst("AM_GITDIR:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if val.contains("/worktrees/") {
                    isWorktree = true
                }
            } else if line.hasPrefix("AM_BRANCH:") {
                let val = String(line.dropFirst("AM_BRANCH:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !val.isEmpty, val != "HEAD" {
                    branch = val
                }
            } else if rawLine.contains("\t") {
                let parts = rawLine.split(separator: "\t", maxSplits: 2)
                if parts.count >= 3 {
                    files += 1
                    if let a = Int(parts[0].trimmingCharacters(in: .whitespaces)) { ins += a }
                    if let d = Int(parts[1].trimmingCharacters(in: .whitespaces)) { del += d }
                }
            }
        }

        let candidateDiff = GitDiffSummary(changedFiles: files, insertions: ins, deletions: del)
        let diff: GitDiffSummary? = candidateDiff.isEmpty ? nil : candidateDiff
        return RemoteGitMetadata(branch: branch, isWorktree: isWorktree, diff: diff, gitRoot: gitRoot)
    }

    private nonisolated static func extractGitBranchFromTerminal(tail: String?, title: String?) -> String? {
        var candidates: [String] = []
        if let tail {
            let lines = tail.split(separator: "\n").suffix(15).reversed()
            candidates.append(contentsOf: lines.map(String.init))
        }
        if let title, !title.isEmpty {
            candidates.append(title)
        }

        let patterns = [
            "git:\\(([A-Za-z0-9._/-]+)\\)",
            "on\\s+⎇\\s*([A-Za-z0-9._/-]+)",
            "⎇\\s+([A-Za-z0-9._/-]+)",
            "\u{E0A0}\\s*([A-Za-z0-9._/-]+)",
        ]

        for line in candidates {
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                if let match = regex.firstMatch(in: line, range: fullRange), match.numberOfRanges >= 2 {
                    let branchRange = match.range(at: 1)
                    if branchRange.location != NSNotFound {
                        let extracted = nsLine.substring(with: branchRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !extracted.isEmpty, extracted != "HEAD" {
                            return extracted
                        }
                    }
                }
            }
        }
        return nil
    }

    private nonisolated static func extractDiffFromPreviewLines(_ lines: [String]) -> GitDiffSummary? {
        for line in lines.reversed() {
            guard let plusIdx = line.range(of: "\\+(\\d+)\\s+-(\\d+)", options: .regularExpression) else { continue }
            let snippet = String(line[plusIdx])
            let nums = snippet.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if nums.count >= 2 && (nums[0] > 0 || nums[1] > 0) {
                return GitDiffSummary(changedFiles: 1, insertions: nums[0], deletions: nums[1])
            }
        }
        return nil
    }

    // MARK: - Process Table & CWD Inspection

    private struct ProcessEntry {
        let pid: Int32
        let ppid: Int32
        let tty: String?
        let family: AgentFamily
        let cpu: Double
        let cwdPath: String
        var workspaceName: String {
            let name = URL(fileURLWithPath: cwdPath).lastPathComponent
            return name.isEmpty || name == "/" ? (AppLanguage.current == .english ? "Default" : "默认目录") : name
        }
    }

    private struct ScannedProcesses {
        let candidates: [ProcessEntry]
        let ppidMap: [Int32: Int32]
        let sshPIDsByTTY: [String: Int32]
    }

    private nonisolated static let machTimebaseNumer: UInt64 = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return UInt64(max(1, info.numer))
    }()

    private nonisolated static let machTimebaseDenom: UInt64 = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return UInt64(max(1, info.denom))
    }()

    private nonisolated static func scanAgentProcesses() -> ScannedProcesses {
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return ScannedProcesses(candidates: [], ppidMap: [:], sshPIDsByTTY: [:]) }
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let byteSize = Int32(pids.count * MemoryLayout<Int32>.stride)
        count = proc_listallpids(&pids, byteSize)
        guard count > 0 else { return ScannedProcesses(candidates: [], ppidMap: [:], sshPIDsByTTY: [:]) }

        let myUID = getuid()
        let now = Date().timeIntervalSince1970
        var ppidMap: [Int32: Int32] = [:]
        ppidMap.reserveCapacity(Int(count))
        var sshPIDsByTTY: [String: Int32] = [:]
        var entries: [ProcessEntry] = []

        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let taskAllSize = Int32(MemoryLayout<proc_taskallinfo>.stride)
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)

        for i in 0..<Int(count) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var bsdInfo = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize else { continue }
            let ppid = Int32(bsdInfo.pbi_ppid)
            ppidMap[pid] = ppid
            guard bsdInfo.pbi_uid == myUID else { continue }

            let commName = withUnsafePointer(to: &bsdInfo.pbi_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                    String(cString: cStr)
                }
            }
            let shortComm = withUnsafePointer(to: &bsdInfo.pbi_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                    String(cString: cStr)
                }
            }
            let effectiveComm = commName.isEmpty ? shortComm : commName

            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let execPath: String = pathLen > 0
                ? pathBuffer.withUnsafeBufferPointer { buf in
                    let count = buf.firstIndex(of: 0) ?? Int(pathLen)
                    return String(decoding: buf.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                }
                : effectiveComm

            let lowerComm = effectiveComm.lowercased()
            let lowerExec = execPath.lowercased()
            let ttyDev = bsdInfo.e_tdev
            let tty: String? = (ttyDev != UInt32.max && ttyDev != 0) ? String(format: "ttys%03d", ttyDev & 0xff) : nil

            if lowerComm == "ssh" || lowerExec.hasSuffix("/ssh"), let tty {
                sshPIDsByTTY[tty] = pid
                continue
            }

            // Fast pre-filter before inspecting full command-line args
            let maybeAgent = lowerComm == "codex" || lowerComm == "claude" || lowerComm == "copilot" ||
                lowerComm == "agy" || lowerComm == "antigravity" || lowerComm == "node" ||
                lowerExec.contains("codex") || lowerExec.contains("claude") ||
                lowerExec.contains("copilot") || lowerExec.contains("agy") || lowerExec.contains("antigravity")
            guard maybeAgent else { continue }

            let args = processCommandLineArgs(pid: pid) ?? execPath
            guard let family = classifyProcess(comm: execPath, args: args) else { continue }

            var cpu = 0.0
            var taskAll = proc_taskallinfo()
            if proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &taskAll, taskAllSize) == taskAllSize {
                let totalTicks = taskAll.ptinfo.pti_total_user + taskAll.ptinfo.pti_total_system
                let totalNs = (totalTicks * machTimebaseNumer) / machTimebaseDenom
                cpu = DiscoveryCache.shared.computeCPUPercent(pid: pid, totalTimeNs: totalNs, now: now)
            }

            let cwd = processWorkingDirectory(pid: pid) ?? ""
            entries.append(ProcessEntry(pid: pid, ppid: ppid, tty: tty, family: family, cpu: cpu, cwdPath: cwd))
        }
        return ScannedProcesses(candidates: entries, ppidMap: ppidMap, sshPIDsByTTY: sshPIDsByTTY)
    }

    private nonisolated static func processCommandLineArgs(pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.stride, size <= 262_144 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.stride else {
            return nil
        }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0, argc < 512 else { return nil }

        var offset = MemoryLayout<Int32>.stride
        // Skip executable path string
        while offset < size && buffer[offset] != 0 { offset += 1 }
        // Skip trailing null bytes after exec path
        while offset < size && buffer[offset] == 0 { offset += 1 }

        var parts: [String] = []
        parts.reserveCapacity(Int(min(argc, 16)))
        var currentStart = offset
        while offset < size && parts.count < Int(min(argc, 16)) {
            if buffer[offset] == 0 {
                if offset > currentStart,
                   let arg = String(bytes: buffer[currentStart..<offset], encoding: .utf8) {
                    parts.append(arg)
                }
                offset += 1
                currentStart = offset
            } else {
                offset += 1
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private nonisolated static func classifyProcess(comm: String, args: String) -> AgentFamily? {
        let lowerComm = comm.lowercased()
        let lowerArgs = args.lowercased()

        if lowerArgs.contains("daemon run") || lowerArgs.contains("bg-pty-host") || lowerArgs.contains("bg-spare") || lowerArgs.contains("--bg-spare") || lowerArgs.contains("--bg-pty-host") {
            return nil
        }
        if lowerArgs.contains("app-server") || lowerArgs.contains("code-mode-host") || lowerArgs.contains("bridge.py") {
            return nil
        }
        if lowerArgs.contains("copilot-runtime") && lowerArgs.contains("visual studio code.app") {
            return nil
        }

        let firstArgToken = lowerArgs.split(separator: " ").first.map(String.init) ?? lowerArgs

        if lowerComm.hasSuffix("/codex") || lowerComm == "codex" ||
           firstArgToken == "codex" || firstArgToken.hasSuffix("/codex") ||
           lowerArgs.contains("/bin/codex") || lowerArgs.contains("@openai/codex") {
            return .codex
        }
        if lowerComm.hasSuffix("/claude") || lowerComm == "claude" ||
           lowerComm.contains("/share/claude/versions/") || lowerComm.contains("/claude/versions/") ||
           firstArgToken == "claude" || firstArgToken.hasSuffix("/claude") ||
           lowerArgs.contains("/bin/claude") || lowerArgs.contains("@anthropic-ai/claude-code") ||
           lowerArgs.contains("/share/claude/versions/") {
            if lowerArgs.contains("claude.app/") { return nil }
            return .claude
        }
        if lowerComm.hasSuffix("/copilot") || lowerComm == "copilot" ||
           firstArgToken == "copilot" || firstArgToken.hasSuffix("/copilot") ||
           lowerArgs.contains("/copilot-cli/") || lowerArgs.contains("@github/copilot") ||
           lowerArgs.contains("/bin/copilot") || lowerArgs.contains("gh copilot") {
            return .copilot
        }
        if lowerComm.hasSuffix("/agy") || lowerComm == "agy" ||
           lowerComm.hasSuffix("/antigravity") || lowerComm == "antigravity" ||
           firstArgToken == "agy" || firstArgToken.hasSuffix("/agy") ||
           firstArgToken == "antigravity" || firstArgToken.hasSuffix("/antigravity") ||
           lowerArgs.contains("/bin/agy") || lowerArgs.contains("antigravity-cli") {
            if lowerArgs.contains("language_server") { return nil }
            return .antigravity
        }
        return nil
    }

    private nonisolated static func processWorkingDirectory(pid: Int32) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, size)
        guard ret == size else { return nil }
        return withUnsafePointer(to: &vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                String(cString: cStr)
            }
        }
    }

    // MARK: - Codex Session Rollout & Title Parser

    private struct CodexSessionInfo {
        let sessionID: String
        let cwdPath: String
        let fallbackTitle: String?
        let isTaskRunning: Bool
        let updatedAt: Date

        var workspaceName: String {
            let name = URL(fileURLWithPath: cwdPath).lastPathComponent
            return name.isEmpty || name == "/" ? "Codex" : name
        }
    }

    private struct CodexTitleIndex {
        var bySessionID: [String: String] = [:]
        var byCwd: [String: String] = [:]
        var recentPromptsBySessionID: [String: [String]] = [:]
    }

    private nonisolated static func matchCodexSession(
        for proc: ProcessEntry,
        rexEntry: RexBlockEntry?,
        ghosttyEntry: GhosttyTerminalEntry? = nil,
        exactThreadID: String?,
        sessions: [CodexSessionInfo],
        titles: CodexTitleIndex,
        matchedSessionIDs: inout Set<String>
    ) -> CodexSessionInfo? {
        if let exactThreadID, !matchedSessionIDs.contains(exactThreadID) {
            matchedSessionIDs.insert(exactThreadID)
            if let info = sessions.first(where: { $0.sessionID == exactThreadID }) {
                return info
            }
            return CodexSessionInfo(
                sessionID: exactThreadID,
                cwdPath: proc.cwdPath,
                fallbackTitle: titles.bySessionID[exactThreadID],
                isTaskRunning: false,
                updatedAt: syntheticTimestampSentinel
            )
        }

        let screenPrompts = rexEntry?.screenPrompts ?? ghosttyEntry?.screenPrompts ?? []

        if !screenPrompts.isEmpty {
            for prompt in screenPrompts.reversed() {
                if let matchedSID = titles.recentPromptsBySessionID.first(where: { sid, prompts in
                    !matchedSessionIDs.contains(sid) && prompts.contains(where: { $0.contains(prompt) || prompt.contains($0) })
                })?.key {
                    matchedSessionIDs.insert(matchedSID)
                    if let info = sessions.first(where: { $0.sessionID == matchedSID }) {
                        return info
                    }
                    return CodexSessionInfo(
                        sessionID: matchedSID,
                        cwdPath: proc.cwdPath,
                        fallbackTitle: titles.bySessionID[matchedSID] ?? prompt,
                        isTaskRunning: false,
                        updatedAt: syntheticTimestampSentinel
                    )
                }
                if let info = sessions.first(where: {
                    !matchedSessionIDs.contains($0.sessionID) && (
                        ($0.fallbackTitle.map { $0.contains(prompt) || prompt.contains($0) } ?? false) ||
                        (titles.bySessionID[$0.sessionID].map { $0.contains(prompt) || prompt.contains($0) } ?? false)
                    )
                }) {
                    matchedSessionIDs.insert(info.sessionID)
                    return info
                }
            }
        }

        if let info = sessions.first(where: { !matchedSessionIDs.contains($0.sessionID) && $0.cwdPath == proc.cwdPath }) {
            matchedSessionIDs.insert(info.sessionID)
            return info
        }
        return nil
    }

    private nonisolated static func mapCodexPIDsToThreadIDs(
        home: URL,
        pids: [Int32],
        validThreadIDs: Set<String>
    ) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        var result: [Int32: String] = [:]
        var uncachedPIDs: [Int32] = []

        for pid in pids {
            if let cachedTID = DiscoveryCache.shared.cachedCodexThreadID(for: pid),
               validThreadIDs.contains(cachedTID) {
                result[pid] = cachedTID
            } else {
                uncachedPIDs.append(pid)
            }
        }
        guard !uncachedPIDs.isEmpty else { return result }

        let logsURL = home.appendingPathComponent(".codex/logs_2.sqlite")
        var db: OpaquePointer?
        guard sqlite3_open_v2(logsURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return result
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 400)

        let sessionSQL = """
        SELECT ts, ts_nanos FROM logs
        WHERE thread_id IS NULL
          AND process_uuid >= ? AND process_uuid < ?
          AND target = 'rmcp::transport::streamable_http_server::session::local'
        ORDER BY ts DESC, ts_nanos DESC, id DESC LIMIT 4;
        """
        let resumeSQL = """
        SELECT thread_id FROM logs
        WHERE ts BETWEEN ? AND ?
          AND thread_id IS NOT NULL
          AND (feedback_log_body LIKE '%thread/resume%' OR feedback_log_body LIKE '%thread/start%')
        ORDER BY ABS((ts - ?) * 1000000000 + (ts_nanos - ?)) ASC LIMIT 6;
        """

        var sessionStmt: OpaquePointer?
        var resumeStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sessionSQL, -1, &sessionStmt, nil) == SQLITE_OK,
              sqlite3_prepare_v2(db, resumeSQL, -1, &resumeStmt, nil) == SQLITE_OK else {
            if sessionStmt != nil { sqlite3_finalize(sessionStmt) }
            if resumeStmt != nil { sqlite3_finalize(resumeStmt) }
            return result
        }
        defer {
            sqlite3_finalize(sessionStmt)
            sqlite3_finalize(resumeStmt)
        }

        let sqlTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        for pid in uncachedPIDs {
            let low = "pid:\(pid):"
            let high = "pid:\(pid);"
            sqlite3_reset(sessionStmt)
            sqlite3_bind_text(sessionStmt, 1, low, -1, sqlTransient)
            sqlite3_bind_text(sessionStmt, 2, high, -1, sqlTransient)

            var timestamps: [(Int64, Int64)] = []
            while sqlite3_step(sessionStmt) == SQLITE_ROW {
                let ts = sqlite3_column_int64(sessionStmt, 0)
                let nanos = sqlite3_column_int64(sessionStmt, 1)
                timestamps.append((ts, nanos))
            }

            var matchedTID: String?
            for (ts, nanos) in timestamps {
                sqlite3_reset(resumeStmt)
                sqlite3_bind_int64(resumeStmt, 1, ts - 1)
                sqlite3_bind_int64(resumeStmt, 2, ts + 2)
                sqlite3_bind_int64(resumeStmt, 3, ts)
                sqlite3_bind_int64(resumeStmt, 4, nanos)
                while sqlite3_step(resumeStmt) == SQLITE_ROW {
                    if let cStr = sqlite3_column_text(resumeStmt, 0) {
                        let tid = String(cString: cStr)
                        if validThreadIDs.contains(tid) {
                            matchedTID = tid
                            break
                        }
                    }
                }
                if matchedTID != nil { break }
            }
            if let matchedTID {
                result[pid] = matchedTID
                DiscoveryCache.shared.setCachedCodexThreadID(matchedTID, for: pid)
            }
        }
        return result
    }

    private nonisolated static func fileStamp(_ url: URL) -> String {
        guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return "missing"
        }
        let mtime = vals.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = vals.fileSize ?? 0
        return "\(mtime):\(size)"
    }

    private nonisolated static func loadCodexTitles(home: URL) -> CodexTitleIndex {
        let sessionIndexURL = home.appendingPathComponent(".codex/session_index.jsonl")
        let dbURL = home.appendingPathComponent(".codex/state_5.sqlite")
        let dbWalURL = home.appendingPathComponent(".codex/state_5.sqlite-wal")
        let historyURL = home.appendingPathComponent(".codex/history.jsonl")

        let stamp = [
            fileStamp(sessionIndexURL),
            fileStamp(dbURL),
            fileStamp(dbWalURL),
            fileStamp(historyURL),
        ].joined(separator: "|")

        if let cached = DiscoveryCache.shared.cachedCodexTitles(stamp: stamp) {
            return cached
        }

        var index = CodexTitleIndex()

        if let data = try? Data(contentsOf: sessionIndexURL),
           let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                if let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                   let id = json["id"] as? String,
                   let name = cleanSessionTitle(json["thread_name"] as? String) {
                    index.bySessionID[id] = name
                }
            }
        }

        var db: OpaquePointer?
        if sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK {
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db, 400)
            let sql = "SELECT id, COALESCE(NULLIF(name, ''), NULLIF(title, ''), first_user_message), cwd FROM threads ORDER BY updated_at DESC LIMIT 80;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                    let rawTitle = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                    let cwd = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                    if let title = cleanSessionTitle(rawTitle) {
                        if !id.isEmpty && index.bySessionID[id] == nil {
                            index.bySessionID[id] = title
                        }
                        if !cwd.isEmpty && index.byCwd[cwd] == nil {
                            index.byCwd[cwd] = title
                        }
                    }
                }
            }
        }

        if let handle = try? FileHandle(forReadingFrom: historyURL) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            let offset = size > 65536 ? size - 65536 : 0
            try? handle.seek(toOffset: offset)
            if let data = try? handle.readToEnd(),
               let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          let sid = json["session_id"] as? String,
                          let prompt = cleanSessionTitle(json["text"] as? String) else { continue }
                    if index.bySessionID[sid] == nil {
                        index.bySessionID[sid] = prompt
                    }
                    index.recentPromptsBySessionID[sid, default: []].append(prompt)
                }
            }
        }

        DiscoveryCache.shared.setCachedCodexTitles(index, stamp: stamp)
        return index
    }

    private nonisolated static func inspectCodexSessions(home: URL) -> [CodexSessionInfo] {
        let sessionsRoot = home.appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-6 * 3600)
        var recentFiles: [(url: URL, modDate: Date)] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modDate = values.contentModificationDate,
                  modDate > cutoff else { continue }
            recentFiles.append((fileURL, modDate))
        }

        recentFiles.sort { $0.modDate > $1.modDate }
        var infos: [CodexSessionInfo] = []
        var seenSessionIDs = Set<String>()

        for entry in recentFiles.prefix(16) {
            guard let info = parseCodexRolloutFile(entry.url, modDate: entry.modDate),
                  !seenSessionIDs.contains(info.sessionID) else { continue }
            seenSessionIDs.insert(info.sessionID)
            infos.append(info)
        }
        return infos
    }

    private nonisolated static func parseCodexRolloutFile(_ url: URL, modDate: Date) -> CodexSessionInfo? {
        let activelyWritingWindow = Date().timeIntervalSince(modDate) < 4.0
        if !activelyWritingWindow, let cached = DiscoveryCache.shared.cachedCodexRollout(path: url.path, modDate: modDate) {
            return cached
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let headData = (try? handle.read(upToCount: 16384)) ?? Data()
        let headStr = String(data: headData, encoding: .utf8) ?? ""
        let headLines = headStr.split(separator: "\n")
        let firstLine = headLines.first.map(String.init) ?? ""

        var sessionID = url.deletingPathExtension().lastPathComponent
        var cwdPath = ""
        if let json = try? JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any],
           let payload = json["payload"] as? [String: Any] {
            if let id = payload["session_id"] as? String { sessionID = id }
            if let cwd = payload["cwd"] as? String { cwdPath = cwd }
        }
        guard !cwdPath.isEmpty else { return nil }

        var fallbackTitle: String?
        for line in headLines.dropFirst().prefix(8) {
            guard line.contains("\"role\":\"user\""),
                  let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  let contents = payload["content"] as? [[String: Any]] else { continue }
            for item in contents {
                if let rawText = item["text"] as? String,
                   let extracted = extractUserPromptAfterEnvironment(rawText) {
                    fallbackTitle = extracted
                    break
                }
            }
            if fallbackTitle != nil { break }
        }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let tailOffset = fileSize > 24576 ? fileSize - 24576 : 0
        try? handle.seek(toOffset: tailOffset)
        let tailData = (try? handle.readToEnd()) ?? Data()
        let tailStr = String(data: tailData, encoding: .utf8) ?? ""

        var lastStarted = false
        for line in tailStr.split(separator: "\n") {
            if line.contains("\"type\":\"task_started\"") {
                lastStarted = true
            } else if line.contains("\"type\":\"task_complete\"") || line.contains("\"type\":\"turn_aborted\"") {
                lastStarted = false
            }
        }
        let activelyWriting = activelyWritingWindow && lastStarted
        let isRunning = lastStarted || activelyWriting

        let info = CodexSessionInfo(
            sessionID: sessionID,
            cwdPath: cwdPath,
            fallbackTitle: fallbackTitle,
            isTaskRunning: isRunning,
            updatedAt: modDate
        )
        if !activelyWritingWindow {
            DiscoveryCache.shared.setCachedCodexRollout(info, path: url.path, modDate: modDate)
        }
        return info
    }

    // MARK: - Claude Code CLI Session Parser

    private struct ClaudePIDMetadata {
        let pid: Int32
        let sessionID: String
        let cwdPath: String
        let status: String?
        let name: String?
        let updatedAt: Date?
    }

    private struct ClaudeTranscriptSummary {
        let aiTitle: String?
        let lastPrompt: String?
        let modDate: Date?
    }

    private nonisolated static func inspectClaudeSessions(
        home: URL,
        liveProcesses: [ProcessEntry],
        rexMap: [Int32: RexBlockEntry],
        ghosttyMap: [Int32: GhosttyTerminalEntry]
    ) -> [AgentActivityItem] {
        guard !liveProcesses.isEmpty else { return [] }
        let pidMetaMap = loadClaudePIDMetadata(home: home, pids: liveProcesses.map(\.pid))
        let historyPrompts = loadClaudeHistoryPrompts(home: home)
        var items: [AgentActivityItem] = []

        for proc in liveProcesses {
            let rexEntry = rexMap[proc.pid]
            let ghosttyEntry = rexEntry == nil ? ghosttyMap[proc.pid] : nil
            let meta = pidMetaMap[proc.pid]
            let cwdPath = (meta?.cwdPath.isEmpty == false ? meta?.cwdPath : nil)
                ?? (!proc.cwdPath.isEmpty ? proc.cwdPath : nil)
                ?? ghosttyEntry?.cwdPath
                ?? ""
            let workspaceName: String = {
                let name = URL(fileURLWithPath: cwdPath).lastPathComponent
                return name.isEmpty || name == "/" ? "Claude" : name
            }()

            let transcript = meta.flatMap { inspectClaudeTranscript(home: home, cwdPath: cwdPath, sessionID: $0.sessionID) }
            let metaBusy = meta?.status?.lowercased() == "busy" || meta?.status?.lowercased() == "working"

            let status: AgentTaskStatus
            if let rexEntry {
                let inferred = rexEntry.inferredStatus
                if inferred == .needsInput || rexEntry.status == .needsInput {
                    status = .needsInput
                } else if let rexStatus = rexEntry.status {
                    status = rexStatus
                } else if metaBusy {
                    status = .working
                } else {
                    status = inferred
                }
            } else if let ghosttyEntry {
                let inferred = ghosttyEntry.inferredStatus
                if inferred == .needsInput {
                    status = .needsInput
                } else if metaBusy || proc.cpu > 3.5 || inferred == .working {
                    status = .working
                } else {
                    status = inferred
                }
            } else {
                let isWorking = metaBusy || (proc.cpu > 3.5)
                status = isWorking ? .working : .idle
            }

            let primaryTitle: String? = transcript?.aiTitle
                ?? rexEntry?.descriptiveTitle
                ?? ghosttyEntry?.descriptiveTitle
                ?? transcript?.lastPrompt
                ?? meta.flatMap { historyPrompts[$0.sessionID] }
            let fallbackTitle: String? = rexEntry?.latestScreenPrompt
                ?? ghosttyEntry?.latestScreenPrompt
                ?? rexEntry?.cleanTitle
                ?? ghosttyEntry?.cleanTitle
                ?? meta?.name
            let sessionTitle: String = primaryTitle ?? fallbackTitle ?? workspaceName

            let updatedAt = [meta?.updatedAt, transcript?.modDate].compactMap { $0 }.max() ?? syntheticTimestampSentinel
            let itemID: String = {
                if let rexEntry {
                    return "rex-block-\(rexEntry.location.blockID)"
                }
                if let meta {
                    return "claude-\(meta.sessionID)-pid-\(proc.pid)"
                }
                if let ghosttyEntry {
                    return "ghostty-term-\(ghosttyEntry.location.terminalID)-pid-\(proc.pid)"
                }
                return "claude-pid-\(proc.pid)"
            }()
            let en = AppLanguage.current == .english

            items.append(
                AgentActivityItem(
                    id: itemID,
                    sessionID: meta?.sessionID,
                    family: .claude,
                    workspace: workspaceName,
                    cwdPath: cwdPath,
                    title: sessionTitle,
                    status: status,
                    isFocusedInHost: rexEntry?.isFocusedInActiveWindow ?? ghosttyEntry?.isFocusedInActiveWindow ?? false,
                    detail: status == .needsInput
                        ? (en ? "Awaiting confirmation" : "等待确认")
                        : (status == .working ? (en ? "Running task" : "正在执行任务") : (en ? "Terminal idle" : "终端待命")),
                    updatedAt: updatedAt,
                    pid: proc.pid,
                    tty: proc.tty ?? ghosttyEntry?.ttyName,
                    rexPane: rexEntry?.location,
                    ghosttyPane: ghosttyEntry?.location
                )
            )
        }
        return items
    }

    private nonisolated static func loadClaudePIDMetadata(home: URL, pids: [Int32]) -> [Int32: ClaudePIDMetadata] {
        let sessionsDir = home.appendingPathComponent(".claude/sessions")
        var result: [Int32: ClaudePIDMetadata] = [:]
        for pid in pids {
            let fileURL = sessionsDir.appendingPathComponent("\(pid).json")
            guard let data = try? Data(contentsOf: fileURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sid = json["sessionId"] as? String, !sid.isEmpty else { continue }
            let cwd = (json["cwd"] as? String) ?? ""
            let status = json["status"] as? String
            let name = cleanSessionTitle(json["name"] as? String)
            let updatedMs = (json["statusUpdatedAt"] as? Double) ?? (json["updatedAt"] as? Double)
            let updatedAt = updatedMs.map { Date(timeIntervalSince1970: $0 / 1000.0) }
            result[pid] = ClaudePIDMetadata(
                pid: pid,
                sessionID: sid,
                cwdPath: cwd,
                status: status,
                name: name,
                updatedAt: updatedAt
            )
        }
        return result
    }

    private nonisolated static func loadClaudeHistoryPrompts(home: URL) -> [String: String] {
        let historyURL = home.appendingPathComponent(".claude/history.jsonl")
        let modDate = (try? historyURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let modDate, let cached = DiscoveryCache.shared.cachedClaudeHistory(modDate: modDate) {
            return cached
        }
        guard let handle = try? FileHandle(forReadingFrom: historyURL) else { return [:] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > 65536 ? size - 65536 : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return [:] }

        var bySession: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let sid = json["sessionId"] as? String,
                  let display = json["display"] as? String,
                  !display.hasPrefix("/"),
                  let cleaned = cleanSessionTitle(display) else { continue }
            bySession[sid] = cleaned
        }
        if let modDate {
            DiscoveryCache.shared.setCachedClaudeHistory(bySession, modDate: modDate)
        }
        return bySession
    }

    private nonisolated static func inspectClaudeTranscript(home: URL, cwdPath: String, sessionID: String) -> ClaudeTranscriptSummary? {
        let projectsRoot = home.appendingPathComponent(".claude/projects")
        let slug = cwdPath.replacingOccurrences(of: "/", with: "-")
        var candidateURL = projectsRoot.appendingPathComponent(slug).appendingPathComponent("\(sessionID).jsonl")
        if !FileManager.default.fileExists(atPath: candidateURL.path) {
            if let dirs = try? FileManager.default.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for dir in dirs {
                    let alt = dir.appendingPathComponent("\(sessionID).jsonl")
                    if FileManager.default.fileExists(atPath: alt.path) {
                        candidateURL = alt
                        break
                    }
                }
            }
        }
        guard FileManager.default.fileExists(atPath: candidateURL.path) else { return nil }
        let modDate = (try? candidateURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let modDate, let cached = DiscoveryCache.shared.cachedClaudeTranscript(path: candidateURL.path, modDate: modDate) {
            return cached
        }
        guard let handle = try? FileHandle(forReadingFrom: candidateURL) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > 32768 ? size - 32768 : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""

        var aiTitle: String?
        var lastPrompt: String?
        for line in text.split(separator: "\n") {
            if line.contains("\"ai-title\""),
               let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let raw = cleanSessionTitle(json["aiTitle"] as? String) {
                aiTitle = raw
            } else if line.contains("\"last-prompt\""),
                      let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let raw = json["lastPrompt"] as? String,
                      !raw.hasPrefix("/"),
                      let cleaned = cleanSessionTitle(raw) {
                lastPrompt = cleaned
            }
        }
        let summary = ClaudeTranscriptSummary(aiTitle: aiTitle, lastPrompt: lastPrompt, modDate: modDate)
        if let modDate {
            DiscoveryCache.shared.setCachedClaudeTranscript(summary, path: candidateURL.path, modDate: modDate)
        }
        return summary
    }

    // MARK: - Copilot CLI Session Parser

    private nonisolated static func inspectCopilotSessions(
        home: URL,
        liveProcesses: [ProcessEntry],
        rexMap: [Int32: RexBlockEntry],
        ghosttyMap: [Int32: GhosttyTerminalEntry]
    ) -> [AgentActivityItem] {
        guard !liveProcesses.isEmpty else { return [] }
        var items: [AgentActivityItem] = []
        var matchedPIDs = Set<Int32>()

        let sessionStateRoot = home.appendingPathComponent(".copilot/session-state")
        let openSessionsURL = home.appendingPathComponent(".copilot/open-sessions-state.json")

        struct OpenSessionEntry {
            let working: Bool
            let refreshedAt: Date?
        }
        var openSessionMap: [String: OpenSessionEntry] = [:]
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let data = try? Data(contentsOf: openSessionsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            for (sid, dict) in json {
                let working = (dict["working"] as? Bool) ?? false
                let refreshedStr = (dict["refreshedAt"] as? String) ?? (dict["openedAt"] as? String)
                let refreshedDate = refreshedStr.flatMap { isoFormatter.date(from: $0) }
                openSessionMap[sid] = OpenSessionEntry(working: working, refreshedAt: refreshedDate)
            }
        }

        if let dirs = try? FileManager.default.contentsOfDirectory(
            at: sessionStateRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            let sortedDirs = dirs.compactMap { url -> (URL, Date)? in
                let eventsURL = url.appendingPathComponent("events.jsonl")
                guard let vals = try? eventsURL.resourceValues(forKeys: [.contentModificationDateKey]),
                      let mod = vals.contentModificationDate else { return nil }
                return (url, mod)
            }.sorted { $0.1 > $1.1 }

            for (dirURL, modDate) in sortedDirs.prefix(6) {
                let sid = dirURL.lastPathComponent
                let eventsURL = dirURL.appendingPathComponent("events.jsonl")
                let workspaceURL = dirURL.appendingPathComponent("workspace.yaml")

                let cwdPath = parseSimpleYAMLValue(at: workspaceURL, key: "cwd") ?? ""
                let yamlTitle = cleanSessionTitle(parseSimpleYAMLValue(at: workspaceURL, key: "name"))
                let workspaceName: String = {
                    let name = URL(fileURLWithPath: cwdPath).lastPathComponent
                    return name.isEmpty || name == "/" ? "Copilot" : name
                }()

                guard let proc = liveProcesses.first(where: { !matchedPIDs.contains($0.pid) && !cwdPath.isEmpty && $0.cwdPath == cwdPath }) else {
                    continue
                }
                matchedPIDs.insert(proc.pid)
                let rexEntry = rexMap[proc.pid]
                let ghosttyEntry = rexEntry == nil ? ghosttyMap[proc.pid] : nil

                let state = parseCopilotEventsTail(eventsURL)
                let openInfo = openSessionMap[sid]
                let status: AgentTaskStatus
                if let rexEntry {
                    let inferred = rexEntry.inferredStatus
                    if inferred == .needsInput {
                        status = .needsInput
                    } else if openInfo?.working == true || state.inTurn {
                        status = .working
                    } else {
                        status = inferred
                    }
                } else if let ghosttyEntry {
                    let inferred = ghosttyEntry.inferredStatus
                    if inferred == .needsInput {
                        status = .needsInput
                    } else if (openInfo?.working == true) || state.inTurn || (proc.cpu > 3.5) || inferred == .working {
                        status = .working
                    } else {
                        status = inferred
                    }
                } else {
                    let isWorking = (openInfo?.working == true) || state.inTurn || (proc.cpu > 3.5)
                    status = isWorking ? .working : .idle
                }
                let en = AppLanguage.current == .english
                let sessionTitle = yamlTitle
                    ?? rexEntry?.cleanTitle
                    ?? ghosttyEntry?.cleanTitle
                    ?? state.lastUserMessage
                    ?? (en ? "Copilot Session" : "Copilot 会话")
                let itemID = rexEntry.map { "rex-block-\($0.location.blockID)" }
                    ?? "copilot-\(sid)-pid-\(proc.pid)"
                items.append(
                    AgentActivityItem(
                        id: itemID,
                        sessionID: sid,
                        family: .copilot,
                        workspace: workspaceName,
                        cwdPath: cwdPath,
                        title: sessionTitle,
                        status: status,
                        isFocusedInHost: rexEntry?.isFocusedInActiveWindow ?? ghosttyEntry?.isFocusedInActiveWindow ?? false,
                        detail: status == .needsInput
                            ? (en ? "Awaiting confirmation" : "等待确认")
                            : (status == .working ? (en ? "Running task" : "正在执行任务") : (en ? "Terminal idle" : "终端待命")),
                        updatedAt: max(modDate, openInfo?.refreshedAt ?? modDate),
                        pid: proc.pid,
                        tty: proc.tty ?? ghosttyEntry?.ttyName,
                        rexPane: rexEntry?.location,
                        ghosttyPane: ghosttyEntry?.location
                    )
                )
            }
        }

        let en = AppLanguage.current == .english
        for proc in liveProcesses where !matchedPIDs.contains(proc.pid) {
            let rexEntry = rexMap[proc.pid]
            let ghosttyEntry = rexEntry == nil ? ghosttyMap[proc.pid] : nil
            let status: AgentTaskStatus
            if let rexEntry {
                status = rexEntry.inferredStatus
            } else if let ghosttyEntry {
                let inferred = ghosttyEntry.inferredStatus
                status = (proc.cpu > 3.5 && inferred == .idle) ? .working : inferred
            } else {
                status = proc.cpu > 3.5 ? .working : .idle
            }
            let effectiveCwd = !proc.cwdPath.isEmpty ? proc.cwdPath : (ghosttyEntry?.cwdPath ?? "")
            let itemID = rexEntry.map { "rex-block-\($0.location.blockID)" }
                ?? ghosttyEntry.map { "ghostty-term-\($0.location.terminalID)-pid-\(proc.pid)" }
                ?? "copilot-pid-\(proc.pid)"
            items.append(
                AgentActivityItem(
                    id: itemID,
                    family: .copilot,
                    workspace: proc.workspaceName,
                    cwdPath: effectiveCwd,
                    title: rexEntry?.cleanTitle ?? ghosttyEntry?.cleanTitle ?? (en ? "Copilot Terminal Session" : "Copilot 终端会话"),
                    status: status,
                    isFocusedInHost: rexEntry?.isFocusedInActiveWindow ?? ghosttyEntry?.isFocusedInActiveWindow ?? false,
                    detail: status == .needsInput
                        ? (en ? "Awaiting confirmation" : "等待确认")
                        : (status == .working ? (en ? "Running task" : "正在执行任务") : (en ? "Terminal idle" : "终端待命")),
                    updatedAt: syntheticTimestampSentinel,
                    pid: proc.pid,
                    tty: proc.tty ?? ghosttyEntry?.ttyName,
                    rexPane: rexEntry?.location,
                    ghosttyPane: ghosttyEntry?.location
                )
            )
        }

        return items
    }

    private nonisolated static func parseCopilotEventsTail(_ url: URL) -> (inTurn: Bool, isShutdown: Bool, lastUserMessage: String?) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (false, true, nil) }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > 16384 ? size - 16384 : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""

        var inTurn = false
        var isShutdown = false
        var lastUserMessage: String?
        for line in text.split(separator: "\n") {
            if line.contains("\"assistant.turn_start\"") || line.contains("\"tool.execution_start\"") {
                inTurn = true
                isShutdown = false
            } else if line.contains("\"assistant.turn_end\"") {
                inTurn = false
            } else if line.contains("\"session.shutdown\"") {
                inTurn = false
                isShutdown = true
            }
            if line.contains("\"type\":\"user.message\""),
               let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let dataDict = json["data"] as? [String: Any],
               let content = cleanSessionTitle(dataDict["content"] as? String) {
                lastUserMessage = content
            }
        }
        return (inTurn, isShutdown, lastUserMessage)
    }

    private nonisolated static func parseSimpleYAMLValue(at url: URL, key: String) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let prefix = "\(key):"
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                return trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - Antigravity CLI Session Parser

    private nonisolated static func inspectAntigravitySessions(
        home: URL,
        liveProcesses: [ProcessEntry],
        rexMap: [Int32: RexBlockEntry],
        ghosttyMap: [Int32: GhosttyTerminalEntry]
    ) -> [AgentActivityItem] {
        guard !liveProcesses.isEmpty else { return [] }
        let logURL = home.appendingPathComponent(".gemini/antigravity-cli/cli.log")
        let historyURL = home.appendingPathComponent(".gemini/antigravity-cli/history.jsonl")
        let logState = parseAntigravityLogTail(logURL)
        let latestHistory = parseAntigravityLatestHistory(historyURL)

        var items: [AgentActivityItem] = []
        for proc in liveProcesses {
            let rexEntry = rexMap[proc.pid]
            let ghosttyEntry = rexEntry == nil ? ghosttyMap[proc.pid] : nil
            let status: AgentTaskStatus
            if let rexStatus = rexEntry?.status {
                status = rexStatus
            } else if let rexEntry {
                status = logState.isPending ? .working : rexEntry.inferredStatus
            } else if let ghosttyEntry {
                let inferred = ghosttyEntry.inferredStatus
                if inferred == .needsInput {
                    status = .needsInput
                } else if logState.isPending || proc.cpu > 3.5 || inferred == .working {
                    status = .working
                } else {
                    status = inferred
                }
            } else {
                status = (logState.isPending || proc.cpu > 3.5) ? .working : .idle
            }
            let en = AppLanguage.current == .english
            let effectiveCwd = !proc.cwdPath.isEmpty ? proc.cwdPath : (ghosttyEntry?.cwdPath ?? "")
            let workspace = effectiveCwd.isEmpty
                ? (latestHistory.workspace ?? "Antigravity")
                : {
                    let name = URL(fileURLWithPath: effectiveCwd).lastPathComponent
                    return name.isEmpty || name == "/" ? proc.workspaceName : name
                }()
            let sessionTitle = latestHistory.title
                ?? rexEntry?.cleanTitle
                ?? ghosttyEntry?.cleanTitle
                ?? logState.lastPrompt
                ?? (en ? "Antigravity Session" : "Antigravity 会话")
            let itemID = rexEntry.map { "rex-block-\($0.location.blockID)" }
                ?? ghosttyEntry.map { "ghostty-term-\($0.location.terminalID)-pid-\(proc.pid)" }
                ?? "antigravity-pid-\(proc.pid)"
            items.append(
                AgentActivityItem(
                    id: itemID,
                    sessionID: latestHistory.conversationID,
                    family: .antigravity,
                    workspace: workspace,
                    cwdPath: effectiveCwd,
                    title: sessionTitle,
                    status: status,
                    isFocusedInHost: rexEntry?.isFocusedInActiveWindow ?? ghosttyEntry?.isFocusedInActiveWindow ?? false,
                    detail: status == .needsInput
                        ? (en ? "Awaiting confirmation" : "等待确认")
                        : (status == .working ? (en ? "Generating response" : "正在生成响应") : (en ? "Terminal idle" : "终端待命")),
                    updatedAt: logState.modDate ?? syntheticTimestampSentinel,
                    pid: proc.pid,
                    tty: proc.tty ?? ghosttyEntry?.ttyName,
                    rexPane: rexEntry?.location,
                    ghosttyPane: ghosttyEntry?.location
                )
            )
        }
        return items
    }

    private nonisolated static func parseAntigravityLogTail(_ url: URL) -> (isPending: Bool, isShutDown: Bool, modDate: Date?, lastPrompt: String?) {
        let resolved = url.resolvingSymlinksInPath()
        let modDate = (try? resolved.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let handle = try? FileHandle(forReadingFrom: resolved) else {
            return (false, true, modDate, nil)
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > 24576 ? size - 24576 : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""

        var isPending = false
        var isShutDown = false
        var lastPrompt: String?
        for line in text.split(separator: "\n") {
            if let markerRange = line.range(of: "HandleUserInput called with text: \"") {
                let rest = line[markerRange.upperBound...]
                if let endQuote = rest.lastIndex(of: "\"") {
                    let candidate = String(rest[..<endQuote])
                    if !candidate.hasPrefix("/"), let cleaned = cleanSessionTitle(candidate) {
                        lastPrompt = cleaned
                    }
                }
            }
            if line.contains("Forwarding user message to conversation") || line.contains("Sending user message to conversation") {
                isPending = true
                isShutDown = false
            } else if line.contains("clearing ResponsePending") || line.contains("Full redraw completed") {
                isPending = false
            } else if line.contains("CLI program exited, shutting down") || line.contains("Language server shutting down") {
                isPending = false
                isShutDown = true
            }
        }
        return (isPending, isShutDown, modDate, lastPrompt)
    }

    private nonisolated static func parseAntigravityLatestHistory(_ url: URL) -> (conversationID: String?, workspace: String?, title: String?) {
        var conversationID: String?
        var workspace: String?
        var title: String?
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n").reversed() {
                guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                if conversationID == nil, let cid = json["conversationId"] as? String, !cid.isEmpty {
                    conversationID = cid
                }
                if workspace == nil, let ws = json["workspace"] as? String, !ws.isEmpty {
                    let name = URL(fileURLWithPath: ws).lastPathComponent
                    workspace = name.isEmpty ? ws : name
                }
                if title == nil,
                   (json["type"] as? String) != "slash_command",
                   let display = json["display"] as? String,
                   !display.hasPrefix("/"),
                   let cleaned = cleanSessionTitle(display) {
                    title = cleaned
                }
                if conversationID != nil && workspace != nil && title != nil { break }
            }
        }
        return (conversationID, workspace, title)
    }

    private nonisolated static func extractUserPromptAfterEnvironment(_ raw: String) -> String? {
        if let endTag = raw.range(of: "</environment_context>") {
            return cleanSessionTitle(String(raw[endTag.upperBound...]))
        }
        return cleanSessionTitle(raw)
    }

    private nonisolated static func cleanSessionTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty,
                      !line.hasPrefix("<"),
                      !line.hasPrefix("■"),
                      !line.hasPrefix("─"),
                      !line.hasPrefix("```") else { return false }
                let lower = line.lowercased()
                if lower.hasPrefix("hint:") || lower.hasPrefix("warning:") || lower.hasPrefix("error:") {
                    return false
                }
                return true
            }

        guard !lines.isEmpty else { return nil }
        // If the user pasted terminal output followed by a question on the last line, prefer the line with CJK or question mark if first line looks like a command/log
        if lines.count > 1,
           let first = lines.first,
           (first.hasPrefix("git ") || first.hasPrefix("$ ") || first.hasPrefix("% ")),
           let last = lines.last {
            return last
        }
        return lines.first
    }

    // MARK: - Rex Multiplexer Discovery & Tab Jump

    private struct RexBlockEntry {
        let location: RexPaneLocation
        let pid: Int32
        let processName: String
        let cwdPath: String
        let rawTitle: String?
        let reportedApp: String?
        let status: AgentTaskStatus?
        let screenMode: String?
        let screenTail: String?
        let screenPrompts: [String]
        let isFocusedInActiveWindow: Bool
        let isSSH: Bool
        let sshTarget: String?

        var latestScreenPrompt: String? {
            screenPrompts.last
        }

        var detectedFamily: AgentFamily? {
            if let app = reportedApp?.lowercased() {
                if app.contains("codex") { return .codex }
                if app.contains("claude") { return .claude }
                if app.contains("copilot") { return .copilot }
                if app.contains("agy") || app.contains("antigravity") { return .antigravity }
            }
            let lowerProc = processName.lowercased()
            if lowerProc == "codex" { return .codex }
            if lowerProc == "claude" { return .claude }
            if lowerProc == "copilot" { return .copilot }
            if lowerProc == "agy" || lowerProc == "antigravity" { return .antigravity }

            if let title = rawTitle {
                let lowerTitle = title.lowercased()
                if lowerTitle.contains("claude code") || lowerTitle.hasPrefix("✳ ") {
                    return .claude
                }
                if lowerTitle.contains("codex") {
                    return .codex
                }
                if lowerTitle.hasSuffix("- github copilot") || lowerTitle.contains("github copilot") {
                    return .copilot
                }
                if lowerTitle.contains("antigravity") {
                    return .antigravity
                }
                // Braille spinner title set by Codex/Copilot TUI when running in alternate screen
                if screenMode == "alternate",
                   let firstScalar = title.unicodeScalars.first,
                   (0x2800...0x28FF).contains(firstScalar.value) {
                    return .codex
                }
            }

            if screenMode == "alternate", let tail = screenTail {
                if tail.contains("tell Copilot what to do") || tail.contains("GitHub Copilot") {
                    return .copilot
                }
            }
            return nil
        }

        var hasHistoricalTurnOutput: Bool {
            guard let tail = screenTail else { return false }
            let lower = tail.lowercased()
            if lower.contains("worked for ") || lower.contains("thought for ") {
                return true
            }
            for line in tail.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if (trimmed.hasPrefix("● ") || trimmed.hasPrefix("• ")) && !trimmed.lowercased().hasPrefix("● tip:") {
                    return true
                }
            }
            return false
        }

        var inferredStatus: AgentTaskStatus {
            // Check live terminal tail bottom lines first for explicit TUI status bar indicators
            if let tail = screenTail {
                let bottomLines = tail
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .suffix(12)
                    .joined(separator: "\n")
                let lowerBottom = bottomLines.lowercased()

                // 1. Explicit approval / user confirmation prompts in the active bottom area
                if lowerBottom.contains("do you want to run") ||
                   lowerBottom.contains("do you want to proceed") ||
                   lowerBottom.contains("do you want to make this edit") ||
                   lowerBottom.contains("do you want to create") ||
                   lowerBottom.contains("would you like to run") ||
                   lowerBottom.contains("allow this action") ||
                   lowerBottom.contains("waiting for approval") ||
                   lowerBottom.contains("requires approval") ||
                   (lowerBottom.contains("yes, allow") && lowerBottom.contains("no,")) ||
                   (lowerBottom.contains("[y/n]") && lowerBottom.contains("allow")) {
                    return .needsInput
                }

                // 2. Explicit working / thinking indicators in the active bottom area
                if lowerBottom.contains("esc to interrupt") ||
                   lowerBottom.contains("esc esc interrupt") ||
                   lowerBottom.contains("esc to cancel") ||
                   lowerBottom.contains("esc to stop") ||
                   lowerBottom.contains("reconnecting...") ||
                   lowerBottom.contains("thinking...") ||
                   lowerBottom.contains("generating...") ||
                   bottomLines.contains("· Working ·") ||
                   bottomLines.contains("○ Working ·") {
                    return .working
                }

                // 3. Explicit ready / idle indicators in the active bottom area
                if bottomLines.contains("· Ready ·") {
                    if status == .completed || hasHistoricalTurnOutput {
                        return .completed
                    }
                    return .idle
                }
            }

            if status == .needsInput {
                return .needsInput
            }

            if let title = rawTitle,
               let first = title.unicodeScalars.first,
               (0x2800...0x28FF).contains(first.value) {
                return .working
            }

            if let status {
                if status == .idle && hasHistoricalTurnOutput {
                    return .completed
                }
                return status
            }

            if hasHistoricalTurnOutput {
                return .completed
            }
            return .idle
        }

        var cleanTitle: String? {
            guard var text = cleanSessionTitle(rawTitle) else { return nil }
            while let first = text.unicodeScalars.first,
                  (0x2800...0x28FF).contains(first.value) || first == " " || first == "✳" || first == "✢" || first == "✻" || first == "✶" || first == "·" {
                text.removeFirst()
            }
            if let suffixRange = text.range(of: " - GitHub Copilot") {
                text = String(text[..<suffixRange.lowerBound])
            }
            if let suffixRange = text.range(of: " - Claude Code") {
                text = String(text[..<suffixRange.lowerBound])
            }
            if let suffixRange = text.range(of: " - Codex CLI") {
                text = String(text[..<suffixRange.lowerBound])
            }
            return text.isEmpty ? nil : text
        }

        var descriptiveTitle: String? {
            guard let clean = cleanTitle else { return nil }
            let hasSpaceOrBar = clean.contains(" ") || clean.contains("|")
            let hasCJK = clean.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
            return (hasSpaceOrBar || hasCJK || clean.count > 14) ? clean : nil
        }

        var contextPercentUsed: Int? {
            guard let tail = screenTail else { return nil }
            for line in tail.split(separator: "\n").reversed().prefix(15) {
                let text = String(line)
                // Match "% used" (Claude Code, Codex CLI, and Copilot CLI e.g. "(2% used)" or "Context 14% used")
                if let usedRange = text.range(of: "% used") {
                    let before = text[..<usedRange.lowerBound]
                    let digits = before.reversed().prefix(while: { $0.isNumber })
                    if !digits.isEmpty, let val = Int(String(digits.reversed())) {
                        return min(100, max(0, val))
                    }
                }
                if let range = text.range(of: "Context ") {
                    let sub = text[range.upperBound...]
                    // Fallback to "Context XX% left"
                    if let leftRange = sub.range(of: "% left") {
                        let numStr = sub[..<leftRange.lowerBound].trimmingCharacters(in: .whitespaces)
                        if let leftVal = Int(numStr) {
                            return min(100, max(0, 100 - leftVal))
                        }
                    }
                }
            }
            return nil
        }

        var remoteCwdPath: String? {
            if let tail = screenTail {
                for line in tail.split(separator: "\n").reversed().prefix(20) {
                    let parts = line.components(separatedBy: " · ")
                    if parts.count >= 2 {
                        for part in parts {
                            let p = part.trimmingCharacters(in: .whitespacesAndNewlines)
                            if (p.hasPrefix("/") || p.hasPrefix("~/") || p == "~"),
                               !p.contains(" "),
                               p.count <= 140 {
                                return p
                            }
                        }
                    }
                }
            }
            if let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               title.contains("@"),
               let colonIdx = title.lastIndex(of: ":") {
                let pathPart = String(title[title.index(after: colonIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if pathPart == "~" || pathPart.hasPrefix("~/") || pathPart.hasPrefix("/") {
                    return pathPart
                }
            }
            if let tail = screenTail {
                for line in tail.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if (trimmed.hasPrefix("/") || trimmed.hasPrefix("~/")),
                       !trimmed.contains(" "),
                       !trimmed.contains("//"),
                       (2...140).contains(trimmed.count) {
                        return trimmed
                    }
                }
            }
            return nil
        }

        var previewLines: [String] {
            guard let tail = screenTail else { return [] }
            let isWaitingForApproval = (inferredStatus == .needsInput)
            let rawLines = tail
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0).replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }

            var filtered: [String] = []
            for line in rawLines {
                guard !line.isEmpty else { continue }
                // Strip leading replacement characters from partial multibyte slice
                var cleaned = line
                while cleaned.first == "\u{FFFD}" {
                    cleaned.removeFirst()
                }
                // Strip outer box-drawing vertical borders (│ / ┃) commonly used around tool approval dialogs
                while let first = cleaned.first, first == "│" || first == "┃" || first == "╭" || first == "╰" || first == "├" {
                    cleaned.removeFirst()
                }
                while let last = cleaned.last, last == "│" || last == "┃" || last == "╮" || last == "╯" || last == "┤" {
                    cleaned.removeLast()
                }
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleaned.count >= 2 else { continue }

                // Skip pure horizontal rules / box-drawing / block-element borders (U+2500..U+259F)
                let meaningfulScalars = cleaned.unicodeScalars.filter { scalar in
                    if scalar == " " || scalar == "-" || scalar == "_" || scalar == "=" { return false }
                    if (0x2500...0x259F).contains(scalar.value) { return false }
                    return true
                }
                if meaningfulScalars.isEmpty { continue }

                // Skip empty prompt lines
                if cleaned == "❯" || cleaned == "›" || cleaned == ">" || cleaned == "$" || cleaned == "%" {
                    continue
                }
                if cleaned.hasPrefix("› Ask Codex") || cleaned.hasPrefix("❯ Ask ") || cleaned.hasPrefix("tell Copilot what to do") {
                    continue
                }

                // Skip TUI footer / status chrome / helper tip lines
                let lower = cleaned.lowercased()
                if (lower.contains("context ") && (lower.contains("% left") || lower.contains("% used"))) ||
                   (lower.contains("% used)") && lower.contains("plan:")) ||
                   lower.contains("ctrl+e change environment") ||
                   lower.contains("open sidebar") ||
                   lower.contains("/ commands") ||
                   lower.contains("auto mode on") ||
                   lower.contains("shift+tab to cycle") ||
                   lower.contains("? for shortcuts") ||
                   lower.contains("← for agents") ||
                   lower.contains("ctrl+o to expand") ||
                   lower.contains("ctrl+b to run in background") ||
                   lower.contains("tip: use /") ||
                   lower.hasPrefix("● tip:") ||
                   lower.hasPrefix("└ show memory") ||
                   lower.hasPrefix("※ recap:") {
                    continue
                }

                // Collapse excessive internal whitespace (such as right-aligned warning columns)
                if let gapRange = cleaned.range(of: "      ") {
                    let leftPart = String(cleaned[..<gapRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !leftPart.isEmpty {
                        cleaned = leftPart
                    }
                }

                if filtered.last != cleaned {
                    filtered.append(cleaned)
                }
            }

            if isWaitingForApproval {
                // Keep up to 7 lines for approval prompts so both the command/tool and numbered options are visible
                return Array(filtered.suffix(7))
            }
            return Array(filtered.suffix(3))
        }
    }

    nonisolated static func isRexBinaryAvailable() -> Bool {
        resolveRexBinary(home: FileManager.default.homeDirectoryForCurrentUser) != nil
    }

    nonisolated static func isGhosttyAppInstalled() -> Bool {
        ghosttyAppBundleURL() != nil
    }

    private nonisolated static func ghosttyAppBundleURL() -> URL? {
        let candidates = [
            "/Applications/Ghostty.app",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Ghostty.app").path,
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") {
            return appURL
        }
        return nil
    }

    private nonisolated static func runningGhosttyApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            !app.isTerminated && (
                app.bundleIdentifier?.lowercased() == "com.mitchellh.ghostty" ||
                app.localizedName?.lowercased() == "ghostty"
            )
        }
    }

    private nonisolated static func isGhosttyFrontmostOrRecentlyActive() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleID = frontmost.bundleIdentifier?.lowercased() ?? ""
        let name = frontmost.localizedName?.lowercased() ?? ""
        return bundleID == "com.mitchellh.ghostty" || name == "ghostty"
    }

    private struct GhosttyTerminalEntry: Sendable {
        let location: GhosttyPaneLocation
        let pid: Int32
        let ttyName: String?
        let cwdPath: String
        let rawTitle: String?
        let isFocusedInActiveWindow: Bool
        let screenTail: String?
        var isSSH: Bool = false
        var sshPID: Int32? = nil
        var sshTarget: String? = nil

        var screenPrompts: [String] {
            guard let tail = screenTail else { return [] }
            var prompts: [String] = []
            for rawLine in tail.split(separator: "\n") {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                var candidate: String?
                if trimmed.hasPrefix("› ") {
                    candidate = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("❯ ") {
                    candidate = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                if let candidate,
                   !candidate.contains("Ask Codex to do anything"),
                   candidate.range(of: "^\\d+\\.\\s", options: .regularExpression) == nil,
                   !candidate.hasPrefix("Thought for "),
                   let cleaned = cleanSessionTitle(candidate) {
                    prompts.append(cleaned)
                }
            }
            return prompts
        }

        var latestScreenPrompt: String? {
            screenPrompts.last
        }

        var detectedFamily: AgentFamily? {
            if let title = rawTitle {
                let lowerTitle = title.lowercased()
                if lowerTitle.contains("claude code") || lowerTitle.hasPrefix("✳ ") || lowerTitle.contains("claude") {
                    return .claude
                }
                if lowerTitle.contains("codex") {
                    return .codex
                }
                if lowerTitle.hasSuffix("- github copilot") || lowerTitle.contains("github copilot") || lowerTitle.contains("copilot") {
                    return .copilot
                }
                if lowerTitle.contains("antigravity") {
                    return .antigravity
                }
                if let firstScalar = title.unicodeScalars.first,
                   (0x2800...0x28FF).contains(firstScalar.value) {
                    return .codex
                }
            }
            if let tail = screenTail {
                let lowerTail = tail.lowercased()
                if lowerTail.contains("claude code") { return .claude }
                if lowerTail.contains("github copilot") || lowerTail.contains("tell copilot what to do") { return .copilot }
                if lowerTail.contains("codex") { return .codex }
                if lowerTail.contains("antigravity") { return .antigravity }
            }
            return nil
        }

        private var asRexLookalike: RexBlockEntry {
            RexBlockEntry(
                location: RexPaneLocation(sessionID: location.windowID, windowID: location.tabID, blockID: location.terminalID),
                pid: pid,
                processName: isSSH ? "ssh" : "",
                cwdPath: cwdPath,
                rawTitle: rawTitle,
                reportedApp: nil,
                status: nil,
                screenMode: nil,
                screenTail: screenTail,
                screenPrompts: screenPrompts,
                isFocusedInActiveWindow: isFocusedInActiveWindow,
                isSSH: isSSH,
                sshTarget: sshTarget
            )
        }

        var inferredStatus: AgentTaskStatus {
            asRexLookalike.inferredStatus
        }

        var cleanTitle: String? {
            asRexLookalike.cleanTitle
        }

        var descriptiveTitle: String? {
            asRexLookalike.descriptiveTitle
        }

        var contextPercentUsed: Int? {
            asRexLookalike.contextPercentUsed
        }

        var remoteCwdPath: String? {
            asRexLookalike.remoteCwdPath
        }

        var previewLines: [String] {
            asRexLookalike.previewLines
        }
    }

    private nonisolated static func queryGhosttyTerminals(
        sshPIDsByTTY: [String: Int32] = [:],
        ppidMap: [Int32: Int32] = [:]
    ) -> [GhosttyTerminalEntry] {
        // Zero-overhead pre-check: never trigger osascript if Ghostty is not currently running
        guard let ghosttyApp = runningGhosttyApplication() else {
            return []
        }

        let now = ProcessInfo.processInfo.systemUptime
        let appleScript = """
        on cleanField(val)
            try
                if val is missing value then return ""
                set s to val as text
                set AppleScript's text item delimiters to {ASCII character 9, return, linefeed, "|||"}
                set parts to text items of s
                set AppleScript's text item delimiters to " "
                set s to parts as text
                set AppleScript's text item delimiters to ""
                return s
            on error
                set AppleScript's text item delimiters to ""
                return ""
            end try
        end cleanField

        set sep to "|||"
        tell application "Ghostty"
            set outLines to {}
            set frontWinId to ""
            try
                set frontWinId to my cleanField(id of front window)
            end try
            repeat with w in windows
                try
                    set winId to my cleanField(id of w)
                    set selTabId to ""
                    try
                        set selTabId to my cleanField(id of (selected tab of w))
                    end try
                    set winTabs to {}
                    try
                        set winTabs to tabs of w
                    end try
                    if (count of winTabs) > 0 then
                        repeat with t in winTabs
                            try
                                set tabId to my cleanField(id of t)
                                set focTermId to ""
                                try
                                    set focTermId to my cleanField(id of (focused terminal of t))
                                end try
                                repeat with trm in terminals of t
                                    try
                                        set termId to my cleanField(id of trm)
                                        set termPid to 0
                                        try
                                            set termPid to pid of trm
                                        end try
                                        set termTty to my cleanField(tty of trm)
                                        set termCwd to my cleanField(working directory of trm)
                                        set termName to my cleanField(name of trm)
                                        set isFoc to "0"
                                        if (winId is equal to frontWinId) and (tabId is equal to selTabId) and (termId is equal to focTermId) then
                                            set isFoc to "1"
                                        end if
                                        set end of outLines to (winId & sep & tabId & sep & termId & sep & (termPid as text) & sep & termTty & sep & termCwd & sep & termName & sep & isFoc)
                                    end try
                                end repeat
                            end try
                        end repeat
                    else
                        repeat with trm in terminals of w
                            try
                                set termId to my cleanField(id of trm)
                                set termPid to 0
                                try
                                    set termPid to pid of trm
                                end try
                                set termTty to my cleanField(tty of trm)
                                set termCwd to my cleanField(working directory of trm)
                                set termName to my cleanField(name of trm)
                                set isFoc to "0"
                                if winId is equal to frontWinId then set isFoc to "1"
                                set end of outLines to (winId & sep & "" & sep & termId & sep & (termPid as text) & sep & termTty & sep & termCwd & sep & termName & sep & isFoc)
                            end try
                        end repeat
                    end if
                end try
            end repeat
            set AppleScript's text item delimiters to linefeed
            set resText to outLines as text
            set AppleScript's text item delimiters to ""
            return resText
        end tell
        """

        let execResult = runProcessWithTimeout(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", appleScript],
            captureStdout: true,
            timeoutSeconds: 1.5
        )
        guard execResult.succeeded,
              let outputText = String(data: execResult.outputData, encoding: .utf8) else {
            return DiscoveryCache.shared.cachedGhosttyTerminalsFallback(now: now, maxAge: 6.0) ?? []
        }

        let axFocusedTail = queryGhosttyAccessibilityScreenTail(appPID: ghosttyApp.processIdentifier)
        let isGhosttyFront = isGhosttyFrontmostOrRecentlyActive()
        var entries: [GhosttyTerminalEntry] = []

        for rawLine in outputText.split(whereSeparator: \.isNewline) {
            let fields = String(rawLine).components(separatedBy: "|||")
            guard fields.count >= 8 else { continue }
            let winID = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let tabIDRaw = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let termID = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !termID.isEmpty else { continue }
            let pidVal = Int32(fields[3].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let ttyPathRaw = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
            let cwdRaw = fields[5].trimmingCharacters(in: .whitespacesAndNewlines)
            let titleRaw = fields[6].trimmingCharacters(in: .whitespacesAndNewlines)
            let isFocInGhostty = fields[7].trimmingCharacters(in: .whitespacesAndNewlines) == "1"

            let ttyPath: String? = ttyPathRaw.isEmpty ? nil : ttyPathRaw
            let ttyName: String? = {
                guard let ttyPath, !ttyPath.isEmpty else { return nil }
                let last = URL(fileURLWithPath: ttyPath).lastPathComponent
                return last.isEmpty ? nil : last
            }()

            // Detect SSH process associated with this Ghostty terminal (by TTY or child PID)
            var matchedSSHPID: Int32? = nil
            if let ttyName, let sshPID = sshPIDsByTTY[ttyName] {
                matchedSSHPID = sshPID
            } else if pidVal > 1 {
                for (_, sshPID) in sshPIDsByTTY {
                    var cur = sshPID
                    for _ in 0..<10 {
                        guard cur > 1 else { break }
                        if cur == pidVal {
                            matchedSSHPID = sshPID
                            break
                        }
                        let next = ppidMap[cur] ?? parentPID(of: cur)
                        guard next > 1, next != cur else { break }
                        cur = next
                    }
                    if matchedSSHPID != nil { break }
                }
            }

            let sshTarget = matchedSSHPID.flatMap { extractSSHTarget(pid: $0) }
            let location = GhosttyPaneLocation(
                windowID: winID,
                tabID: tabIDRaw.isEmpty ? nil : tabIDRaw,
                terminalID: termID,
                ttyPath: ttyPath
            )
            entries.append(
                GhosttyTerminalEntry(
                    location: location,
                    pid: pidVal,
                    ttyName: ttyName,
                    cwdPath: cwdRaw,
                    rawTitle: titleRaw.isEmpty ? nil : titleRaw,
                    isFocusedInActiveWindow: isFocInGhostty && isGhosttyFront,
                    screenTail: isFocInGhostty ? axFocusedTail : nil,
                    isSSH: matchedSSHPID != nil,
                    sshPID: matchedSSHPID,
                    sshTarget: sshTarget
                )
            )
        }

        DiscoveryCache.shared.setCachedGhosttyTerminals(entries, now: ProcessInfo.processInfo.systemUptime)
        return entries
    }

    private nonisolated static func queryGhosttyAccessibilityScreenTail(appPID: pid_t) -> String? {
        guard appPID > 1, AXIsProcessTrusted() else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.045
        let appElem = AXUIElementCreateApplication(appPID)
        AXUIElementSetMessagingTimeout(appElem, 0.04)

        func extractTextValue(from elem: AXUIElement) -> String? {
            var valRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &valRef) == .success,
               let str = valRef as? String {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 4 {
                    return String(trimmed.suffix(1600))
                }
            }
            return nil
        }

        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElem, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focusedRef,
           CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
            let focusedElem = unsafeDowncast(focusedRef, to: AXUIElement.self)
            if let text = extractTextValue(from: focusedElem) {
                return text
            }
        }

        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef,
              CFGetTypeID(windowRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let rootWin = unsafeDowncast(windowRef, to: AXUIElement.self)
        var queue: [AXUIElement] = [rootWin]
        var visited = 0

        while !queue.isEmpty && visited < 32 && ProcessInfo.processInfo.systemUptime < deadline {
            let current = queue.removeFirst()
            visited += 1
            if let text = extractTextValue(from: current) {
                return text
            }
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(8))
            }
        }
        return nil
    }

    private nonisolated static func matchGhosttyEntry(
        for proc: ProcessEntry,
        ppidMap: [Int32: Int32],
        entries: [GhosttyTerminalEntry]
    ) -> GhosttyTerminalEntry? {
        guard !entries.isEmpty else { return nil }

        // 1. Exact PID match
        if let exact = entries.first(where: { $0.pid > 0 && $0.pid == proc.pid }) {
            return exact
        }

        // 2. TTY match
        if let procTTY = proc.tty, !procTTY.isEmpty {
            if let byTTY = entries.first(where: { $0.ttyName == procTTY }) {
                return byTTY
            }
        }

        // 3. Parent-child process chain match (up to 10 levels)
        var currentPID = proc.pid
        for _ in 0..<10 {
            let nextPPID = ppidMap[currentPID] ?? parentPID(of: currentPID)
            guard nextPPID > 1, nextPPID != currentPID else { break }
            if let ancestorMatch = entries.first(where: { $0.pid > 1 && $0.pid == nextPPID }) {
                return ancestorMatch
            }
            currentPID = nextPPID
        }

        return nil
    }

    private nonisolated static func isDescendantOfGhostty(
        pid startPID: Int32,
        ghosttyAppPID: Int32?,
        ppidMap: [Int32: Int32]
    ) -> Bool {
        guard let ghosttyAppPID, ghosttyAppPID > 1 else { return false }
        var cur = startPID
        for _ in 0..<12 {
            guard cur > 1 else { break }
            if cur == ghosttyAppPID {
                return true
            }
            let next = ppidMap[cur] ?? parentPID(of: cur)
            if next <= 1 || next == cur { break }
            cur = next
        }
        return false
    }

    private nonisolated static func resolveRexBinary(home: URL) -> URL? {
        let candidates = [
            home.appendingPathComponent("Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex").path,
            "/Applications/Rex Beta.app/Contents/Resources/rex",
            "/Applications/Rex.app/Contents/Resources/rex",
            "/opt/homebrew/bin/rex",
            "/usr/local/bin/rex",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private nonisolated static func queryRexBlocks(home: URL) -> [Int32: RexBlockEntry] {
        let now = ProcessInfo.processInfo.systemUptime
        guard let rexBin = resolveRexBinary(home: home) else {
            return DiscoveryCache.shared.cachedRexBlocksFallback(now: now, maxAge: 6.0) ?? [:]
        }
        let luaScript = """
        local ok_s, s_res = pcall(rex.call, "session.list")
        local sessions = (ok_s and s_res and s_res.sessions) or {}
        local out = {}
        for _, s in ipairs(sessions) do
          local sid = s.session_id
          if sid then
            local ok_att = pcall(rex.call, "session.attach", {session_id = sid})
            if ok_att then
              local ok_v, view = pcall(rex.call, "session.view", {session_id = sid})
              if not ok_v then view = nil end
              local active_wid = view and view.active_window_id
              local focused_bid = nil
              if active_wid and view and view.windows then
                for _, w in ipairs(view.windows) do
                  if w.window_id == active_wid then
                    focused_bid = w.focused_block_id
                    break
                  end
                end
              end
              local ok_b, b_res = pcall(rex.call, "session.list_blocks", {session_id = sid})
              local blocks = (ok_b and b_res and b_res.blocks) or {}
              for _, b in ipairs(blocks) do
                if b.creator_name == "com.superlogical.terminal" and b.block_id then
                  local ok_p, p = pcall(rex.call, "block.method", {session_id = sid, block_id = b.block_id, method = "process"})
                  if not ok_p then p = nil end
                  local ok_t, t = pcall(rex.call, "block.method", {session_id = sid, block_id = b.block_id, method = "title"})
                  if not ok_t then t = nil end
                  local ok_st, st = pcall(rex.call, "block.method", {session_id = sid, block_id = b.block_id, method = "program_status"})
                  if not ok_st then st = nil end
                  local ok_m, m = pcall(rex.call, "block.method", {session_id = sid, block_id = b.block_id, method = "modes"})
                  if not ok_m then m = nil end
                  local state = nil
                  local app = nil
                  if st and st.records and st.records[1] then
                    state = st.records[1].state
                    app = st.records[1].effective_app or st.records[1].app
                  end
                  local screen = m and m.screen
                  local fg_name = string.lower((p and p.foreground and p.foreground.name) or "")
                  local fg_path = string.lower((p and p.foreground and p.foreground.path) or "")
                  local is_ssh = (fg_name == "ssh" or string.sub(fg_path, -4) == "/ssh")
                  if not is_ssh and p and p.ancestors then
                    for _, anc in ipairs(p.ancestors) do
                      local aname = string.lower(anc.name or "")
                      local apath = string.lower(anc.path or "")
                      if aname == "ssh" or string.sub(apath, -4) == "/ssh" then
                        is_ssh = true
                        break
                      end
                    end
                  end
                  local app_lower = string.lower(app or "")
                  local raw_title = (t and t.title) or ""
                  local title_lower = string.lower(raw_title)
                  local is_candidate = (app_lower ~= "")
                    or (fg_name == "codex" or fg_name == "claude" or fg_name == "copilot" or fg_name == "agy" or fg_name == "antigravity" or fg_name == "ssh" or fg_name == "node")
                    or (screen == "alternate")
                    or (string.find(title_lower, "claude", 1, true) ~= nil)
                    or (string.find(title_lower, "copilot", 1, true) ~= nil)
                    or (string.find(title_lower, "codex", 1, true) ~= nil)
                    or (string.find(title_lower, "antigravity", 1, true) ~= nil)
                  local tail = nil
                  local prompts = {}
                  if is_candidate then
                    local ok_f, fmt = pcall(rex.call, "block.method", {session_id = sid, block_id = b.block_id, method = "format", args = {format = "text", trim = true}})
                    if ok_f and fmt and fmt.content then
                      tail = string.sub(fmt.content, -1600)
                      for line in string.gmatch(fmt.content, "[^\\r\\n]+") do
                        local p1 = string.match(line, "^%s*›%s+(.+)$")
                        local p2 = string.match(line, "^%s*❯%s+(.+)$")
                        local p = p1 or p2
                        if p and not string.find(p, "Ask Codex to do anything") and not string.find(p, "^%d+%.%s") and not string.find(p, "^Thought for ") then
                          table.insert(prompts, p)
                        end
                      end
                    end
                  end
                  table.insert(out, {
                    session_id = sid,
                    window_id = b.window_id,
                    block_id = b.block_id,
                    is_focused = (b.window_id == active_wid and b.block_id == focused_bid),
                    pid = p and p.foreground and p.foreground.pid,
                    name = p and p.foreground and p.foreground.name,
                    cwd = p and p.foreground and p.foreground.cwd,
                    title = t and t.title,
                    state = state,
                    app = app,
                    screen = screen,
                    tail = tail,
                    prompts = prompts,
                    is_ssh = is_ssh,
                  })
                end
              end
            end
          end
        end
        return out
        """

        let execResult = runProcessWithTimeout(
            executableURL: rexBin,
            arguments: ["--autostart=false", "--timeout", "1s", "do", "-e", luaScript, "--json"],
            environment: rexCleanEnvironment(),
            captureStdout: true,
            timeoutSeconds: 1.8
        )
        guard execResult.succeeded,
              let rows = try? JSONSerialization.jsonObject(with: execResult.outputData) as? [[String: Any]] else {
            return DiscoveryCache.shared.cachedRexBlocksFallback(now: now, maxAge: 6.0) ?? [:]
        }

        var map: [Int32: RexBlockEntry] = [:]
        for row in rows {
            guard let sid = row["session_id"] as? String,
                  let bid = row["block_id"] as? String,
                  let pidNum = row["pid"] as? Int else { continue }
            let pid = Int32(pidNum)
            let procName = (row["name"] as? String) ?? ""
            let wid = row["window_id"] as? String
            let cwd = (row["cwd"] as? String) ?? ""
            let title = row["title"] as? String
            let app = row["app"] as? String
            let stateStr = row["state"] as? String
            let screen = row["screen"] as? String
            let tail = row["tail"] as? String
            let rawPrompts = (row["prompts"] as? [String]) ?? []
            let cleanedPrompts = rawPrompts.compactMap { cleanSessionTitle($0) }
            let isFocused = (row["is_focused"] as? Bool) ?? false
            let isSSH = (row["is_ssh"] as? Bool) ?? (procName.lowercased() == "ssh")
            let sshTarget: String? = isSSH ? extractSSHTarget(pid: pid) : nil
            let status: AgentTaskStatus? = {
                switch stateStr {
                case "blocked": return .needsInput
                case "working": return .working
                case "done": return .completed
                case "idle": return .idle
                default: return nil
                }
            }()
            map[pid] = RexBlockEntry(
                location: RexPaneLocation(sessionID: sid, windowID: wid, blockID: bid),
                pid: pid,
                processName: procName,
                cwdPath: cwd,
                rawTitle: title,
                reportedApp: app,
                status: status,
                screenMode: screen,
                screenTail: tail,
                screenPrompts: cleanedPrompts,
                isFocusedInActiveWindow: isFocused && isRexFrontmostOrRecentlyActive(),
                isSSH: isSSH,
                sshTarget: sshTarget
            )
        }
        DiscoveryCache.shared.setLastGoodRexBlocks(map, now: ProcessInfo.processInfo.systemUptime)
        return map
    }

    private nonisolated static func extractSSHTarget(pid: Int32) -> String? {
        guard let argsLine = processCommandLineArgs(pid: pid) else { return nil }
        let tokens = argsLine.split(separator: " ").map(String.init)
        let flagsWithValue: Set<String> = [
            "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L",
            "-l", "-m", "-O", "-o", "-p", "-Q", "-R", "-S", "-W", "-w",
        ]
        var skipNext = false
        var loginUser: String?
        for token in tokens {
            if skipNext {
                skipNext = false
                continue
            }
            if token == "ssh" || token.hasSuffix("/ssh") {
                continue
            }
            if token == "-l", let idx = tokens.firstIndex(of: token), idx + 1 < tokens.count {
                loginUser = tokens[idx + 1]
                skipNext = true
                continue
            }
            if flagsWithValue.contains(token) {
                skipNext = true
                continue
            }
            if token.hasPrefix("-") {
                continue
            }
            if let user = loginUser, !token.contains("@") {
                return "\(user)@\(token)"
            }
            return token
        }
        return nil
    }

    private nonisolated static func isRexFrontmostOrRecentlyActive() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleID = frontmost.bundleIdentifier?.lowercased() ?? ""
        let name = frontmost.localizedName?.lowercased() ?? ""
        return bundleID.contains("com.superlogical.rex") || name == "rex beta" || name == "rex"
    }

    private nonisolated static func ensureRexRemoteControlEnabled() {
        guard let suite = UserDefaults(suiteName: "com.superlogical.rex") else { return }
        if !suite.bool(forKey: "rex.client.remoteControl") {
            suite.set(true, forKey: "rex.client.remoteControl")
            suite.synchronize()
        }
    }

    private nonisolated static func performJump(for item: AgentActivityItem) -> Bool {
        if item.ghosttyPane != nil || item.terminalHost == .ghostty {
            return performGhosttyJump(for: item)
        }
        return performRexJump(for: item)
    }

    private nonisolated static let ghosttyResolveTerminalAppleScriptPreamble = """
        set targetWinId to item 1 of argv
        set targetTabId to item 2 of argv
        set targetTermId to item 3 of argv
        set targetTty to item 4 of argv
        set targetPid to (item 5 of argv) as integer

        tell application "Ghostty"
            set matchedWin to missing value
            set matchedTab to missing value
            set matchedTerm to missing value

            -- Tier 1: match by windowID / tabID / terminalID
            if targetTermId is not "" then
                repeat with w in windows
                    try
                        if targetWinId is "" or (id of w as text) is equal to targetWinId then
                            repeat with t in tabs of w
                                try
                                    if targetTabId is "" or (id of t as text) is equal to targetTabId then
                                        repeat with trm in terminals of t
                                            try
                                                if (id of trm as text) is equal to targetTermId then
                                                    set matchedWin to w
                                                    set matchedTab to t
                                                    set matchedTerm to trm
                                                    exit repeat
                                                end if
                                            end try
                                        end repeat
                                    end if
                                end try
                                if matchedTerm is not missing value then exit repeat
                            end repeat
                        end if
                    end try
                    if matchedTerm is not missing value then exit repeat
                end repeat

                if matchedTerm is missing value then
                    repeat with w in windows
                        try
                            repeat with t in tabs of w
                                try
                                    repeat with trm in terminals of t
                                        try
                                            if (id of trm as text) is equal to targetTermId then
                                                set matchedWin to w
                                                set matchedTab to t
                                                set matchedTerm to trm
                                                exit repeat
                                            end if
                                        end try
                                    end repeat
                                end try
                                if matchedTerm is not missing value then exit repeat
                            end repeat
                            if matchedTerm is missing value then
                                repeat with trm in terminals of w
                                    try
                                        if (id of trm as text) is equal to targetTermId then
                                            set matchedWin to w
                                            set matchedTerm to trm
                                            exit repeat
                                        end if
                                    end try
                                end repeat
                            end if
                        end try
                        if matchedTerm is not missing value then exit repeat
                    end repeat
                end if
            end if

            -- Tier 2: fallback match by TTY device path or foreground/shell PID
            if matchedTerm is missing value then
                repeat with w in windows
                    try
                        repeat with t in tabs of w
                            try
                                repeat with trm in terminals of t
                                    try
                                        set trmTty to ""
                                        try
                                            set trmTty to (tty of trm as text)
                                        end try
                                        set trmPid to -1
                                        try
                                            set trmPid to (pid of trm as integer)
                                        end try
                                        if (targetTty is not "" and trmTty is equal to targetTty) or (targetPid > 0 and trmPid is equal to targetPid) then
                                            set matchedWin to w
                                            set matchedTab to t
                                            set matchedTerm to trm
                                            exit repeat
                                        end if
                                    end try
                                end repeat
                            end try
                            if matchedTerm is not missing value then exit repeat
                        end repeat
                        if matchedTerm is missing value then
                            repeat with trm in terminals of w
                                try
                                    set trmTty to ""
                                    try
                                        set trmTty to (tty of trm as text)
                                    end try
                                    set trmPid to -1
                                    try
                                        set trmPid to (pid of trm as integer)
                                    end try
                                    if (targetTty is not "" and trmTty is equal to targetTty) or (targetPid > 0 and trmPid is equal to targetPid) then
                                        set matchedWin to w
                                        set matchedTerm to trm
                                        exit repeat
                                    end if
                                end try
                            end repeat
                        end if
                    end try
                    if matchedTerm is not missing value then exit repeat
                end repeat
            end if
    """

    private nonisolated static func ghosttyLookupArgs(for item: AgentActivityItem) -> [String] {
        let winID = item.ghosttyPane?.windowID ?? ""
        let tabID = item.ghosttyPane?.tabID ?? ""
        let termID = item.ghosttyPane?.terminalID ?? ""
        let ttyPath: String = {
            if let path = item.ghosttyPane?.ttyPath, !path.isEmpty {
                return path.hasPrefix("/dev/") ? path : "/dev/\(path)"
            }
            if let tty = item.tty, !tty.isEmpty {
                return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
            }
            return ""
        }()
        let pidStr = "\(item.pid ?? -1)"
        return [winID, tabID, termID, ttyPath, pidStr]
    }

    private nonisolated static func resolvedLocalTTYName(for item: AgentActivityItem) -> String? {
        if let tty = item.tty?.trimmingCharacters(in: .whitespacesAndNewlines), !tty.isEmpty {
            return URL(fileURLWithPath: tty).lastPathComponent
        }
        if let ttyPath = item.ghosttyPane?.ttyPath?.trimmingCharacters(in: .whitespacesAndNewlines), !ttyPath.isEmpty {
            let last = URL(fileURLWithPath: ttyPath).lastPathComponent
            return last.isEmpty ? nil : last
        }
        return nil
    }

    private nonisolated static func performGhosttyJump(for item: AgentActivityItem) -> Bool {
        dismissMenuBarPanelWindows()
        var scriptMatched = false

        if runningGhosttyApplication() != nil {
            let script = """
            on run argv
            \(ghosttyResolveTerminalAppleScriptPreamble)
                    if matchedWin is not missing value then
                        try
                            activate window matchedWin
                        end try
                    end if
                    if matchedTab is not missing value then
                        try
                            select tab matchedTab
                        end try
                    end if
                    if matchedTerm is not missing value then
                        try
                            focus matchedTerm
                        end try
                    end if
                    activate
                    if matchedTerm is not missing value then
                        return "OK"
                    end if
                end tell
                return "MISS"
            end run
            """
            let execResult = runProcessWithTimeout(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script] + ghosttyLookupArgs(for: item),
                captureStdout: true,
                timeoutSeconds: 2.0
            )
            if execResult.succeeded,
               let out = String(data: execResult.outputData, encoding: .utf8),
               out.contains("OK") {
                scriptMatched = true
            }
        }

        // Tier 3 fallback: always activate Ghostty application via NSRunningApplication
        let activated = activateGhosttyApp()
        return scriptMatched || activated
    }

    private nonisolated static func performRexJump(for item: AgentActivityItem) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        dismissMenuBarPanelWindows()
        guard let rexBin = resolveRexBinary(home: home) else {
            return activateRexApp()
        }
        ensureRexRemoteControlEnabled()

        var targetPane = item.rexPane
        if targetPane == nil, let pid = item.pid {
            let liveRexMap = queryRexBlocks(home: home)
            if let found = liveRexMap[pid] {
                targetPane = found.location
            }
        }

        let script: String
        if let rexPane = targetPane {
            let widExpr = rexPane.windowID.map(luaQuote) ?? "nil"
            script = """
            local sid = \(luaQuote(rexPane.sessionID))
            local wid = \(widExpr)
            local bid = \(luaQuote(rexPane.blockID))
            pcall(rex.call, "session.attach", {session_id = sid})
            local ok_v, view = pcall(rex.call, "session.view", {session_id = sid})
            if not ok_v then view = nil end
            local win_idx = nil
            if wid and view and view.windows then
              for idx, w in ipairs(view.windows) do
                if w.window_id == wid then win_idx = idx; break end
              end
            end
            if wid then
              pcall(rex.call, "session.focus_window", {session_id = sid, window_id = wid})
            end
            pcall(rex.call, "session.focus_block", {session_id = sid, block_id = bid})
            local ok_c, c_res = pcall(rex.call, "client.list")
            local clients = (ok_c and c_res and c_res.clients) or {}
            for _, c in ipairs(clients) do
              if c.info and c.info.kind == "app" and c.connection_state == "connected" then
                pcall(rex.call, "client.perform", {
                  client_id = c.client_id,
                  action = "session.select",
                  args = {session_id = sid, window_id = wid},
                  timeout_ms = 1500
                })
                if win_idx then
                  pcall(rex.call, "client.perform", {
                    client_id = c.client_id,
                    action = "client.tab.goto",
                    args = {index = win_idx},
                    timeout_ms = 1500
                  })
                end
              end
            end
            """
        } else {
            let targetPID = item.pid ?? -1
            let targetCwd = luaQuote(item.cwdPath)
            script = """
            local ok_s, s_res = pcall(rex.call, "session.list")
            local sessions = (ok_s and s_res and s_res.sessions) or {}
            local target_pid = \(targetPID)
            local target_cwd = \(targetCwd)
            local matched_sid, matched_wid, matched_bid = nil, nil, nil
            for _, s in ipairs(sessions) do
              local sid = s.session_id
              if sid then
                pcall(rex.call, "session.attach", {session_id = sid})
                local ok_b, b_res = pcall(rex.call, "session.list_blocks", {session_id = sid})
                local blocks = (ok_b and b_res and b_res.blocks) or {}
                for _, b in ipairs(blocks) do
                  if b.creator_name == "com.superlogical.terminal" and b.block_id then
                    local ok_p, p = pcall(rex.call, "block.method", {session_id = sid, block_id = b.block_id, method = "process"})
                    local fg = ok_p and p and p.foreground
                    if fg then
                      if (target_pid > 0 and fg.pid == target_pid) or (target_cwd ~= "" and fg.cwd == target_cwd) then
                        matched_sid = sid
                        matched_wid = b.window_id
                        matched_bid = b.block_id
                        if target_pid > 0 and fg.pid == target_pid then break end
                      end
                    end
                  end
                end
              end
            end
            if matched_sid and matched_bid then
              local ok_v, view = pcall(rex.call, "session.view", {session_id = matched_sid})
              if not ok_v then view = nil end
              local win_idx = nil
              if matched_wid and view and view.windows then
                for idx, w in ipairs(view.windows) do
                  if w.window_id == matched_wid then win_idx = idx; break end
                end
              end
              if matched_wid then
                pcall(rex.call, "session.focus_window", {session_id = matched_sid, window_id = matched_wid})
              end
              pcall(rex.call, "session.focus_block", {session_id = matched_sid, block_id = matched_bid})
              local ok_c, c_res = pcall(rex.call, "client.list")
              local clients = (ok_c and c_res and c_res.clients) or {}
              for _, c in ipairs(clients) do
                if c.info and c.info.kind == "app" and c.connection_state == "connected" then
                  pcall(rex.call, "client.perform", {
                    client_id = c.client_id,
                    action = "session.select",
                    args = {session_id = matched_sid, window_id = matched_wid},
                    timeout_ms = 1500
                  })
                  if win_idx then
                    pcall(rex.call, "client.perform", {
                      client_id = c.client_id,
                      action = "client.tab.goto",
                      args = {index = win_idx},
                      timeout_ms = 1500
                    })
                  end
                end
              end
            end
            """
        }

        _ = runProcessWithTimeout(
            executableURL: rexBin,
            arguments: ["--autostart=false", "--timeout", "2s", "do", "-e", script],
            environment: rexCleanEnvironment(),
            captureStdout: false,
            timeoutSeconds: 2.8
        )

        return activateRexApp()
    }

    private nonisolated static func performCloseSession(for item: AgentActivityItem) -> Bool {
        if item.ghosttyPane != nil || item.terminalHost == .ghostty {
            return performGhosttyCloseSession(for: item)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        var closedInRex = false

        if let rexBin = resolveRexBinary(home: home) {
            func tryClosePane(_ rexPane: RexPaneLocation) -> Bool {
                let script = """
                local sid = \(luaQuote(rexPane.sessionID))
                local bid = \(luaQuote(rexPane.blockID))
                local ok_att = pcall(rex.call, "session.attach", {session_id = sid})
                if not ok_att then os.exit(1) end
                local ok_cl = pcall(rex.call, "block.close", {session_id = sid, block_id = bid})
                if not ok_cl then os.exit(1) end
                """
                let execResult = runProcessWithTimeout(
                    executableURL: rexBin,
                    arguments: ["--autostart=false", "--timeout", "2s", "do", "-e", script],
                    environment: rexCleanEnvironment(),
                    captureStdout: false,
                    timeoutSeconds: 2.8
                )
                return execResult.succeeded
            }

            if let initialPane = item.rexPane {
                closedInRex = tryClosePane(initialPane)
            }
            if !closedInRex, let pid = item.pid {
                let liveRexMap = queryRexBlocks(home: home)
                if let found = liveRexMap[pid], found.location != item.rexPane {
                    closedInRex = tryClosePane(found.location)
                }
            }
        }

        var killedProcess = false
        if let pid = item.pid, pid > 1 {
            killedProcess = (Darwin.kill(pid, SIGTERM) == 0)
        }

        return closedInRex || killedProcess
    }

    private nonisolated static func performGhosttyCloseSession(for item: AgentActivityItem) -> Bool {
        var closedInGhostty = false
        if runningGhosttyApplication() != nil {
            let script = """
            on run argv
            \(ghosttyResolveTerminalAppleScriptPreamble)
                    if matchedTerm is not missing value then
                        close matchedTerm
                        return "OK"
                    end if
                end tell
                return "MISS"
            end run
            """
            let execResult = runProcessWithTimeout(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script] + ghosttyLookupArgs(for: item),
                captureStdout: true,
                timeoutSeconds: 2.0
            )
            if execResult.succeeded,
               let out = String(data: execResult.outputData, encoding: .utf8),
               out.contains("OK") {
                closedInGhostty = true
            }
        }

        var killedProcess = false
        if let pid = item.pid, pid > 1 {
            killedProcess = (Darwin.kill(pid, SIGTERM) == 0)
        }

        return closedInGhostty || killedProcess
    }

    private nonisolated static func performApprovalWrite(for item: AgentActivityItem, choice: AgentApprovalChoice) -> Bool {
        if item.ghosttyPane != nil || item.terminalHost == .ghostty {
            return performGhosttyApprovalWrite(for: item, choice: choice)
        }
        return performRexApprovalWrite(for: item, choice: choice)
    }

    private nonisolated static func performGhosttyApprovalWrite(for item: AgentActivityItem, choice: AgentApprovalChoice) -> Bool {
        let combinedPreview = item.terminalPreviewLines.joined(separator: "\n").lowercased()
        let isPlainYN = combinedPreview.contains("[y/n]") || combinedPreview.contains("(y/n)")
        let hasNumberedDenyOption3 = combinedPreview.contains("3. no") || combinedPreview.contains("3. cancel") || combinedPreview.contains("3. reject")
        let hasNumberedDenyOption2 = combinedPreview.contains("2. no") || combinedPreview.contains("2. cancel") || combinedPreview.contains("2. reject")

        let textOption: String? = {
            switch choice {
            case .approvePrimary:
                return isPlainYN ? "y" : "1"
            case .approveSecondary:
                return isPlainYN ? "y" : "2"
            case .deny:
                if isPlainYN {
                    return "n"
                } else if hasNumberedDenyOption3 {
                    return "3"
                } else if hasNumberedDenyOption2 {
                    return "2"
                } else {
                    return nil
                }
            }
        }()

        // Tier 1: Ghostty AppleScript `input text` + `send key "enter"` or `send key "escape"`
        if runningGhosttyApplication() != nil {
            let script: String
            let extraArgs: [String]
            if let textOption {
                script = """
                on run argv
                    set replyVal to item 6 of argv
                \(ghosttyResolveTerminalAppleScriptPreamble)
                        if matchedTerm is not missing value then
                            input text replyVal to matchedTerm
                            send key "enter" to matchedTerm
                            return "OK"
                        end if
                    end tell
                    return "MISS"
                end run
                """
                extraArgs = [textOption]
            } else {
                script = """
                on run argv
                \(ghosttyResolveTerminalAppleScriptPreamble)
                        if matchedTerm is not missing value then
                            send key "escape" to matchedTerm
                            return "OK"
                        end if
                    end tell
                    return "MISS"
                end run
                """
                extraArgs = []
            }

            let execResult = runProcessWithTimeout(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script] + ghosttyLookupArgs(for: item) + extraArgs,
                captureStdout: true,
                timeoutSeconds: 2.0
            )
            if execResult.succeeded,
               let out = String(data: execResult.outputData, encoding: .utf8),
               out.contains("OK") {
                return true
            }
        }

        // Tier 2 fallback: direct local TTY write
        if item.sshTarget == nil, let tty = resolvedLocalTTYName(for: item) {
            let rawPayload = textOption.map { "\($0)\r" } ?? "\u{1B}"
            return writeToLocalTTY(ttyName: tty, data: Data(rawPayload.utf8))
        }
        return false
    }

    private nonisolated static func performRexApprovalWrite(for item: AgentActivityItem, choice: AgentApprovalChoice) -> Bool {
        let combinedPreview = item.terminalPreviewLines.joined(separator: "\n").lowercased()
        let isPlainYN = combinedPreview.contains("[y/n]") || combinedPreview.contains("(y/n)")
        let hasNumberedDenyOption3 = combinedPreview.contains("3. no") || combinedPreview.contains("3. cancel") || combinedPreview.contains("3. reject")
        let hasNumberedDenyOption2 = combinedPreview.contains("2. no") || combinedPreview.contains("2. cancel") || combinedPreview.contains("2. reject")

        let payload: String = {
            switch choice {
            case .approvePrimary:
                return isPlainYN ? "y\r" : "1\r"
            case .approveSecondary:
                return isPlainYN ? "y\r" : "2\r"
            case .deny:
                if isPlainYN {
                    return "n\r"
                } else if hasNumberedDenyOption3 {
                    return "3\r"
                } else if hasNumberedDenyOption2 {
                    return "2\r"
                } else {
                    return "\u{1B}"
                }
            }
        }()

        let home = FileManager.default.homeDirectoryForCurrentUser
        if let rexBin = resolveRexBinary(home: home) {
            func tryWriteToPane(_ rexPane: RexPaneLocation) -> Bool {
                let script = """
                local sid = \(luaQuote(rexPane.sessionID))
                local bid = \(luaQuote(rexPane.blockID))
                local ok_att = pcall(rex.call, "session.attach", {session_id = sid})
                if not ok_att then os.exit(1) end
                local ok_w = pcall(rex.call, "block.method", {
                  session_id = sid,
                  block_id = bid,
                  method = "write",
                  args = { data = \(luaQuote(payload)) }
                })
                if not ok_w then os.exit(1) end
                """
                let execResult = runProcessWithTimeout(
                    executableURL: rexBin,
                    arguments: ["--autostart=false", "--timeout", "2s", "do", "-e", script],
                    environment: rexCleanEnvironment(),
                    captureStdout: false,
                    timeoutSeconds: 2.8
                )
                return execResult.succeeded
            }

            if let initialPane = item.rexPane, tryWriteToPane(initialPane) {
                return true
            }
            if let pid = item.pid {
                let liveRexMap = queryRexBlocks(home: home)
                if let found = liveRexMap[pid], found.location != item.rexPane, tryWriteToPane(found.location) {
                    return true
                }
            }
        }

        if item.sshTarget == nil, let tty = item.tty, !tty.isEmpty {
            return writeToLocalTTY(ttyName: tty, data: Data(payload.utf8))
        }
        return false
    }

    private nonisolated static func performPromptWrite(for item: AgentActivityItem, text: String) -> Bool {
        if item.ghosttyPane != nil || item.terminalHost == .ghostty {
            return performGhosttyPromptWrite(for: item, text: text)
        }
        return performRexPromptWrite(for: item, text: text)
    }

    private nonisolated static func performGhosttyPromptWrite(for item: AgentActivityItem, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Tier 1: Ghostty AppleScript `input text` + `send key "enter"`
        if runningGhosttyApplication() != nil {
            let script = """
            on run argv
                set promptText to item 6 of argv
            \(ghosttyResolveTerminalAppleScriptPreamble)
                    if matchedTerm is not missing value then
                        input text promptText to matchedTerm
                        delay 0.05
                        send key "enter" to matchedTerm
                        return "OK"
                    end if
                end tell
                return "MISS"
            end run
            """
            let execResult = runProcessWithTimeout(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script] + ghosttyLookupArgs(for: item) + [trimmed],
                captureStdout: true,
                timeoutSeconds: 2.0
            )
            if execResult.succeeded,
               let out = String(data: execResult.outputData, encoding: .utf8),
               out.contains("OK") {
                return true
            }
        }

        // Tier 2 fallback: direct local TTY write
        if item.sshTarget == nil, let tty = resolvedLocalTTYName(for: item) {
            return writeToLocalTTY(ttyName: tty, data: Data((trimmed + "\r").utf8))
        }
        return false
    }

    private nonisolated static func performRexPromptWrite(for item: AgentActivityItem, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser

        if let rexBin = resolveRexBinary(home: home) {
            func tryWritePromptToPane(_ rexPane: RexPaneLocation) -> Bool {
                // Send text first, then carriage return \r after a brief yield so TUI agents (Claude Code / Codex) submit cleanly
                let script = """
                local sid = \(luaQuote(rexPane.sessionID))
                local bid = \(luaQuote(rexPane.blockID))
                local ok_att = pcall(rex.call, "session.attach", {session_id = sid})
                if not ok_att then os.exit(1) end
                local ok_w1 = pcall(rex.call, "block.method", {
                  session_id = sid,
                  block_id = bid,
                  method = "write",
                  args = { data = \(luaQuote(trimmed)) }
                })
                if not ok_w1 then os.exit(1) end
                pcall(rex.sleep, 0.06)
                local ok_w2 = pcall(rex.call, "block.method", {
                  session_id = sid,
                  block_id = bid,
                  method = "write",
                  args = { data = "\\r" }
                })
                if not ok_w2 then os.exit(1) end
                """
                let execResult = runProcessWithTimeout(
                    executableURL: rexBin,
                    arguments: ["--autostart=false", "--timeout", "2s", "do", "-e", script],
                    environment: rexCleanEnvironment(),
                    captureStdout: false,
                    timeoutSeconds: 2.8
                )
                return execResult.succeeded
            }

            if let initialPane = item.rexPane, tryWritePromptToPane(initialPane) {
                return true
            }
            if let pid = item.pid {
                let liveRexMap = queryRexBlocks(home: home)
                if let found = liveRexMap[pid], found.location != item.rexPane, tryWritePromptToPane(found.location) {
                    return true
                }
            }
        }

        if item.sshTarget == nil, let tty = item.tty, !tty.isEmpty {
            return writeToLocalTTY(ttyName: tty, data: Data((trimmed + "\r").utf8))
        }
        return false
    }

    private nonisolated static func performInterrupt(for item: AgentActivityItem) -> Bool {
        if item.ghosttyPane != nil || item.terminalHost == .ghostty {
            return performGhosttyInterrupt(for: item)
        }
        return performRexInterrupt(for: item)
    }

    private nonisolated static func performGhosttyInterrupt(for item: AgentActivityItem) -> Bool {
        // Tier 1: Ghostty AppleScript `send key "escape"` + `send key "c" modifiers "control"`
        if runningGhosttyApplication() != nil {
            let script = """
            on run argv
            \(ghosttyResolveTerminalAppleScriptPreamble)
                    if matchedTerm is not missing value then
                        send key "escape" to matchedTerm
                        delay 0.05
                        send key "c" modifiers "control" to matchedTerm
                        return "OK"
                    end if
                end tell
                return "MISS"
            end run
            """
            let execResult = runProcessWithTimeout(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script] + ghosttyLookupArgs(for: item),
                captureStdout: true,
                timeoutSeconds: 2.0
            )
            if execResult.succeeded,
               let out = String(data: execResult.outputData, encoding: .utf8),
               out.contains("OK") {
                return true
            }
        }

        // Tier 2 fallback: direct local TTY write of Esc + ^C
        if item.sshTarget == nil, let tty = resolvedLocalTTYName(for: item),
           writeToLocalTTY(ttyName: tty, data: Data("\u{1B}\u{03}".utf8)) {
            return true
        }

        // Tier 3 fallback: SIGINT to process
        if let pid = item.pid, pid > 1, Darwin.kill(pid, SIGINT) == 0 {
            return true
        }
        return false
    }

    private nonisolated static func performRexInterrupt(for item: AgentActivityItem) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser

        if let rexBin = resolveRexBinary(home: home) {
            func tryInterruptPane(_ rexPane: RexPaneLocation) -> Bool {
                let script = """
                local sid = \(luaQuote(rexPane.sessionID))
                local bid = \(luaQuote(rexPane.blockID))
                local ok_att = pcall(rex.call, "session.attach", {session_id = sid})
                if not ok_att then os.exit(1) end
                local ok_w1 = pcall(rex.call, "block.method", {
                  session_id = sid,
                  block_id = bid,
                  method = "write",
                  args = { data = \(luaQuote("\u{1B}")) }
                })
                pcall(rex.sleep, 0.05)
                local ok_w2 = pcall(rex.call, "block.method", {
                  session_id = sid,
                  block_id = bid,
                  method = "write",
                  args = { data = \(luaQuote("\u{03}")) }
                })
                if not (ok_w1 or ok_w2) then os.exit(1) end
                """
                let execResult = runProcessWithTimeout(
                    executableURL: rexBin,
                    arguments: ["--autostart=false", "--timeout", "2s", "do", "-e", script],
                    environment: rexCleanEnvironment(),
                    captureStdout: false,
                    timeoutSeconds: 2.8
                )
                return execResult.succeeded
            }

            if let initialPane = item.rexPane, tryInterruptPane(initialPane) {
                return true
            }
            if let pid = item.pid {
                let liveRexMap = queryRexBlocks(home: home)
                if let found = liveRexMap[pid], found.location != item.rexPane, tryInterruptPane(found.location) {
                    return true
                }
            }
        }

        if let pid = item.pid, pid > 1, Darwin.kill(pid, SIGINT) == 0 {
            return true
        }
        if item.sshTarget == nil, let tty = item.tty, !tty.isEmpty {
            return writeToLocalTTY(ttyName: tty, data: Data("\u{1B}\u{03}".utf8))
        }
        return false
    }

    private nonisolated static func buildResumeCommand(for item: AgentHistorySessionItem, baseCommand: String) -> String {
        let trimmedBase = baseCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveBase = trimmedBase.isEmpty ? item.family.defaultLaunchCommand : trimmedBase
        let sid = item.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { return effectiveBase }

        switch item.family {
        case .claude:
            return "\(effectiveBase) --resume \(sid)"
        case .codex:
            return "\(effectiveBase) resume \(sid)"
        case .copilot:
            return "\(effectiveBase) --resume \(sid)"
        case .antigravity:
            return "\(effectiveBase) --conversation \(sid)"
        }
    }

    private nonisolated static func performDeleteHistoricalSession(_ item: AgentHistorySessionItem) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default
        let sid = item.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty, !item.id.contains(":demo-hist-") else { return true }
        guard item.onlineActivityID == nil else { return false }

        switch item.family {
        case .codex:
            let codexDBURL = home.appendingPathComponent(".codex/state_5.sqlite")
            var db: OpaquePointer?
            if sqlite3_open_v2(codexDBURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK {
                defer { sqlite3_close(db) }
                sqlite3_busy_timeout(db, 400)
                let sqlTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

                // 1. Query rollout_path and physically delete the rollout .jsonl file on disk
                let selectSQL = "SELECT rollout_path FROM threads WHERE id = ?;"
                var selectStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
                    defer { sqlite3_finalize(selectStmt) }
                    sqlite3_bind_text(selectStmt, 1, sid, -1, sqlTransient)
                    while sqlite3_step(selectStmt) == SQLITE_ROW {
                        if let cPath = sqlite3_column_text(selectStmt, 0) {
                            let rolloutPath = String(cString: cPath)
                            if !rolloutPath.isEmpty, fm.fileExists(atPath: rolloutPath) {
                                try? fm.removeItem(atPath: rolloutPath)
                            }
                        }
                    }
                }

                // 2. Physically delete row from threads table
                let deleteSQL = "DELETE FROM threads WHERE id = ?;"
                var deleteStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK {
                    defer { sqlite3_finalize(deleteStmt) }
                    sqlite3_bind_text(deleteStmt, 1, sid, -1, sqlTransient)
                    _ = sqlite3_step(deleteStmt)
                }
            }

            // 3. Fallback scan in ~/.codex/sessions and ~/.codex/archived_sessions for any rollout file matching sid
            for subdir in [".codex/sessions", ".codex/archived_sessions"] {
                let rootURL = home.appendingPathComponent(subdir)
                if let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        if fileURL.lastPathComponent.contains(sid) && fileURL.pathExtension == "jsonl" {
                            try? fm.removeItem(at: fileURL)
                        }
                    }
                }
            }

            // 4. Clean thread_id logs from ~/.codex/logs_2.sqlite
            let logsDBURL = home.appendingPathComponent(".codex/logs_2.sqlite")
            var logsDB: OpaquePointer?
            if sqlite3_open_v2(logsDBURL.path, &logsDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK {
                defer { sqlite3_close(logsDB) }
                sqlite3_busy_timeout(logsDB, 400)
                let sqlTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                let delLogsSQL = "DELETE FROM logs WHERE thread_id = ?;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(logsDB, delLogsSQL, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, sid, -1, sqlTransient)
                    _ = sqlite3_step(stmt)
                    sqlite3_finalize(stmt)
                }
            }

            // 5. Remove from ~/.codex/session_index.jsonl and ~/.codex/history.jsonl
            for jsonlRel in [".codex/session_index.jsonl", ".codex/history.jsonl"] {
                let fileURL = home.appendingPathComponent(jsonlRel)
                if let data = try? Data(contentsOf: fileURL),
                   let text = String(data: data, encoding: .utf8) {
                    let kept = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
                        !line.contains("\"\(sid)\"")
                    }
                    try? kept.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }
            return true

        case .claude:
            // 1. Remove index entries from ~/.claude/history.jsonl
            let claudeHistoryURL = home.appendingPathComponent(".claude/history.jsonl")
            if let data = try? Data(contentsOf: claudeHistoryURL),
               let text = String(data: data, encoding: .utf8) {
                let keptLines = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
                    !line.contains("\"sessionId\":\"\(sid)\"") && !line.contains("\"sessionId\": \"\(sid)\"")
                }
                let updated = keptLines.joined(separator: "\n")
                try? updated.write(to: claudeHistoryURL, atomically: true, encoding: .utf8)
            }

            // 2. Physically delete ~/.claude/projects/*/<sid>.jsonl and ~/.claude/projects/*/<sid> directory
            let projectsRoot = home.appendingPathComponent(".claude/projects")
            if let projectDirs = try? fm.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for dir in projectDirs {
                    let jsonlFile = dir.appendingPathComponent("\(sid).jsonl")
                    if fm.fileExists(atPath: jsonlFile.path) {
                        try? fm.removeItem(at: jsonlFile)
                    }
                    let sessionFolder = dir.appendingPathComponent(sid)
                    if fm.fileExists(atPath: sessionFolder.path) {
                        try? fm.removeItem(at: sessionFolder)
                    }
                }
            }

            // 3. Clean auxiliary session-env / todos / tasks if present
            let sessionEnvDir = home.appendingPathComponent(".claude/session-env").appendingPathComponent(sid)
            if fm.fileExists(atPath: sessionEnvDir.path) {
                try? fm.removeItem(at: sessionEnvDir)
            }
            for auxSubdir in [".claude/todos", ".claude/tasks"] {
                let auxURL = home.appendingPathComponent(auxSubdir)
                if let items = try? fm.contentsOfDirectory(at: auxURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for itemURL in items where itemURL.lastPathComponent.contains(sid) {
                        try? fm.removeItem(at: itemURL)
                    }
                }
            }
            return true

        case .copilot:
            // 1. Physically delete ~/.copilot/session-state/<sid> directory
            let sessionDir = home.appendingPathComponent(".copilot/session-state").appendingPathComponent(sid)
            if fm.fileExists(atPath: sessionDir.path) {
                try? fm.removeItem(at: sessionDir)
            }

            // 2. Physically delete session records from ~/.copilot/session-store.db
            let storeDBURL = home.appendingPathComponent(".copilot/session-store.db")
            var db: OpaquePointer?
            if sqlite3_open_v2(storeDBURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK {
                defer { sqlite3_close(db) }
                sqlite3_busy_timeout(db, 400)
                let sqlTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                let deleteQueries = [
                    "DELETE FROM turns WHERE session_id = ?;",
                    "DELETE FROM checkpoints WHERE session_id = ?;",
                    "DELETE FROM session_files WHERE session_id = ?;",
                    "DELETE FROM session_refs WHERE session_id = ?;",
                    "DELETE FROM forge_trajectory_events WHERE session_id = ?;",
                    "DELETE FROM assistant_usage_events WHERE session_id = ?;",
                    "DELETE FROM search_index WHERE session_id = ?;",
                    "DELETE FROM sessions WHERE id = ?;",
                ]
                for query in deleteQueries {
                    var stmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(stmt, 1, sid, -1, sqlTransient)
                        _ = sqlite3_step(stmt)
                        sqlite3_finalize(stmt)
                    }
                }
            }

            // 3. Clean from ~/.copilot/sidebar-sessions-state/*.json
            let sidebarDir = home.appendingPathComponent(".copilot/sidebar-sessions-state")
            if let sidebarFiles = try? fm.contentsOfDirectory(at: sidebarDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for fileURL in sidebarFiles where fileURL.pathExtension == "json" {
                    if let data = try? Data(contentsOf: fileURL),
                       var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       var sids = json["sessionIds"] as? [String],
                       sids.contains(sid) {
                        sids.removeAll { $0 == sid }
                        json["sessionIds"] = sids
                        if let outData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                            try? outData.write(to: fileURL, options: .atomic)
                        }
                    }
                }
            }
            return true

        case .antigravity:
            // 1. Remove from ~/.gemini/antigravity-cli/conversation_summaries.db
            let summariesDBURL = home.appendingPathComponent(".gemini/antigravity-cli/conversation_summaries.db")
            var sumDB: OpaquePointer?
            if sqlite3_open_v2(summariesDBURL.path, &sumDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK {
                defer { sqlite3_close(sumDB) }
                sqlite3_busy_timeout(sumDB, 400)
                let sqlTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                let delSQL = "DELETE FROM conversation_summaries WHERE conversation_id = ?;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(sumDB, delSQL, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, sid, -1, sqlTransient)
                    _ = sqlite3_step(stmt)
                    sqlite3_finalize(stmt)
                }
            }

            // 2. Remove from ~/.gemini/antigravity-cli/history.jsonl
            let agyHistoryURL = home.appendingPathComponent(".gemini/antigravity-cli/history.jsonl")
            if let data = try? Data(contentsOf: agyHistoryURL),
               let text = String(data: data, encoding: .utf8) {
                let keptLines = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
                    !line.contains("\"conversationId\":\"\(sid)\"") && !line.contains("\"conversationId\": \"\(sid)\"")
                }
                let updated = keptLines.joined(separator: "\n")
                try? updated.write(to: agyHistoryURL, atomically: true, encoding: .utf8)
            }

            // 3. Physically delete ~/.gemini/antigravity-cli/conversations/<sid>.db*, brain/<sid>, and presence/<sid>.lock
            let convDir = home.appendingPathComponent(".gemini/antigravity-cli/conversations")
            for suffix in [".db", ".db-wal", ".db-shm"] {
                let dbFile = convDir.appendingPathComponent("\(sid)\(suffix)")
                if fm.fileExists(atPath: dbFile.path) {
                    try? fm.removeItem(at: dbFile)
                }
            }
            let brainDir = home.appendingPathComponent(".gemini/antigravity-cli/brain").appendingPathComponent(sid)
            if fm.fileExists(atPath: brainDir.path) {
                try? fm.removeItem(at: brainDir)
            }
            let presenceLock = home.appendingPathComponent(".gemini/antigravity-cli/presence").appendingPathComponent("\(sid).lock")
            if fm.fileExists(atPath: presenceLock.path) {
                try? fm.removeItem(at: presenceLock)
            }
            return true
        }
    }

    private nonisolated static func collectHistoricalSessions(liveItems: [AgentActivityItem]) -> [AgentHistorySessionItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let deletedKeys = loadDeletedHistoryKeys()
        var onlineBySessionID: [String: String] = [:]
        for live in liveItems {
            if let sid = live.sessionID, !sid.isEmpty {
                onlineBySessionID[sid] = live.id
            }
        }

        var results: [AgentHistorySessionItem] = []
        var staleDeletedOnDisk: [AgentHistorySessionItem] = []
        var seenKeys = Set<String>()

        func addEntry(_ entry: AgentHistorySessionItem) {
            let key = "\(entry.family.rawValue):\(entry.sessionID)"
            guard !entry.sessionID.isEmpty, !seenKeys.contains(key) else { return }
            seenKeys.insert(key)
            if deletedKeys.contains(entry.id) || deletedKeys.contains(key) || deletedKeys.contains(entry.sessionID) {
                if entry.onlineActivityID == nil {
                    staleDeletedOnDisk.append(entry)
                }
                return
            }
            results.append(entry)
        }

        func openSQLiteForReading(_ url: URL) -> OpaquePointer? {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            var handle: OpaquePointer?
            if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK {
                sqlite3_busy_timeout(handle, 400)
                return handle
            }
            if let handle { sqlite3_close(handle) }
            handle = nil
            if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK {
                sqlite3_busy_timeout(handle, 400)
                return handle
            }
            if let handle { sqlite3_close(handle) }
            return nil
        }

        // 1. Codex CLI History from ~/.codex/state_5.sqlite & ~/.codex/sessions
        let en = AppLanguage.current == .english
        let codexDBURL = home.appendingPathComponent(".codex/state_5.sqlite")
        let codexTitles = loadCodexTitles(home: home)
        if let db = openSQLiteForReading(codexDBURL) {
            defer { sqlite3_close(db) }
            let sql = """
            SELECT id, cwd, COALESCE(NULLIF(name, ''), NULLIF(title, ''), first_user_message), updated_at, git_branch
            FROM threads
            WHERE archived = 0
            ORDER BY updated_at DESC
            LIMIT 500;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let sid = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                    let cwd = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                    let rawTitle = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                    let updatedSec = sqlite3_column_int64(stmt, 3)
                    let branch = sqlite3_column_text(stmt, 4).map { String(cString: $0) }

                    guard !sid.isEmpty else { continue }
                    let wsName = URL(fileURLWithPath: cwd).lastPathComponent
                    let workspace = wsName.isEmpty || wsName == "/" ? "Codex" : wsName
                    let shortID = String(sid.prefix(8))
                    let unnamedFallback = en ? "Untitled Session (\(shortID))" : "未命名会话 (\(shortID))"
                    let title = codexTitles.bySessionID[sid]
                        ?? extractUserPromptAfterEnvironment(rawTitle ?? "")
                        ?? cleanSessionTitle(rawTitle)
                        ?? unnamedFallback
                    let updatedAt = updatedSec > 1_000_000_000_000
                        ? Date(timeIntervalSince1970: Double(updatedSec) / 1000.0)
                        : Date(timeIntervalSince1970: Double(max(1, updatedSec)))

                    addEntry(
                        AgentHistorySessionItem(
                            id: "codex:\(sid)",
                            sessionID: sid,
                            family: .codex,
                            title: title,
                            workspace: workspace,
                            cwdPath: cwd.isEmpty ? home.path : cwd,
                            gitBranch: (branch?.isEmpty == false) ? branch : nil,
                            updatedAt: updatedAt,
                            onlineActivityID: onlineBySessionID[sid]
                        )
                    )
                }
            }
        }

        // Fallback scan for any Codex rollout files on disk not yet in state_5.sqlite
        let codexSessionsRoot = home.appendingPathComponent(".codex/sessions")
        if let enumerator = FileManager.default.enumerator(
            at: codexSessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" && fileURL.lastPathComponent.hasPrefix("rollout-") {
                let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                if let info = parseCodexRolloutFile(fileURL, modDate: modDate), !info.sessionID.isEmpty {
                    let wsName = URL(fileURLWithPath: info.cwdPath).lastPathComponent
                    let workspace = wsName.isEmpty || wsName == "/" ? "Codex" : wsName
                    let shortID = String(info.sessionID.prefix(8))
                    let unnamedFallback = en ? "Untitled Session (\(shortID))" : "未命名会话 (\(shortID))"
                    let title = codexTitles.bySessionID[info.sessionID]
                        ?? info.fallbackTitle
                        ?? unnamedFallback
                    addEntry(
                        AgentHistorySessionItem(
                            id: "codex:\(info.sessionID)",
                            sessionID: info.sessionID,
                            family: .codex,
                            title: title,
                            workspace: workspace,
                            cwdPath: info.cwdPath.isEmpty ? home.path : info.cwdPath,
                            gitBranch: nil,
                            updatedAt: info.updatedAt,
                            onlineActivityID: onlineBySessionID[info.sessionID]
                        )
                    )
                }
            }
        }

        // 2. Claude Code History from ~/.claude/history.jsonl AND ~/.claude/projects/*/*.jsonl
        struct ClaudeHistAcc {
            var sessionID: String
            var cwdPath: String
            var gitBranch: String?
            var latestPrompt: String?
            var aiTitle: String?
            var updatedDate: Date
        }
        var claudeBySid: [String: ClaudeHistAcc] = [:]

        let claudeHistoryURL = home.appendingPathComponent(".claude/history.jsonl")
        if let data = try? Data(contentsOf: claudeHistoryURL),
           let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let sid = json["sessionId"] as? String, !sid.isEmpty else { continue }
                let project = (json["project"] as? String) ?? home.path
                let ts = (json["timestamp"] as? Double) ?? 0
                let date = ts > 0 ? Date(timeIntervalSince1970: ts / 1000.0) : Date.distantPast
                let display = json["display"] as? String
                let cleanedPrompt: String? = {
                    guard let display, !display.hasPrefix("/") else { return nil }
                    return cleanSessionTitle(display)
                }()

                if var existing = claudeBySid[sid] {
                    if date >= existing.updatedDate {
                        existing.updatedDate = date
                        if !project.isEmpty { existing.cwdPath = project }
                    }
                    if let cleanedPrompt {
                        existing.latestPrompt = cleanedPrompt
                    }
                    claudeBySid[sid] = existing
                } else {
                    claudeBySid[sid] = ClaudeHistAcc(
                        sessionID: sid,
                        cwdPath: project,
                        gitBranch: nil,
                        latestPrompt: cleanedPrompt,
                        aiTitle: nil,
                        updatedDate: date
                    )
                }
            }
        }

        // Scan all ~/.claude/projects/*/*.jsonl files to capture sessions not in history.jsonl and enrich metadata
        let claudeProjectsRoot = home.appendingPathComponent(".claude/projects")
        if let projectDirs = try? FileManager.default.contentsOfDirectory(at: claudeProjectsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for dir in projectDirs {
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for fileURL in files where fileURL.pathExtension == "jsonl" {
                    let sid = fileURL.deletingPathExtension().lastPathComponent
                    guard !sid.isEmpty else { continue }
                    let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

                    var fileCwd: String?
                    var fileBranch: String?
                    var fileAiTitle: String?
                    var fileLastPrompt: String?
                    var fileUserMsg: String?

                    if let handle = try? FileHandle(forReadingFrom: fileURL) {
                        defer { try? handle.close() }
                        let headData = (try? handle.read(upToCount: 16384)) ?? Data()
                        if let headText = String(data: headData, encoding: .utf8) {
                            for line in headText.split(separator: "\n") {
                                guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                                if fileCwd == nil, let cwd = json["cwd"] as? String, !cwd.isEmpty {
                                    fileCwd = cwd
                                }
                                if fileBranch == nil, let br = json["gitBranch"] as? String, !br.isEmpty, br != "HEAD" {
                                    fileBranch = br
                                }
                                if fileUserMsg == nil, (json["type"] as? String) == "user",
                                   let msg = json["message"] as? [String: Any] {
                                    if let contentStr = msg["content"] as? String, !contentStr.hasPrefix("/") {
                                        fileUserMsg = cleanSessionTitle(contentStr)
                                    } else if let parts = msg["content"] as? [[String: Any]] {
                                        for part in parts where (part["type"] as? String) == "text" {
                                            if let txt = part["text"] as? String, !txt.hasPrefix("<"), !txt.hasPrefix("/"),
                                               let cleaned = cleanSessionTitle(txt) {
                                                fileUserMsg = cleaned
                                                break
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        let totalSize = (try? handle.seekToEnd()) ?? 0
                        let tailOffset = totalSize > 32768 ? totalSize - 32768 : 0
                        try? handle.seek(toOffset: tailOffset)
                        let tailData = (try? handle.readToEnd()) ?? Data()
                        if let tailText = String(data: tailData, encoding: .utf8) {
                            for line in tailText.split(separator: "\n") {
                                if line.contains("\"ai-title\""),
                                   let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                                   let raw = cleanSessionTitle(json["aiTitle"] as? String) {
                                    fileAiTitle = raw
                                } else if line.contains("\"last-prompt\""),
                                          let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                                          let raw = json["lastPrompt"] as? String,
                                          !raw.hasPrefix("/"),
                                          let cleaned = cleanSessionTitle(raw) {
                                    fileLastPrompt = cleaned
                                }
                            }
                        }
                    }

                    if var existing = claudeBySid[sid] {
                        if modDate > existing.updatedDate {
                            existing.updatedDate = modDate
                        }
                        if existing.cwdPath.isEmpty, let fileCwd {
                            existing.cwdPath = fileCwd
                        }
                        if existing.gitBranch == nil {
                            existing.gitBranch = fileBranch
                        }
                        if let fileAiTitle {
                            existing.aiTitle = fileAiTitle
                        }
                        if existing.latestPrompt == nil {
                            existing.latestPrompt = fileLastPrompt ?? fileUserMsg
                        }
                        claudeBySid[sid] = existing
                    } else {
                        claudeBySid[sid] = ClaudeHistAcc(
                            sessionID: sid,
                            cwdPath: fileCwd ?? home.path,
                            gitBranch: fileBranch,
                            latestPrompt: fileLastPrompt ?? fileUserMsg,
                            aiTitle: fileAiTitle,
                            updatedDate: modDate
                        )
                    }
                }
            }
        }

        for item in claudeBySid.values.sorted(by: { $0.updatedDate > $1.updatedDate }) {
            let wsName = URL(fileURLWithPath: item.cwdPath).lastPathComponent
            let workspace = wsName.isEmpty || wsName == "/" ? "Claude" : wsName
            let shortID = String(item.sessionID.prefix(8))
            let unnamedFallback = en ? "Untitled Session (\(shortID))" : "未命名会话 (\(shortID))"
            let resolvedTitle = item.aiTitle
                ?? item.latestPrompt
                ?? unnamedFallback

            addEntry(
                AgentHistorySessionItem(
                    id: "claude:\(item.sessionID)",
                    sessionID: item.sessionID,
                    family: .claude,
                    title: resolvedTitle,
                    workspace: workspace,
                    cwdPath: item.cwdPath,
                    gitBranch: item.gitBranch,
                    updatedAt: item.updatedDate,
                    onlineActivityID: onlineBySessionID[item.sessionID]
                )
            )
        }

        // 3. Copilot CLI History from ~/.copilot/session-store.db & ~/.copilot/session-state
        let isoFormatterFractional = ISO8601DateFormatter()
        isoFormatterFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterPlain = ISO8601DateFormatter()
        isoFormatterPlain.formatOptions = [.withInternetDateTime]

        func parseISO8601Date(_ raw: String?) -> Date? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            let normalized = raw.replacingOccurrences(of: " ", with: "T")
            return isoFormatterFractional.date(from: normalized) ?? isoFormatterPlain.date(from: normalized)
        }

        let copilotStoreURL = home.appendingPathComponent(".copilot/session-store.db")
        if let copilotDB = openSQLiteForReading(copilotStoreURL) {
            defer { sqlite3_close(copilotDB) }
            let sql = """
            SELECT
                s.id,
                s.cwd,
                s.branch,
                s.summary,
                (SELECT t.user_message FROM turns t WHERE t.session_id = s.id ORDER BY t.turn_index DESC LIMIT 1),
                s.updated_at
            FROM sessions s
            ORDER BY s.updated_at DESC
            LIMIT 500;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(copilotDB, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let sid = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                    guard !sid.isEmpty, !sid.hasPrefix("pending-session:") else { continue }
                    let cwdRaw = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                    let branch = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                    let summaryRaw = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                    let turnMsgRaw = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                    let updatedStr = sqlite3_column_text(stmt, 5).map { String(cString: $0) }

                    let workspaceURL = home.appendingPathComponent(".copilot/session-state").appendingPathComponent(sid).appendingPathComponent("workspace.yaml")
                    let yamlTitle = cleanSessionTitle(parseSimpleYAMLValue(at: workspaceURL, key: "name"))
                    let cwdPath = !cwdRaw.isEmpty ? cwdRaw : (parseSimpleYAMLValue(at: workspaceURL, key: "cwd") ?? home.path)
                    let wsName = URL(fileURLWithPath: cwdPath).lastPathComponent
                    let workspace = wsName.isEmpty || wsName == "/" ? "Copilot" : wsName

                    let shortID = String(sid.prefix(8))
                    let unnamedFallback = en ? "Untitled Session (\(shortID))" : "未命名会话 (\(shortID))"
                    let title = yamlTitle
                        ?? cleanSessionTitle(summaryRaw)
                        ?? cleanSessionTitle(turnMsgRaw)
                        ?? unnamedFallback

                    let updatedAt = parseISO8601Date(updatedStr) ?? Date()

                    addEntry(
                        AgentHistorySessionItem(
                            id: "copilot:\(sid)",
                            sessionID: sid,
                            family: .copilot,
                            title: title,
                            workspace: workspace,
                            cwdPath: cwdPath,
                            gitBranch: (branch?.isEmpty == false) ? branch : nil,
                            updatedAt: updatedAt,
                            onlineActivityID: onlineBySessionID[sid]
                        )
                    )
                }
            }
        }

        let copilotRoot = home.appendingPathComponent(".copilot/session-state")
        if let dirs = try? FileManager.default.contentsOfDirectory(
            at: copilotRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let sortedDirs = dirs.compactMap { url -> (URL, Date)? in
                let name = url.lastPathComponent
                guard !name.hasPrefix("pending-session:"),
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
                let eventsURL = url.appendingPathComponent("events.jsonl")
                let workspaceURL = url.appendingPathComponent("workspace.yaml")
                if let vals = try? eventsURL.resourceValues(forKeys: [.contentModificationDateKey]),
                   let mod = vals.contentModificationDate {
                    return (url, mod)
                }
                if let updatedStr = parseSimpleYAMLValue(at: workspaceURL, key: "updated_at"),
                   let parsedDate = parseISO8601Date(updatedStr) {
                    return (url, parsedDate)
                }
                if let vals = try? workspaceURL.resourceValues(forKeys: [.contentModificationDateKey]),
                   let mod = vals.contentModificationDate {
                    return (url, mod)
                }
                return nil
            }.sorted { $0.1 > $1.1 }

            for (dirURL, modDate) in sortedDirs {
                let sid = dirURL.lastPathComponent
                let workspaceURL = dirURL.appendingPathComponent("workspace.yaml")
                let eventsURL = dirURL.appendingPathComponent("events.jsonl")
                let cwdPath = parseSimpleYAMLValue(at: workspaceURL, key: "cwd") ?? home.path
                let yamlTitle = cleanSessionTitle(parseSimpleYAMLValue(at: workspaceURL, key: "name"))
                let tail = parseCopilotEventsTail(eventsURL)
                let wsName = URL(fileURLWithPath: cwdPath).lastPathComponent
                let workspace = wsName.isEmpty || wsName == "/" ? "Copilot" : wsName
                let shortID = String(sid.prefix(8))
                let unnamedFallback = en ? "Untitled Session (\(shortID))" : "未命名会话 (\(shortID))"
                let title = yamlTitle ?? tail.lastUserMessage ?? unnamedFallback

                addEntry(
                    AgentHistorySessionItem(
                        id: "copilot:\(sid)",
                        sessionID: sid,
                        family: .copilot,
                        title: title,
                        workspace: workspace,
                        cwdPath: cwdPath,
                        gitBranch: nil,
                        updatedAt: modDate,
                        onlineActivityID: onlineBySessionID[sid]
                    )
                )
            }
        }

        // 4. Antigravity CLI History from ~/.gemini/antigravity-cli/conversation_summaries.db, conversations/*.db & history.jsonl
        struct AgyHistAcc {
            var conversationID: String
            var cwdPath: String
            var title: String?
            var updatedDate: Date
        }
        var agyByCid: [String: AgyHistAcc] = [:]

        let agySummariesURL = home.appendingPathComponent(".gemini/antigravity-cli/conversation_summaries.db")
        if let agyDB = openSQLiteForReading(agySummariesURL) {
            defer { sqlite3_close(agyDB) }
            let sql = """
            SELECT conversation_id, title, preview, workspace_uris, last_modified_time
            FROM conversation_summaries
            WHERE killed = 0
            ORDER BY last_modified_time DESC
            LIMIT 300;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(agyDB, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let cid = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                    guard !cid.isEmpty else { continue }
                    let rawTitle = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                    let rawPreview = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                    let rawUris = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                    let rawTime = sqlite3_column_text(stmt, 4).map { String(cString: $0) }

                    var parsedCwd = home.path
                    if let data = rawUris.data(using: .utf8),
                       let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
                       let firstUri = arr.first,
                       let url = URL(string: firstUri), url.isFileURL {
                        parsedCwd = url.path
                    }

                    let title = cleanSessionTitle(rawTitle) ?? cleanSessionTitle(rawPreview)
                    let updatedDate = parseISO8601Date(rawTime) ?? Date()
                    agyByCid[cid] = AgyHistAcc(
                        conversationID: cid,
                        cwdPath: parsedCwd,
                        title: title,
                        updatedDate: updatedDate
                    )
                }
            }
        }

        let agyHistoryURL = home.appendingPathComponent(".gemini/antigravity-cli/history.jsonl")
        if let data = try? Data(contentsOf: agyHistoryURL),
           let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let cid = json["conversationId"] as? String, !cid.isEmpty else { continue }
                let ws = (json["workspace"] as? String) ?? home.path
                let ts = (json["timestamp"] as? Double) ?? 0
                let date = ts > 0 ? Date(timeIntervalSince1970: ts / 1000.0) : Date()
                let isSlash = (json["type"] as? String) == "slash_command"
                let display = json["display"] as? String
                let promptTitle: String? = (!isSlash && display?.hasPrefix("/") == false) ? cleanSessionTitle(display) : nil

                if var existing = agyByCid[cid] {
                    if date > existing.updatedDate {
                        existing.updatedDate = date
                    }
                    if !ws.isEmpty {
                        existing.cwdPath = ws
                    }
                    if existing.title == nil, let promptTitle {
                        existing.title = promptTitle
                    }
                    agyByCid[cid] = existing
                } else {
                    agyByCid[cid] = AgyHistAcc(
                        conversationID: cid,
                        cwdPath: ws,
                        title: promptTitle,
                        updatedDate: date
                    )
                }
            }
        }

        let agyConvDir = home.appendingPathComponent(".gemini/antigravity-cli/conversations")
        if let dbFiles = try? FileManager.default.contentsOfDirectory(
            at: agyConvDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in dbFiles where fileURL.pathExtension == "db" {
                let cid = fileURL.deletingPathExtension().lastPathComponent
                guard !cid.isEmpty, agyByCid[cid] == nil else { continue }
                let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                agyByCid[cid] = AgyHistAcc(
                    conversationID: cid,
                    cwdPath: home.path,
                    title: nil,
                    updatedDate: modDate
                )
            }
        }

        for item in agyByCid.values.sorted(by: { $0.updatedDate > $1.updatedDate }) {
            let shortID = String(item.conversationID.prefix(8))
            let unnamedFallback = en ? "Untitled Session (\(shortID))" : "未命名会话 (\(shortID))"
            let title = item.title ?? unnamedFallback
            let wsName = URL(fileURLWithPath: item.cwdPath).lastPathComponent
            let workspace = wsName.isEmpty || wsName == "/" ? "Antigravity" : wsName

            addEntry(
                AgentHistorySessionItem(
                    id: "antigravity:\(item.conversationID)",
                    sessionID: item.conversationID,
                    family: .antigravity,
                    title: title,
                    workspace: workspace,
                    cwdPath: item.cwdPath,
                    gitBranch: nil,
                    updatedAt: item.updatedDate,
                    onlineActivityID: onlineBySessionID[item.conversationID]
                )
            )
        }

        for staleItem in staleDeletedOnDisk {
            _ = performDeleteHistoricalSession(staleItem)
        }

        results.sort { $0.updatedAt > $1.updatedAt }
        return results
    }

    private nonisolated static func performLaunch(
        family: AgentFamily,
        cwdPath: String,
        customCommand: String,
        preferredTabTitle: String? = nil,
        preferredHost: TerminalHostKind = .rex
    ) -> Bool {
        if preferredHost == .ghostty {
            if performGhosttyLaunch(
                family: family,
                cwdPath: cwdPath,
                customCommand: customCommand,
                preferredTabTitle: preferredTabTitle
            ) {
                return true
            }
            return performRexLaunch(
                family: family,
                cwdPath: cwdPath,
                customCommand: customCommand,
                preferredTabTitle: preferredTabTitle
            )
        } else {
            if performRexLaunch(
                family: family,
                cwdPath: cwdPath,
                customCommand: customCommand,
                preferredTabTitle: preferredTabTitle
            ) {
                return true
            }
            return performGhosttyLaunch(
                family: family,
                cwdPath: cwdPath,
                customCommand: customCommand,
                preferredTabTitle: preferredTabTitle
            )
        }
    }

    private nonisolated static func performSSHLaunch(
        family: AgentFamily,
        sshTarget: String,
        remotePath: String,
        customCommand: String,
        preferredHost: TerminalHostKind = .rex
    ) -> Bool {
        if preferredHost == .ghostty {
            if performGhosttySSHLaunch(
                family: family,
                sshTarget: sshTarget,
                remotePath: remotePath,
                customCommand: customCommand
            ) {
                return true
            }
            return performRexSSHLaunch(
                family: family,
                sshTarget: sshTarget,
                remotePath: remotePath,
                customCommand: customCommand
            )
        } else {
            if performRexSSHLaunch(
                family: family,
                sshTarget: sshTarget,
                remotePath: remotePath,
                customCommand: customCommand
            ) {
                return true
            }
            return performGhosttySSHLaunch(
                family: family,
                sshTarget: sshTarget,
                remotePath: remotePath,
                customCommand: customCommand
            )
        }
    }

    private nonisolated static func performGhosttyLaunch(
        family: AgentFamily,
        cwdPath: String,
        customCommand: String,
        preferredTabTitle: String? = nil
    ) -> Bool {
        guard let appBundleURL = ghosttyAppBundleURL() else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser
        dismissMenuBarPanelWindows()

        let resolvedCwd: String = {
            let trimmed = cwdPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return home.path }
            let expanded = (trimmed as NSString).expandingTildeInPath
            let candidate = URL(fileURLWithPath: expanded).standardizedFileURL.path
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
            return home.path
        }()
        let dirName = URL(fileURLWithPath: resolvedCwd).lastPathComponent
        let tabLabel: String = {
            if let preferredTabTitle = preferredTabTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !preferredTabTitle.isEmpty {
                let shortTitle = preferredTabTitle.count > 26
                    ? String(preferredTabTitle.prefix(26)) + "…"
                    : preferredTabTitle
                return "\(family.shortName) · \(shortTitle)"
            }
            return dirName.isEmpty || dirName == "/" ? family.shortName : "\(family.shortName) · \(dirName)"
        }()
        let trimmedCmd = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveCmd = trimmedCmd.isEmpty ? family.defaultLaunchCommand : trimmedCmd
        let cmdLine = "\(effectiveCmd)\n"

        // Tier 1: Native Ghostty AppleScript `new surface configuration`
        let appleScript = """
        on run argv
            set targetCwd to item 1 of argv
            set targetInput to item 2 of argv
            set targetTitle to item 3 of argv
            tell application "Ghostty"
                activate
                set cfg to new surface configuration
                set initial working directory of cfg to targetCwd
                set initial input of cfg to targetInput
                if (count of windows) > 0 then
                    set newTab to new tab in front window with configuration cfg
                    try
                        set name override of newTab to targetTitle
                    end try
                else
                    set newWin to new window with configuration cfg
                    try
                        set name override of (selected tab of newWin) to targetTitle
                    end try
                end if
            end tell
            return "OK"
        end run
        """

        let scriptResult = runProcessWithTimeout(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", appleScript, resolvedCwd, cmdLine, tabLabel],
            captureStdout: true,
            timeoutSeconds: 3.0
        )
        if scriptResult.succeeded {
            _ = activateGhosttyApp()
            return true
        }

        // Tier 2 fallback: launch Ghostty via `/usr/bin/open -na` with `--working-directory` and interactive shell
        let fallbackShellPayload = "\(effectiveCmd); exec ${SHELL:-/bin/zsh} -l"
        let openResult = runProcessWithTimeout(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: [
                "-na", appBundleURL.path,
                "--args",
                "--working-directory=\(resolvedCwd)",
                "-e", "/bin/zsh", "-lic", fallbackShellPayload,
            ],
            captureStdout: false,
            timeoutSeconds: 3.0
        )
        if openResult.succeeded {
            _ = activateGhosttyApp()
            return true
        }
        return false
    }

    private nonisolated static func performGhosttySSHLaunch(
        family: AgentFamily,
        sshTarget: String,
        remotePath: String,
        customCommand: String
    ) -> Bool {
        guard let appBundleURL = ghosttyAppBundleURL() else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser
        dismissMenuBarPanelWindows()

        let cleanHost = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return false }

        let trimmedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let dirSuffix: String = {
            if trimmedPath.isEmpty || trimmedPath == "~" || trimmedPath == "/" {
                return cleanHost
            }
            let lastComp = URL(fileURLWithPath: trimmedPath).lastPathComponent
            return lastComp.isEmpty ? cleanHost : "\(cleanHost) · \(lastComp)"
        }()
        let tabLabel = "\(family.shortName) · \(dirSuffix)"

        let trimmedCmd = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveCmd = trimmedCmd.isEmpty ? family.defaultLaunchCommand : trimmedCmd

        let cdClause: String = {
            if trimmedPath.isEmpty || trimmedPath == "~" {
                return ""
            }
            if trimmedPath.hasPrefix("~/") {
                let rel = String(trimmedPath.dropFirst(2))
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "cd \"$HOME/\(rel)\" && "
            }
            let esc = trimmedPath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "cd \"\(esc)\" && "
        }()

        let escapedSingleQuotesCmd = effectiveCmd.replacingOccurrences(of: "'", with: "'\\''")
        let remoteShellPayload = "\(cdClause)exec \\$SHELL -lic '\(escapedSingleQuotesCmd)'"
        let sshCommand = "ssh -t \(cleanHost) \"\(remoteShellPayload)\""
        let sshCommandLine = "\(sshCommand)\n"

        // Tier 1: Native Ghostty AppleScript `new surface configuration`
        let appleScript = """
        on run argv
            set targetCwd to item 1 of argv
            set targetInput to item 2 of argv
            set targetTitle to item 3 of argv
            tell application "Ghostty"
                activate
                set cfg to new surface configuration
                set initial working directory of cfg to targetCwd
                set initial input of cfg to targetInput
                if (count of windows) > 0 then
                    set newTab to new tab in front window with configuration cfg
                    try
                        set name override of newTab to targetTitle
                    end try
                else
                    set newWin to new window with configuration cfg
                    try
                        set name override of (selected tab of newWin) to targetTitle
                    end try
                end if
            end tell
            return "OK"
        end run
        """

        let scriptResult = runProcessWithTimeout(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", appleScript, home.path, sshCommandLine, tabLabel],
            captureStdout: true,
            timeoutSeconds: 3.0
        )
        if scriptResult.succeeded {
            _ = activateGhosttyApp()
            return true
        }

        // Tier 2 fallback: launch Ghostty via `/usr/bin/open -na`
        let fallbackShellPayload = "\(sshCommand); exec ${SHELL:-/bin/zsh} -l"
        let openResult = runProcessWithTimeout(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: [
                "-na", appBundleURL.path,
                "--args",
                "--working-directory=\(home.path)",
                "-e", "/bin/zsh", "-lic", fallbackShellPayload,
            ],
            captureStdout: false,
            timeoutSeconds: 3.0
        )
        if openResult.succeeded {
            _ = activateGhosttyApp()
            return true
        }
        return false
    }

    private nonisolated static func performRexLaunch(
        family: AgentFamily,
        cwdPath: String,
        customCommand: String,
        preferredTabTitle: String? = nil
    ) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let rexBin = resolveRexBinary(home: home) else { return false }
        ensureRexRemoteControlEnabled()
        dismissMenuBarPanelWindows()

        let resolvedCwd: String = {
            let trimmed = cwdPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return home.path }
            let candidate = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
            return home.path
        }()
        let dirName = URL(fileURLWithPath: resolvedCwd).lastPathComponent
        let tabLabel: String = {
            if let preferredTabTitle = preferredTabTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !preferredTabTitle.isEmpty {
                let shortTitle = preferredTabTitle.count > 26
                    ? String(preferredTabTitle.prefix(26)) + "…"
                    : preferredTabTitle
                return "\(family.shortName) · \(shortTitle)"
            }
            return dirName.isEmpty || dirName == "/" ? family.shortName : "\(family.shortName) · \(dirName)"
        }()
        let trimmedCmd = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveCmd = trimmedCmd.isEmpty ? family.defaultLaunchCommand : trimmedCmd
        let cmdLine = "\(effectiveCmd)\n"

        let script = """
        local ok_c, c_res = pcall(rex.call, "client.list")
        local clients = (ok_c and c_res and c_res.clients) or {}
        local sid = nil
        for _, c in ipairs(clients) do
          if c.info and c.info.kind == "app" and c.connection_state == "connected" then
            if c.session_ids and c.session_ids[1] then
              sid = c.session_ids[1]
              break
            end
          end
        end
        if not sid then
          local ok_s, s_res = pcall(rex.call, "session.list")
          local sessions = (ok_s and s_res and s_res.sessions) or {}
          if #sessions > 0 then
            sid = sessions[1].session_id
          end
        end
        if sid then
          pcall(rex.call, "session.attach", {session_id = sid})
        else
          local ok_cr, created = pcall(rex.call, "session.create", {label = \(luaQuote(dirName.isEmpty ? "workspace" : dirName))})
          sid = ok_cr and created and created.session_id
        end
        if not sid then os.exit(1) end

        local ok_nw, res = pcall(rex.call, "session.new_window", {
          session_id = sid,
          window_label = \(luaQuote(tabLabel)),
          focus = true,
          layout = {
            block = {
              flavor = "com.superlogical.terminal.shell",
              label = \(luaQuote(family.shortName)),
              options = {
                cwd = \(luaQuote(resolvedCwd)),
                initial_input = \(luaQuote(cmdLine)),
                exit = { on_completion = false }
              }
            }
          }
        })
        if not ok_nw or not res then os.exit(1) end
        local wid = res and res.window_id
        local bid = res and res.block_ids and res.block_ids[1]
        if wid then
          pcall(rex.call, "session.focus_window", {session_id = sid, window_id = wid})
        end
        if bid then
          pcall(rex.call, "session.focus_block", {session_id = sid, block_id = bid})
        end

        local ok_v, view = pcall(rex.call, "session.view", {session_id = sid})
        if not ok_v then view = nil end
        local win_idx = nil
        if wid and view and view.windows then
          for idx, w in ipairs(view.windows) do
            if w.window_id == wid then win_idx = idx; break end
          end
        end

        for _, c in ipairs(clients) do
          if c.info and c.info.kind == "app" and c.connection_state == "connected" then
            pcall(rex.call, "client.perform", {
              client_id = c.client_id,
              action = "session.select",
              args = {session_id = sid, window_id = wid},
              timeout_ms = 1500
            })
            if win_idx then
              pcall(rex.call, "client.perform", {
                client_id = c.client_id,
                action = "client.tab.goto",
                args = {index = win_idx},
                timeout_ms = 1500
              })
            end
          end
        end
        return true
        """

        let execResult = runProcessWithTimeout(
            executableURL: rexBin,
            arguments: ["--autostart=true", "--timeout", "3s", "do", "-e", script],
            environment: rexCleanEnvironment(),
            captureStdout: false,
            timeoutSeconds: 3.5
        )
        guard execResult.succeeded else { return false }

        _ = activateRexApp()
        return true
    }

    private nonisolated static func performRexSSHLaunch(
        family: AgentFamily,
        sshTarget: String,
        remotePath: String,
        customCommand: String
    ) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let rexBin = resolveRexBinary(home: home) else { return false }
        ensureRexRemoteControlEnabled()
        dismissMenuBarPanelWindows()

        let cleanHost = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return false }

        let trimmedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let dirSuffix: String = {
            if trimmedPath.isEmpty || trimmedPath == "~" || trimmedPath == "/" {
                return cleanHost
            }
            let lastComp = URL(fileURLWithPath: trimmedPath).lastPathComponent
            return lastComp.isEmpty ? cleanHost : "\(cleanHost) · \(lastComp)"
        }()
        let tabLabel = "\(family.shortName) · \(dirSuffix)"

        let trimmedCmd = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveCmd = trimmedCmd.isEmpty ? family.defaultLaunchCommand : trimmedCmd

        let cdClause: String = {
            if trimmedPath.isEmpty || trimmedPath == "~" {
                return ""
            }
            if trimmedPath.hasPrefix("~/") {
                let rel = String(trimmedPath.dropFirst(2))
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "cd \"$HOME/\(rel)\" && "
            }
            let esc = trimmedPath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "cd \"\(esc)\" && "
        }()

        let escapedSingleQuotesCmd = effectiveCmd.replacingOccurrences(of: "'", with: "'\\''")
        let remoteShellPayload = "\(cdClause)exec \\$SHELL -lic '\(escapedSingleQuotesCmd)'"
        let sshCommandLine = "ssh -t \(cleanHost) \"\(remoteShellPayload)\"\n"

        let script = """
        local ok_c, c_res = pcall(rex.call, "client.list")
        local clients = (ok_c and c_res and c_res.clients) or {}
        local sid = nil
        for _, c in ipairs(clients) do
          if c.info and c.info.kind == "app" and c.connection_state == "connected" then
            if c.session_ids and c.session_ids[1] then
              sid = c.session_ids[1]
              break
            end
          end
        end
        if not sid then
          local ok_s, s_res = pcall(rex.call, "session.list")
          local sessions = (ok_s and s_res and s_res.sessions) or {}
          if #sessions > 0 then
            sid = sessions[1].session_id
          end
        end
        if sid then
          pcall(rex.call, "session.attach", {session_id = sid})
        else
          local ok_cr, created = pcall(rex.call, "session.create", {label = \(luaQuote(cleanHost))})
          sid = ok_cr and created and created.session_id
        end
        if not sid then os.exit(1) end

        local ok_nw, res = pcall(rex.call, "session.new_window", {
          session_id = sid,
          window_label = \(luaQuote(tabLabel)),
          focus = true,
          layout = {
            block = {
              flavor = "com.superlogical.terminal.shell",
              label = \(luaQuote("\(family.shortName)@\(cleanHost)")),
              options = {
                cwd = \(luaQuote(home.path)),
                initial_input = \(luaQuote(sshCommandLine)),
                exit = { on_completion = false }
              }
            }
          }
        })
        if not ok_nw or not res then os.exit(1) end
        local wid = res and res.window_id
        local bid = res and res.block_ids and res.block_ids[1]
        if wid then
          pcall(rex.call, "session.focus_window", {session_id = sid, window_id = wid})
        end
        if bid then
          pcall(rex.call, "session.focus_block", {session_id = sid, block_id = bid})
        end

        local ok_v, view = pcall(rex.call, "session.view", {session_id = sid})
        if not ok_v then view = nil end
        local win_idx = nil
        if wid and view and view.windows then
          for idx, w in ipairs(view.windows) do
            if w.window_id == wid then win_idx = idx; break end
          end
        end

        for _, c in ipairs(clients) do
          if c.info and c.info.kind == "app" and c.connection_state == "connected" then
            pcall(rex.call, "client.perform", {
              client_id = c.client_id,
              action = "session.select",
              args = {session_id = sid, window_id = wid},
              timeout_ms = 1500
            })
            if win_idx then
              pcall(rex.call, "client.perform", {
                client_id = c.client_id,
                action = "client.tab.goto",
                args = {index = win_idx},
                timeout_ms = 1500
              })
            end
          end
        end
        return true
        """

        let execResult = runProcessWithTimeout(
            executableURL: rexBin,
            arguments: ["--autostart=true", "--timeout", "3s", "do", "-e", script],
            environment: rexCleanEnvironment(),
            captureStdout: false,
            timeoutSeconds: 3.5
        )
        guard execResult.succeeded else { return false }

        _ = activateRexApp()
        return true
    }

    private nonisolated static func luaQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\u{1B}", with: "\\27")
            .replacingOccurrences(of: "\u{03}", with: "\\003")
        return "\"\(escaped)\""
    }

    private nonisolated static func dismissMenuBarPanelWindows() {
        DispatchQueue.main.sync {
            for window in NSApplication.shared.windows where window.isVisible {
                let className = NSStringFromClass(type(of: window))
                if className.contains("StatusBar") { continue }
                window.orderOut(nil)
            }
        }
    }

    private nonisolated static func hasInteractiveHostApplication(
        pid startPID: Int32,
        ppidMap: [Int32: Int32],
        regularPIDs: Set<Int32>
    ) -> Bool {
        var currentPID = startPID
        for _ in 0..<12 {
            guard currentPID > 1 else { break }
            if regularPIDs.contains(currentPID) {
                return true
            }
            let nextPPID = ppidMap[currentPID] ?? parentPID(of: currentPID)
            if nextPPID <= 1 || nextPPID == currentPID { break }
            currentPID = nextPPID
        }
        return false
    }

    private nonisolated static func parentPID(of pid: Int32) -> Int32 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let status = sysctl(&mib, 4, &info, &size, nil, 0)
        guard status == 0, size > 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }

    private nonisolated static func activateRexApp() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        let candidates = ["com.superlogical.rex", "rex beta", "rex"]
        for candidate in candidates {
            if let app = runningApps.first(where: {
                $0.activationPolicy == .regular && (
                    $0.bundleIdentifier?.lowercased().contains(candidate) == true ||
                    $0.localizedName?.lowercased() == candidate ||
                    $0.executableURL?.lastPathComponent.lowercased() == candidate
                )
            }) {
                DispatchQueue.main.async {
                    NSApplication.shared.deactivate()
                    app.activate(options: [.activateAllWindows])
                }
                return true
            }
        }
        return false
    }

    private nonisolated static func activateGhosttyApp() -> Bool {
        if let app = runningGhosttyApplication() {
            DispatchQueue.main.async {
                NSApplication.shared.deactivate()
                app.activate(options: [.activateAllWindows])
            }
            return true
        }
        return false
    }

    nonisolated static func runGhosttySelfTest() -> Bool {
        let entries: [GhosttyTerminalEntry] = [
            GhosttyTerminalEntry(
                location: GhosttyPaneLocation(windowID: "win-1", tabID: "tab-1", terminalID: "term-pid", ttyPath: "/dev/ttys091"),
                pid: 42001,
                ttyName: "ttys091",
                cwdPath: "/Users/yyc/code/AgentMeter",
                rawTitle: "✳ Fix Ghostty jump - Claude Code",
                isFocusedInActiveWindow: true,
                screenTail: "⏺ Bash(swift build)\nDo you want to run this command?\n❯ 1. Yes, allow\n  2. Always\n  3. No, cancel (Esc)"
            ),
            GhosttyTerminalEntry(
                location: GhosttyPaneLocation(windowID: "win-1", tabID: "tab-2", terminalID: "term-tty", ttyPath: "/dev/ttys092"),
                pid: 42000,
                ttyName: "ttys092",
                cwdPath: "/Users/yyc/code/AgentMeter",
                rawTitle: "Codex CLI",
                isFocusedInActiveWindow: false,
                screenTail: "› Optimize scheduler\n· Working · ~/code/AgentMeter · Context 35% used"
            ),
            GhosttyTerminalEntry(
                location: GhosttyPaneLocation(windowID: "win-2", tabID: "tab-3", terminalID: "term-ppid", ttyPath: "/dev/ttys093"),
                pid: 42010,
                ttyName: "ttys093",
                cwdPath: "/Users/yyc/code/AgentMeter",
                rawTitle: "user@gpu-box:~/remote-repo - GitHub Copilot",
                isFocusedInActiveWindow: false,
                screenTail: "· Ready · ~/remote-repo · (18% used)",
                isSSH: true,
                sshPID: 42011,
                sshTarget: "gpu-box"
            ),
        ]

        let ppidMap: [Int32: Int32] = [
            42015: 42014,
            42014: 42013,
            42013: 42012,
            42012: 42010,
        ]

        let procByPID = ProcessEntry(pid: 42001, ppid: 40000, tty: nil, family: .claude, cpu: 1.0, cwdPath: "/Users/yyc/code/AgentMeter")
        let procByTTY = ProcessEntry(pid: 42005, ppid: 40000, tty: "ttys092", family: .codex, cpu: 4.2, cwdPath: "/Users/yyc/code/AgentMeter")
        let procByPPID = ProcessEntry(pid: 42015, ppid: 42014, tty: nil, family: .copilot, cpu: 0.2, cwdPath: "/Users/yyc/code/AgentMeter")

        let m1 = matchGhosttyEntry(for: procByPID, ppidMap: ppidMap, entries: entries)
        let m2 = matchGhosttyEntry(for: procByTTY, ppidMap: ppidMap, entries: entries)
        let m3 = matchGhosttyEntry(for: procByPPID, ppidMap: ppidMap, entries: entries)
        let matchOK = (m1?.location.terminalID == "term-pid")
            && (m2?.location.terminalID == "term-tty")
            && (m3?.location.terminalID == "term-ppid")

        let parseOK = (entries[0].detectedFamily == .claude && entries[0].inferredStatus == .needsInput && entries[0].cleanTitle == "Fix Ghostty jump")
            && (entries[1].detectedFamily == .codex && entries[1].inferredStatus == .working && entries[1].contextPercentUsed == 35)
            && (entries[2].detectedFamily == .copilot && entries[2].remoteCwdPath == "~/remote-repo" && entries[2].contextPercentUsed == 18)

        // Verify PTY fallback for Ghostty prompt write, approval write, and interrupt
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var ttyPathBuf = [CChar](repeating: 0, count: Int(PATH_MAX))
        var ptyFallbackOK = false
        if openpty(&masterFD, &slaveFD, &ttyPathBuf, nil, nil) == 0 {
            defer {
                if masterFD >= 0 { _ = Darwin.close(masterFD) }
                if slaveFD >= 0 { _ = Darwin.close(slaveFD) }
            }
            let flags = fcntl(masterFD, F_GETFL, 0)
            _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)
            let ptyPath = ttyPathBuf.withUnsafeBufferPointer { buf -> String in
                guard let base = buf.baseAddress else { return "" }
                return String(cString: base)
            }
            let ptyName = URL(fileURLWithPath: ptyPath).lastPathComponent
            let dummyItem = AgentActivityItem(
                id: "test-ghostty-pty",
                family: .claude,
                workspace: "AgentMeter",
                cwdPath: "/Users/yyc/code/AgentMeter",
                title: "PTY Fallback Test",
                status: .needsInput,
                updatedAt: Date(),
                pid: nil,
                tty: ptyName,
                rexPane: nil,
                ghosttyPane: GhosttyPaneLocation(
                    windowID: "nonexistent-win-999",
                    tabID: "nonexistent-tab-999",
                    terminalID: "nonexistent-term-999",
                    ttyPath: ptyPath
                ),
                terminalPreviewLines: [
                    "Do you want to run this command?",
                    "1. Yes, allow",
                    "2. Always",
                    "3. No, cancel",
                ]
            )

            func readAvailable(fd: Int32) -> Data {
                var out = Data()
                var buf = [UInt8](repeating: 0, count: 256)
                while true {
                    let n = Darwin.read(fd, &buf, buf.count)
                    if n > 0 {
                        out.append(contentsOf: buf.prefix(n))
                    } else {
                        break
                    }
                }
                return out
            }

            let promptOK = performPromptWrite(for: dummyItem, text: "ping")
            let promptBytes = readAvailable(fd: masterFD)
            let approveOK = performApprovalWrite(for: dummyItem, choice: .approvePrimary)
            let approveBytes = readAvailable(fd: masterFD)
            let interruptOK = performInterrupt(for: dummyItem)
            let interruptBytes = readAvailable(fd: masterFD)

            ptyFallbackOK = promptOK
                && approveOK
                && interruptOK
                && !promptBytes.isEmpty
                && !approveBytes.isEmpty
                && !interruptBytes.isEmpty
        }

        let start = ProcessInfo.processInfo.systemUptime
        let liveEntries = queryGhosttyTerminals()
        let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)

        print("TEST_GHOSTTY_MATCH | success=\(matchOK) | pid_match=\(m1?.location.terminalID ?? "-") | tty_match=\(m2?.location.terminalID ?? "-") | ppid_match=\(m3?.location.terminalID ?? "-")")
        print("TEST_GHOSTTY_PARSE | success=\(parseOK) | claude_status=\(entries[0].inferredStatus.rawValue) | codex_ctx=\(entries[1].contextPercentUsed ?? -1) | ssh_cwd=\(entries[2].remoteCwdPath ?? "-")")
        print("TEST_GHOSTTY_FALLBACK | success=\(ptyFallbackOK)")
        print("TEST_GHOSTTY_DISCOVERY | installed=\(isGhosttyAppInstalled()) | running=\(runningGhosttyApplication() != nil) | entries=\(liveEntries.count) | elapsed_ms=\(elapsedMs)")
        return matchOK && parseOK && ptyFallbackOK
    }
}
