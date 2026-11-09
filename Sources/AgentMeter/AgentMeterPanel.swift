import AppKit
import SwiftUI

private enum AgentListFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case completed

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.all, .english): "All"
        case (.all, .chinese): "全部"
        case (.active, .english): "Active"
        case (.active, .chinese): "活跃"
        case (.completed, .english): "Done"
        case (.completed, .chinese): "完成"
        }
    }
}

private enum QuickLaunchMode: String, CaseIterable, Identifiable {
    case newSession
    case history

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.newSession, .english): "New"
        case (.newSession, .chinese): "新建会话"
        case (.history, .english): "History"
        case (.history, .chinese): "历史记录"
        }
    }
}

struct AgentMeterPanel: View {
    @Bindable var model: AgentMeterModel
    @State private var showingSettings = false
    @State private var showingQuickLaunch = false
    @State private var quickLaunchMode: QuickLaunchMode = .newSession
    @State private var selectedFilter: AgentListFilter = .all
    @State private var historySearchQuery: String = ""
    @State private var selectedHistoryFamily: AgentFamily? = nil
    @State private var isHistorySearchFocused = false
    @State private var hoveredAgentID: String?
    @State private var hoveredPinID: String?
    @State private var hoveredCloseID: String?
    @State private var hoveredApprovePrimaryID: String?
    @State private var hoveredApproveSecondaryID: String?
    @State private var hoveredDenyID: String?
    @State private var hoveredInterruptID: String?
    @State private var hoveredReplyToggleID: String?
    @State private var hoveredReplyFieldID: String?
    @State private var hoveredQuickSendID: String?
    @State private var hoveredQueueEditID: String?
    @State private var hoveredQueueSendNowID: String?
    @State private var hoveredQueueRemoveID: String?
    @State private var hoveredWorkspacePath: String?
    @State private var hoveredWorkspaceAgentKey: String?
    @State private var hoveredHistoryID: String?
    @State private var hoveredHistoryDeleteID: String?
    @State private var hoveredHistoryConfirmDeleteID: String?
    @State private var hoveredHistoryCancelDeleteID: String?
    @State private var confirmingHistoryDeleteID: String?
    @State private var selectedAgentID: String?
    @State private var selectedHistoryID: String?
    @State private var selectedWorkspacePath: String?
    @State private var isKeyboardNavigationActive = false
    @State private var scrollTargetID: String?
    @State private var replyDrafts: [String: String] = [:]
    @State private var expandedReplyAgentID: String?
    @State private var focusedReplyAgentID: String?
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var filterNamespace
    @Namespace private var quickLaunchModeNamespace
    @Namespace private var historyFamilyFilterNamespace

    private var filteredActivities: [AgentActivityItem] {
        activities(for: selectedFilter)
    }

    private func activities(for filter: AgentListFilter) -> [AgentActivityItem] {
        switch filter {
        case .all:
            return model.agentActivities
        case .active:
            return model.agentActivities.filter { $0.status == .working || $0.status == .needsInput }
        case .completed:
            return model.agentActivities.filter { $0.status == .completed }
        }
    }

    var body: some View {
        let dark = (model.appearanceMode.colorScheme ?? systemColorScheme) == .dark

        VStack(alignment: .leading, spacing: 0) {
            header(dark: dark)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(FlatPalette.chromeBackground(dark: dark))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(FlatPalette.hairlineBorder(dark: dark))
                        .frame(height: 1)
                }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if showingSettings {
                            AgentMeterSettings(model: model)
                                .transition(.opacity)
                        } else if showingQuickLaunch {
                            quickLaunchSection(dark: dark)
                                .transition(.opacity)
                        } else {
                            agentDynamicSection(dark: dark)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                    .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22), value: model.agentActivities)
                    .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.20), value: selectedFilter)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.always)
                .defaultScrollAnchor(.top)
                .onChange(of: scrollTargetID) { _, targetID in
                    guard let targetID else { return }
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16)) {
                        scrollProxy.scrollTo(targetID, anchor: nil)
                    }
                }
            }

            footer(dark: dark)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(FlatPalette.chromeBackground(dark: dark))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(FlatPalette.hairlineBorder(dark: dark))
                        .frame(height: 1)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(FlatPanelSurface())
        .tint(FlatPalette.blue)
        .background(
            PanelWindowMask(
                appearanceMode: model.appearanceMode,
                onVisibilityChange: { visible in
                    resetHoverAndKeyboardNavigation()
                    if visible {
                        model.panelDidOpen()
                        focusedReplyAgentID = nil
                        isHistorySearchFocused = false
                        ensureValidKeyboardSelection()
                    } else {
                        focusedReplyAgentID = nil
                        expandedReplyAgentID = nil
                        isHistorySearchFocused = false
                        model.panelDidClose()
                    }
                },
                onKeyCommand: { cmd in
                    handleKeyNavigation(cmd)
                }
            )
        )
        .onChange(of: model.agentActivities) { _, _ in
            ensureValidKeyboardSelection()
        }
        .onChange(of: selectedFilter) { _, _ in
            ensureValidKeyboardSelection(forceFirst: true)
        }
        .environment(\.colorScheme, model.appearanceMode.colorScheme ?? systemColorScheme)
    }

    private func resetHoverAndKeyboardNavigation() {
        isKeyboardNavigationActive = false
        hoveredAgentID = nil
        hoveredPinID = nil
        hoveredCloseID = nil
        hoveredApprovePrimaryID = nil
        hoveredApproveSecondaryID = nil
        hoveredDenyID = nil
        hoveredInterruptID = nil
        hoveredReplyToggleID = nil
        hoveredReplyFieldID = nil
        hoveredQuickSendID = nil
        hoveredQueueEditID = nil
        hoveredQueueSendNowID = nil
        hoveredQueueRemoveID = nil
        hoveredWorkspacePath = nil
        hoveredWorkspaceAgentKey = nil
        hoveredHistoryID = nil
        hoveredHistoryDeleteID = nil
        hoveredHistoryConfirmDeleteID = nil
        hoveredHistoryCancelDeleteID = nil
    }

    private func ensureValidKeyboardSelection(forceFirst: Bool = false) {
        if showingQuickLaunch {
            if quickLaunchMode == .history {
                let items = filteredHistoricalSessions
                if forceFirst || selectedHistoryID == nil || !items.contains(where: { $0.id == selectedHistoryID }) {
                    selectedHistoryID = items.first?.id
                }
            } else {
                let items = model.recentLaunchWorkspaces
                if forceFirst || selectedWorkspacePath == nil || !items.contains(where: { $0.id == selectedWorkspacePath }) {
                    selectedWorkspacePath = items.first?.id
                }
            }
        } else if !showingSettings {
            let items = filteredActivities
            if forceFirst || selectedAgentID == nil || !items.contains(where: { $0.id == selectedAgentID }) {
                selectedAgentID = items.first?.id
            }
        }
    }

    private func handleKeyNavigation(_ cmd: PanelKeyNavigationCommand) -> Bool {
        if showingSettings {
            if cmd == .escape {
                resetHoverAndKeyboardNavigation()
                withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.20)) {
                    showingSettings = false
                }
                return true
            }
            return false
        }

        if showingQuickLaunch {
            if quickLaunchMode == .history {
                let items = filteredHistoricalSessions
                switch cmd {
                case .moveDown, .moveUp:
                    let wasKeyboardActive = isKeyboardNavigationActive
                    isKeyboardNavigationActive = true
                    isHistorySearchFocused = false
                    confirmingHistoryDeleteID = nil
                    guard !items.isEmpty else { return true }
                    let nextIdx: Int
                    if !wasKeyboardActive, hoveredHistoryID == nil {
                        nextIdx = cmd == .moveDown ? 0 : items.count - 1
                    } else if let currentID = (wasKeyboardActive ? selectedHistoryID : hoveredHistoryID) ?? selectedHistoryID,
                              let idx = items.firstIndex(where: { $0.id == currentID }) {
                        nextIdx = cmd == .moveDown
                            ? (idx + 1) % items.count
                            : (idx - 1 + items.count) % items.count
                    } else {
                        nextIdx = cmd == .moveDown ? 0 : items.count - 1
                    }
                    let nextID = items[nextIdx].id
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.15)) {
                        selectedHistoryID = nextID
                        scrollTargetID = nextID
                    }
                    return true

                case .moveLeft, .moveRight:
                    isKeyboardNavigationActive = true
                    isHistorySearchFocused = false
                    confirmingHistoryDeleteID = nil
                    let availableFamilies: [AgentFamily?] = [nil] + AgentFamily.allCases.filter { fam in
                        model.historicalSessions.contains { $0.family == fam }
                    }
                    guard availableFamilies.count > 1 else { return true }
                    let currentIdx = availableFamilies.firstIndex(where: { $0 == selectedHistoryFamily }) ?? 0
                    let nextIdx = cmd == .moveRight
                        ? (currentIdx + 1) % availableFamilies.count
                        : (currentIdx - 1 + availableFamilies.count) % availableFamilies.count
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                        selectedHistoryFamily = availableFamilies[nextIdx]
                    }
                    DispatchQueue.main.async {
                        ensureValidKeyboardSelection(forceFirst: true)
                    }
                    return true

                case .confirmSelection:
                    let targetID = (isKeyboardNavigationActive ? selectedHistoryID : nil) ?? hoveredHistoryID ?? selectedHistoryID ?? items.first?.id
                    guard let targetID, let item = items.first(where: { $0.id == targetID }) else { return false }
                    if confirmingHistoryDeleteID == item.id {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            confirmingHistoryDeleteID = nil
                            model.deleteHistoricalSession(item)
                        }
                    } else {
                        confirmingHistoryDeleteID = nil
                        isHistorySearchFocused = false
                        resetHoverAndKeyboardNavigation()
                        showingQuickLaunch = false
                        model.resumeOrFocusHistoricalSession(item)
                    }
                    return true

                case .openInlineReply:
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16)) {
                        isHistorySearchFocused = true
                    }
                    return true

                case .togglePiP:
                    return false

                case .escape:
                    if confirmingHistoryDeleteID != nil {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16)) {
                            confirmingHistoryDeleteID = nil
                        }
                        return true
                    }
                    if isHistorySearchFocused {
                        isHistorySearchFocused = false
                        return true
                    }
                    resetHoverAndKeyboardNavigation()
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.20)) {
                        showingQuickLaunch = false
                    }
                    return true
                }
            } else {
                // Quick Launch (.newSession) mode
                let workspaces = model.recentLaunchWorkspaces
                switch cmd {
                case .moveDown, .moveUp:
                    let wasKeyboardActive = isKeyboardNavigationActive
                    isKeyboardNavigationActive = true
                    guard !workspaces.isEmpty else { return true }
                    let nextIdx: Int
                    if !wasKeyboardActive, hoveredWorkspacePath == nil {
                        nextIdx = cmd == .moveDown ? 0 : workspaces.count - 1
                    } else if let currentID = (wasKeyboardActive ? selectedWorkspacePath : hoveredWorkspacePath) ?? selectedWorkspacePath,
                              let idx = workspaces.firstIndex(where: { $0.id == currentID }) {
                        nextIdx = cmd == .moveDown
                            ? (idx + 1) % workspaces.count
                            : (idx - 1 + workspaces.count) % workspaces.count
                    } else {
                        nextIdx = cmd == .moveDown ? 0 : workspaces.count - 1
                    }
                    let nextID = workspaces[nextIdx].id
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.15)) {
                        selectedWorkspacePath = nextID
                        scrollTargetID = nextID
                    }
                    return true

                case .moveLeft, .moveRight:
                    isKeyboardNavigationActive = true
                    let families = AgentFamily.allCases
                    let currentIdx = families.firstIndex(of: model.preferredLaunchFamily) ?? 0
                    let nextIdx = cmd == .moveRight
                        ? (currentIdx + 1) % families.count
                        : (currentIdx - 1 + families.count) % families.count
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                        model.preferredLaunchFamily = families[nextIdx]
                    }
                    return true

                case .confirmSelection:
                    let targetID = (isKeyboardNavigationActive ? selectedWorkspacePath : nil) ?? hoveredWorkspacePath ?? selectedWorkspacePath ?? workspaces.first?.id
                    guard let targetID, let ws = workspaces.first(where: { $0.id == targetID }) else { return false }
                    resetHoverAndKeyboardNavigation()
                    showingQuickLaunch = false
                    model.launchWorkspaceSession(family: model.preferredLaunchFamily, workspace: ws)
                    return true

                case .openInlineReply, .togglePiP:
                    return false

                case .escape:
                    resetHoverAndKeyboardNavigation()
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.20)) {
                        showingQuickLaunch = false
                    }
                    return true
                }
            }
        }

        // Main Agent Activity List View
        let items = filteredActivities
        switch cmd {
        case .moveDown, .moveUp:
            let wasKeyboardActive = isKeyboardNavigationActive
            isKeyboardNavigationActive = true
            focusedReplyAgentID = nil
            expandedReplyAgentID = nil
            guard !items.isEmpty else { return true }
            let nextIdx: Int
            if !wasKeyboardActive, hoveredAgentID == nil {
                nextIdx = cmd == .moveDown ? 0 : items.count - 1
            } else if let currentID = (wasKeyboardActive ? selectedAgentID : hoveredAgentID) ?? selectedAgentID,
                      let idx = items.firstIndex(where: { $0.id == currentID }) {
                nextIdx = cmd == .moveDown
                    ? (idx + 1) % items.count
                    : (idx - 1 + items.count) % items.count
            } else {
                nextIdx = cmd == .moveDown ? 0 : items.count - 1
            }
            let nextID = items[nextIdx].id
            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.15)) {
                selectedAgentID = nextID
                scrollTargetID = nextID
            }
            return true

        case .moveLeft, .moveRight:
            isKeyboardNavigationActive = true
            focusedReplyAgentID = nil
            expandedReplyAgentID = nil
            let allFilters = AgentListFilter.allCases
            let currentIdx = allFilters.firstIndex(of: selectedFilter) ?? 0
            let nextIdx = cmd == .moveRight
                ? (currentIdx + 1) % allFilters.count
                : (currentIdx - 1 + allFilters.count) % allFilters.count
            let nextFilter = allFilters[nextIdx]
            let nextItems = activities(for: nextFilter)
            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                selectedFilter = nextFilter
                selectedAgentID = nextItems.first?.id
                scrollTargetID = nextItems.first?.id
            }
            return true

        case .confirmSelection:
            let targetID = (isKeyboardNavigationActive ? selectedAgentID : nil) ?? hoveredAgentID ?? selectedAgentID ?? items.first?.id
            guard let targetID, let item = items.first(where: { $0.id == targetID }) else { return false }
            if item.status == .needsInput {
                withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                    model.respondToPermission(item, choice: .approvePrimary)
                }
            } else {
                model.jumpToAgentSession(item)
            }
            return true

        case .openInlineReply:
            let targetID = (isKeyboardNavigationActive ? selectedAgentID : nil) ?? hoveredAgentID ?? selectedAgentID ?? items.first?.id
            guard let targetID, let item = items.first(where: { $0.id == targetID }) else { return false }
            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                selectedAgentID = item.id
                expandedReplyAgentID = item.id
                focusedReplyAgentID = item.id
                scrollTargetID = item.id
            }
            return true

        case .togglePiP:
            let targetID = (isKeyboardNavigationActive ? selectedAgentID : nil) ?? hoveredAgentID ?? selectedAgentID ?? items.first?.id
            guard let targetID, let item = items.first(where: { $0.id == targetID }) else { return false }
            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                model.togglePiPSession(item)
            }
            return true

        case .escape:
            if focusedReplyAgentID != nil || expandedReplyAgentID != nil {
                withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16)) {
                    focusedReplyAgentID = nil
                    expandedReplyAgentID = nil
                }
                return true
            }
            return false
        }
    }

    private func header(dark: Bool) -> some View {
        let en = model.language == .english
        let workingCount = model.activeAgentWorkingCount
        return HStack(alignment: .center, spacing: 8) {
            if showingSettings {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(FlatPalette.trackBackground(dark: dark))
                    )
            } else if showingQuickLaunch {
                Image(systemName: quickLaunchMode == .newSession ? "plus.rectangle.on.rectangle" : "clock.arrow.circlepath")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(FlatPalette.trackBackground(dark: dark))
                    )
            } else {
                AgentMeterBrandEmblem(dark: dark)
                    .frame(width: 26, height: 26)
            }

            if showingSettings {
                Text(en ? "Settings" : "设置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
            } else if showingQuickLaunch {
                quickLaunchModeSegmentedControl(dark: dark)
            } else {
                HStack(spacing: 8) {
                    Text("Agent Meter")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                    if model.activeAgentNeedsInputCount > 0 {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(FlatPalette.amberAlertForeground(dark: dark))
                                .frame(width: 6, height: 6)
                            Text(en ? "\(model.activeAgentNeedsInputCount) Confirm" : "\(model.activeAgentNeedsInputCount) 待确认")
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(FlatPalette.amberAlertForeground(dark: dark))
                        .padding(.leading, 7)
                        .padding(.trailing, 8)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(FlatPalette.amberAlertBackground(dark: dark))
                        )
                    } else if workingCount > 0 {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(FlatPalette.accentText(dark: dark))
                                .frame(width: 6, height: 6)
                            Text(en ? "\(workingCount) Running" : "\(workingCount) 运行中")
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(FlatPalette.accentText(dark: dark))
                        .padding(.leading, 7)
                        .padding(.trailing, 8)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(FlatPalette.accentSoftBackground(dark: dark))
                        )
                    } else if !model.agentActivities.isEmpty {
                        Text(en ? "\(model.agentActivities.count) Online" : "\(model.agentActivities.count) 在线")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(
                                Capsule().fill(FlatPalette.trackBackground(dark: dark))
                            )
                    }
                }
            }

            Spacer(minLength: 0)

            if showingSettings || showingQuickLaunch {
                FlatCapsuleButton(title: en ? "Back" : "返回", compact: true) {
                    resetHoverAndKeyboardNavigation()
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                        showingSettings = false
                        showingQuickLaunch = false
                        isHistorySearchFocused = false
                    }
                }
            } else {
                HStack(spacing: 6) {
                    FlatIconButton(icon: "plus", size: 26, iconSize: 12.5, tooltip: en ? "New Agent Session" : "快速新建 Agent 会话") {
                        resetHoverAndKeyboardNavigation()
                        quickLaunchMode = .newSession
                        model.refreshLaunchWorkspaces()
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                            showingQuickLaunch = true
                        }
                    }

                    FlatIconButton(icon: "clock.arrow.circlepath", size: 26, iconSize: 12.5, tooltip: en ? "Resume History Session" : "恢复历史 Agent 会话") {
                        resetHoverAndKeyboardNavigation()
                        quickLaunchMode = .history
                        model.refreshHistoricalSessions()
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                            showingQuickLaunch = true
                        }
                    }

                    FlatIconButton(icon: "gearshape", size: 26, iconSize: 12.5, rotatesOnHover: true, tooltip: en ? "Settings" : "设置") {
                        resetHoverAndKeyboardNavigation()
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                            showingSettings = true
                        }
                    }
                }
            }
        }
    }

    private func quickLaunchModeSegmentedControl(dark: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(QuickLaunchMode.allCases) { mode in
                quickLaunchModePill(mode: mode, dark: dark)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FlatPalette.trackBackground(dark: dark))
        )
    }

    private func quickLaunchModePill(mode: QuickLaunchMode, dark: Bool) -> some View {
        let isSelected = quickLaunchMode == mode
        let count = mode == .history ? model.historicalSessions.count : 0
        let thumbShape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return HStack(spacing: 4) {
            Text(mode.title(in: model.language))
                .font(.system(size: 11.5, weight: .medium))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .opacity(isSelected ? 0.9 : 0.7)
            }
        }
        .foregroundStyle(isSelected ? FlatPalette.inkPrimary(dark: dark) : FlatPalette.inkSecondary(dark: dark))
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background {
            if isSelected {
                thumbShape
                    .fill(FlatPalette.selectedPillBackground(dark: dark))
                    .overlay(
                        thumbShape
                            .strokeBorder(
                                dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: .black.opacity(dark ? 0.35 : 0.08), radius: 1.5, x: 0, y: 1)
                    .matchedGeometryEffect(id: "quickLaunchModePill", in: quickLaunchModeNamespace)
            }
        }
        .contentShape(thumbShape)
        .overlay {
            PointingHandCursorOverlay(
                onClick: {
                    resetHoverAndKeyboardNavigation()
                    if mode == .history {
                        model.refreshHistoricalSessions()
                    } else {
                        isHistorySearchFocused = false
                        model.refreshLaunchWorkspaces()
                    }
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.20)) {
                        quickLaunchMode = mode
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func agentDynamicSection(dark: Bool) -> some View {
        let en = model.language == .english
        let unreadCount = model.unreadCompletionCount
        let now = Date()

        VStack(alignment: .leading, spacing: 10) {
            // Section toolbar: Sessions label + Stageshow Segmented Control + mark-all-read action
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(FlatPalette.accent(dark: dark))
                        .frame(width: 6, height: 6)
                    Text(en ? "Sessions" : "会话列表")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                }

                Spacer(minLength: 4)

                if unreadCount > 0 {
                    HStack(spacing: 3.5) {
                        Circle()
                            .fill(FlatPalette.dangerInterruptForeground(dark: dark))
                            .frame(width: 5, height: 5)
                        Text(en ? "Read" : "已读")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(
                        Capsule()
                            .fill(FlatPalette.trackBackground(dark: dark))
                    )
                    .contentShape(Capsule())
                    .overlay {
                        PointingHandCursorOverlay(
                            tooltip: en ? "Clear all unread completion badges" : "清除所有未读完成提醒",
                            onClick: {
                                withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                    model.markAllAsRead()
                                }
                            }
                        )
                    }
                }

                if model.agentActivities.count > 1 {
                    filterSegmentedControl(dark: dark)
                }
            }
            .padding(.leading, 2)

            if model.agentActivities.isEmpty {
                let targetHostName = model.resolvedLaunchTerminalHost().displayName
                emptyStateCard(
                    icon: "terminal",
                    title: en ? "No active CLI Agent sessions detected" : "当前未检测到正在运行的 CLI Agent",
                    subtitle: en
                        ? "Automatically discovers Codex, Claude, Copilot & Antigravity sessions in \(targetHostName)"
                        : "支持自动发现本机及 \(targetHostName) SSH 中的 Codex、Claude、Copilot 与 Antigravity 会话"
                )
            } else if filteredActivities.isEmpty {
                emptyStateCard(
                    icon: "line.3.horizontal.decrease.circle",
                    title: selectedFilter == .active
                        ? (en ? "No running or pending sessions" : "当前没有正在运行或待确认的会话")
                        : (en ? "No completed sessions yet" : "当前没有已完成的会话记录"),
                    subtitle: en
                        ? "Switch to \"All\" to view \(model.agentActivities.count) online session(s)"
                        : "切换到「全部」查看其余 \(model.agentActivities.count) 个在线会话"
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredActivities) { item in
                        agentActivityRow(item, dark: dark, now: now)
                    }
                }
            }
        }
    }

    private func filterSegmentedControl(dark: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(AgentListFilter.allCases) { filter in
                filterPillItem(filter: filter, dark: dark)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FlatPalette.trackBackground(dark: dark))
        )
    }

    private func filterPillItem(filter: AgentListFilter, dark: Bool) -> some View {
        let isSelected = selectedFilter == filter
        let count = filterCount(for: filter)
        let thumbShape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return HStack(spacing: 3.5) {
            Text(filter.title(in: model.language))
                .font(.system(size: 11.5, weight: .medium))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .opacity(isSelected ? 0.92 : 0.72)
            }
        }
        .foregroundStyle(isSelected ? FlatPalette.inkPrimary(dark: dark) : FlatPalette.inkSecondary(dark: dark))
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background {
            if isSelected {
                thumbShape
                    .fill(FlatPalette.selectedPillBackground(dark: dark))
                    .overlay(
                        thumbShape
                            .strokeBorder(
                                dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: .black.opacity(dark ? 0.35 : 0.08), radius: 1.5, x: 0, y: 1)
                    .matchedGeometryEffect(id: "filterPill", in: filterNamespace)
            }
        }
        .contentShape(thumbShape)
        .overlay {
            PointingHandCursorOverlay(
                onClick: {
                    resetHoverAndKeyboardNavigation()
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                        selectedFilter = filter
                    }
                }
            )
        }
    }

    private func filterCount(for filter: AgentListFilter) -> Int {
        switch filter {
        case .all:
            return model.agentActivities.count
        case .active:
            return model.agentActivities.filter { $0.status == .working || $0.status == .needsInput }.count
        case .completed:
            return model.agentActivities.filter { $0.status == .completed }.count
        }
    }

    private func emptyStateCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .modifier(FlatCardSurface(cornerRadius: 10))
    }

    private func shouldShowExtendedPreview(for item: AgentActivityItem) -> Bool {
        return item.status == .needsInput || item.status == .working
    }

    private func agentActivityRow(_ item: AgentActivityItem, dark: Bool, now: Date) -> some View {
        let isPinHovered = hoveredPinID == item.id
        let isCloseHovered = hoveredCloseID == item.id
        let isApprove1Hovered = hoveredApprovePrimaryID == item.id
        let isApprove2Hovered = hoveredApproveSecondaryID == item.id
        let isDenyHovered = hoveredDenyID == item.id
        let isInterruptHovered = hoveredInterruptID == item.id
        let isReplyToggleHovered = hoveredReplyToggleID == item.id
        let isReplyFieldHovered = hoveredReplyFieldID == item.id
        let isQuickSendHovered = hoveredQuickSendID == item.id
        let isQueueEditHovered = hoveredQueueEditID == item.id
        let isQueueSendNowHovered = hoveredQueueSendNowID == item.id
        let isQueueRemoveHovered = hoveredQueueRemoveID == item.id
        let isHovered = hoveredAgentID == item.id
            || isPinHovered
            || isCloseHovered
            || isApprove1Hovered
            || isApprove2Hovered
            || isDenyHovered
            || isInterruptHovered
            || isReplyToggleHovered
            || isReplyFieldHovered
            || isQuickSendHovered
            || isQueueEditHovered
            || isQueueSendNowHovered
            || isQueueRemoveHovered
        let isSelected = isKeyboardNavigationActive && selectedAgentID == item.id
        let isHighlighted = isHovered || isSelected
        let familyColor = item.family.accentColor(dark: dark)
        let statusColor = agentStatusColor(item.status, dark: dark)
        let isExpanded = shouldShowExtendedPreview(for: item)
        let hasDraft = !(replyDrafts[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let isReplyFocused = focusedReplyAgentID == item.id
        let showInlineReply = expandedReplyAgentID == item.id || isReplyFocused || hasDraft
        let queuedPrompts = model.queuedPrompts(for: item)
        let hasQueuedPrompts = !queuedPrompts.isEmpty
        let isLongRunning = item.isLongRunningWorking(now: now)
        let showWorkingControlBar = item.status == .working && isLongRunning
        let supportsFooterHoverActions = item.status != .needsInput && !showWorkingControlBar
        let showFooterHoverActions = supportsFooterHoverActions && isHovered
        let cacheRemaining = item.cacheWarmRemainingSeconds(now: now)
        let hasTaskProgress = item.taskProgress.map { !$0.isEmpty } ?? false
        let hasTelemetryFooter = item.gitDiff != nil || cacheRemaining != nil || hasTaskProgress || item.contextPercentUsed != nil || supportsFooterHoverActions
        let hasPreview = !item.terminalPreviewLines.isEmpty || hasQueuedPrompts || showInlineReply || hasTelemetryFooter

        let cardShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let isLead = item.status == .needsInput || isLongRunning
        let footerBottomPadding: CGFloat = 18
            + (hasQueuedPrompts ? 33 : 0)
            + (showInlineReply ? (hasQueuedPrompts ? 34 : 27) : 0)

        return VStack(alignment: .leading, spacing: 8) {
            agentRowHeader(
                item: item,
                isHovered: isHighlighted,
                familyColor: familyColor,
                statusColor: statusColor,
                dark: dark,
                now: now
            )

            // Live Micro Terminal Preview Box (100% full width, constant line count for 0px hover layout shift)
            if hasPreview {
                miniTerminalPreview(
                    item: item,
                    expanded: isExpanded,
                    hasQueuedPrompts: hasQueuedPrompts,
                    showInlineReply: showInlineReply,
                    hasTelemetryFooter: hasTelemetryFooter,
                    showFooterHoverActions: showFooterHoverActions,
                    cacheRemaining: cacheRemaining,
                    familyColor: familyColor,
                    statusColor: statusColor,
                    dark: dark
                )
            }

            // Inline Permission Approval Bar when the session is waiting for confirmation
            if item.status == .needsInput {
                inlineApprovalReserveBar(dark: dark)
            } else if showWorkingControlBar {
                inlineWorkingReserveBar(item: item, isLongRunning: isLongRunning, dark: dark)
            }
        }
        .padding(10)
        .contentShape(cardShape)
        // Full-card tracking region (never shrinks when expanded, so moving mouse down into the prompt never drops hover)
        .overlay {
            PointingHandCursorOverlay(
                tooltip: cardHoverTooltip(for: item),
                onHoverChange: { hovering in
                    if hovering {
                        isKeyboardNavigationActive = false
                    }
                    hoveredAgentID = hovering ? item.id : (hoveredAgentID == item.id ? nil : hoveredAgentID)
                },
                onClick: {
                    selectedAgentID = item.id
                    model.jumpToAgentSession(item)
                }
            )
        }
        .overlay(alignment: .topTrailing) {
            let isPinned = model.isSessionPinnedInPiP(item)
            if isHovered || isPinned {
                HStack(spacing: 4) {
                    pinPiPSessionButton(
                        item: item,
                        isPinned: isPinned,
                        isPinHovered: isPinHovered,
                        dark: dark
                    )
                    if isHovered {
                        closeSessionButton(item: item, isCloseHovered: isCloseHovered, isRowHovered: isHovered, dark: dark)
                    }
                }
                .offset(x: 5, y: -5)
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
        }
        .overlay(alignment: .bottom) {
            if hasQueuedPrompts || showInlineReply {
                VStack(alignment: .leading, spacing: 13) {
                    if hasQueuedPrompts {
                        inlineQueuedPromptBar(
                            item: item,
                            queuedPrompts: queuedPrompts,
                            isQueueEditHovered: isQueueEditHovered,
                            isQueueSendNowHovered: isQueueSendNowHovered,
                            isQueueRemoveHovered: isQueueRemoveHovered,
                            familyColor: familyColor,
                            dark: dark
                        )
                        .frame(height: 20)
                    }
                    if showInlineReply {
                        inlineTerminalReplyPromptBar(
                            item: item,
                            isQuickSendHovered: isQuickSendHovered,
                            familyColor: familyColor,
                            dark: dark
                        )
                        .frame(height: 21)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, (item.status == .needsInput || showWorkingControlBar) ? 46 : 18)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if item.status == .needsInput {
                inlineApprovalActionButtons(
                    item: item,
                    isApprove1Hovered: isApprove1Hovered,
                    isApprove2Hovered: isApprove2Hovered,
                    isDenyHovered: isDenyHovered,
                    isReplyToggleHovered: isReplyToggleHovered,
                    showInlineReply: showInlineReply,
                    dark: dark
                )
                .padding(.bottom, 10)
                .padding(.trailing, 10)
            } else if showWorkingControlBar {
                inlineWorkingActionButtons(
                    item: item,
                    dark: dark,
                    showInlineReply: showInlineReply
                )
                .padding(.bottom, 10)
                .padding(.trailing, 10)
            } else if showFooterHoverActions {
                inlineFooterHoverActionButtons(
                    item: item,
                    dark: dark,
                    showInlineReply: showInlineReply
                )
                .padding(.trailing, 20)
                .padding(.bottom, footerBottomPadding)
            }
        }
        .background {
            cardShape
                .fill(FlatPalette.elevatedRowBackground(dark: dark, hovered: isHighlighted))
                .overlay(alignment: .top) {
                    if dark {
                        Rectangle()
                            .fill(isHighlighted ? familyColor.opacity(0.32) : Color.white.opacity(isLead ? 0.08 : 0.05))
                            .frame(height: 1)
                            .padding(.horizontal, 8)
                    }
                }
                .overlay {
                    cardShape
                        .strokeBorder(
                            rowBorderColor(
                                for: item,
                                isLead: isLead,
                                isHovered: isHovered,
                                isSelected: isSelected,
                                familyColor: familyColor,
                                dark: dark
                            ),
                            lineWidth: (isHighlighted || isLead) ? 1.25 : 1.0
                        )
                }
                .shadow(
                    color: .black.opacity(dark ? 0.16 : 0.04),
                    radius: 1.5,
                    x: 0,
                    y: 1
                )
        }
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16), value: isHighlighted)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18), value: isExpanded)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18), value: hasQueuedPrompts)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18), value: showInlineReply)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18), value: showWorkingControlBar)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.14), value: isCloseHovered)
        .help(item.title)
        .id(item.id)
    }

    private func cardHoverTooltip(for item: AgentActivityItem) -> String {
        let en = model.language == .english
        let base = en
            ? "Click to focus \(item.terminalHost.displayName) session"
            : "点击跳转到 \(item.terminalHost.displayName) 会话"
        guard let progress = item.taskProgress, !progress.isEmpty else {
            return base
        }
        return base + "\n\n" + taskProgressTooltipText(progress: progress, en: en)
    }

    private func taskProgressTooltipText(progress: AgentTaskProgress, en: Bool) -> String {
        var headerParts: [String] = []
        if progress.totalCount > 0 {
            headerParts.append(
                en
                    ? "Tasks \(progress.completedCount)/\(progress.totalCount)"
                    : "任务进度 \(progress.completedCount)/\(progress.totalCount)"
            )
        }
        if progress.activeSubagentCount > 0 {
            headerParts.append(
                en
                    ? "\(progress.activeSubagentCount) active subagent\(progress.activeSubagentCount > 1 ? "s" : "")"
                    : "\(progress.activeSubagentCount) 个活跃子任务"
            )
        }
        var lines: [String] = []
        if !headerParts.isEmpty {
            lines.append(headerParts.joined(separator: " · "))
        }
        for todo in progress.items.prefix(8) {
            let mark: String = {
                switch todo.status {
                case .completed: return "✓"
                case .inProgress: return "▶"
                case .pending: return "○"
                }
            }()
            lines.append("\(mark) \(todo.title)")
        }
        return lines.joined(separator: "\n")
    }

    private func agentRowHeader(
        item: AgentActivityItem,
        isHovered: Bool,
        familyColor: Color,
        statusColor: Color,
        dark: Bool,
        now: Date
    ) -> some View {
        let en = model.language == .english
        let isLongRunning = item.isLongRunningWorking(now: now)
        let badgeState: AgentVectorBadgeState = {
            switch item.status {
            case .needsInput:
                return .needsInput
            case .working:
                return isLongRunning ? .stuck : .working
            case .completed:
                return .completed
            case .idle:
                return .idle
            }
        }()

        let statusLabel: String = {
            switch badgeState {
            case .needsInput: return en ? "Confirm" : "待确认"
            case .working: return en ? "Running" : "运行中"
            case .stuck: return en ? "Stalled" : "长时卡住"
            case .completed: return en ? "Done" : "已完成"
            case .idle: return en ? "Idle" : "待命"
            }
        }()

        let elapsedText: String? = {
            guard item.status == .working,
                  item.updatedAt > Date(timeIntervalSince1970: 1000) else { return nil }
            let elapsed = max(0, Int(now.timeIntervalSince(item.updatedAt)))
            return formatLiveDuration(elapsed)
        }()

        let badgeTooltip: String = {
            if let elapsedText {
                return "\(statusLabel) · \(elapsedText)"
            }
            return statusLabel
        }()

        let phaseSeed = Double(abs(item.id.hashValue % 1000)) / 170.0

        return HStack(alignment: .top, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                AgentFamilyBadgeIcon(
                    family: item.family,
                    dark: dark,
                    highlighted: isHovered,
                    size: 28
                )
                .help(item.family.badgeTitle)

                if item.isUnreadCompletion {
                    UnreadCompletionBeacon(dark: dark)
                        .offset(x: 3, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Title + Pure Vector Animated Status Badge
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 5.5) {
                        if item.isFocusedInHost {
                            Circle()
                                .fill(FlatPalette.inkSecondary(dark: dark))
                                .frame(width: 5, height: 5)
                                .help(en ? "Focused terminal window" : "当前焦点终端窗口")
                        }
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 6)

                    AgentVectorStatusBadge(
                        state: badgeState,
                        dark: dark,
                        phaseOffset: phaseSeed
                    )
                    .help(badgeTooltip)
                    .accessibilityLabel(badgeTooltip)
                }

                // Row 2: Subtitle (100% full width for host, SSH/path, branch + worktree, and workspace conflict badge)
                HStack(alignment: .center, spacing: 6) {
                    subtitleRow(item: item, familyColor: familyColor)

                    Spacer(minLength: 0)
                }
                .frame(height: 18)
            }
        }
    }

    private func pinPiPSessionButton(
        item: AgentActivityItem,
        isPinned: Bool,
        isPinHovered: Bool,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        let accentFg = FlatPalette.accentText(dark: dark)
        let activeOrHovered = isPinned || isPinHovered
        let tip = isPinned
            ? (en ? "Unpin Picture-in-Picture window (P)" : "取消画中画盯盘 (P)")
            : (en ? "Pin card as floating Picture-in-Picture monitor (P)" : "将此会话钉为桌面画中画盯盘小窗 (P)")

        return Image(systemName: isPinned ? "pin.fill" : "pip.enter")
            .font(.system(size: isPinned ? 8.5 : 9.0, weight: .bold))
            .foregroundStyle(
                activeOrHovered
                    ? accentFg
                    : FlatPalette.inkSecondary(dark: dark)
            )
            .frame(width: 20, height: 20)
            .background {
                Circle()
                    .fill(
                        activeOrHovered
                            ? FlatPalette.accentSoftBackground(dark: dark)
                            : FlatPalette.cardBackground(dark: dark)
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(
                                activeOrHovered
                                    ? accentFg.opacity(0.45)
                                    : (dark ? Color.white.opacity(0.14) : Color.black.opacity(0.11)),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(dark ? 0.40 : 0.10), radius: 3, x: 0, y: 1)
            }
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: tip,
                    onHoverChange: { hovering in
                        if hovering {
                            isKeyboardNavigationActive = false
                        }
                        hoveredPinID = hovering ? item.id : (hoveredPinID == item.id ? nil : hoveredPinID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            model.togglePiPSession(item)
                        }
                    }
                )
            }
            .help(tip)
            .accessibilityLabel(tip)
    }

    private func closeSessionButton(
        item: AgentActivityItem,
        isCloseHovered: Bool,
        isRowHovered: Bool,
        dark: Bool
    ) -> some View {
        let dangerFg = FlatPalette.dangerInterruptForeground(dark: dark)
        return Image(systemName: "xmark")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(
                isCloseHovered
                    ? dangerFg
                    : FlatPalette.inkSecondary(dark: dark)
            )
            .frame(width: 20, height: 20)
            .background {
                Circle()
                    .fill(
                        isCloseHovered
                            ? FlatPalette.dangerInterruptBackground(dark: dark, hovered: true)
                            : FlatPalette.cardBackground(dark: dark)
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isCloseHovered
                                    ? dangerFg.opacity(0.42)
                                    : (dark ? Color.white.opacity(0.14) : Color.black.opacity(0.11)),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(dark ? 0.40 : 0.10), radius: 3, x: 0, y: 1)
            }
            .overlay {
                PointingHandCursorOverlay(
                    onHoverChange: { hovering in
                        if hovering {
                            isKeyboardNavigationActive = false
                        }
                        hoveredCloseID = hovering ? item.id : (hoveredCloseID == item.id ? nil : hoveredCloseID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.20)) {
                            model.closeAgentSession(item)
                        }
                    }
                )
            }
            .help(model.language == .english ? "Close this Agent session" : "关闭该 Agent 会话")
            .accessibilityLabel(model.language == .english ? "Close this Agent session" : "关闭该 Agent 会话")
    }

    @ViewBuilder
    private func subtitleRow(
        item: AgentActivityItem,
        familyColor: Color
    ) -> some View {
        let dark = (model.appearanceMode.colorScheme ?? systemColorScheme) == .dark
        let en = model.language == .english
        let displayPath: String = {
            if !item.cwdPath.isEmpty {
                return abbreviateHomePath(item.cwdPath)
            }
            if !item.workspace.isEmpty,
               item.workspace != "默认目录",
               item.workspace != "Default" {
                return abbreviateHomePath(item.workspace)
            }
            return "~"
        }()

        HStack(spacing: 5) {
            if item.terminalHost == .ghostty || item.rexPane != nil {
                let hostName = item.terminalHost.displayName
                Text(hostName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(FlatPalette.trackBackground(dark: dark))
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .help(en ? "Hosted in \(hostName) terminal" : "运行于 \(hostName) 终端")
            }

            if let sshTarget = item.sshTarget, !sshTarget.isEmpty {
                HStack(spacing: 3.5) {
                    Image(systemName: "network")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(FlatPalette.inkTertiary(dark: dark))
                    Text(sshTarget)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(FlatPalette.inkSecondary(dark: dark))

                if !item.cwdPath.isEmpty {
                    Text("·")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FlatPalette.inkTertiary(dark: dark))
                    Text(displayPath)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text(displayPath)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let branch = item.gitBranch, !branch.isEmpty {
                let branchColor = FlatPalette.terminalPath(dark: dark)
                Text("·")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FlatPalette.inkTertiary(dark: dark))

                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(branchColor)
                    Text(branch)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(branchColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if item.isGitWorktree {
                        Text("WT")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(FlatPalette.accentText(dark: dark))
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(FlatPalette.accentSoftBackground(dark: dark))
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .help(
                    item.isGitWorktree
                        ? (en ? "Isolated Git worktree · branch: \(branch)" : "独立 Git Worktree 工作区 · 分支：\(branch)")
                        : (en ? "Git branch: \(branch)" : "Git 分支：\(branch)")
                )
            }

            if item.hasWorkspaceCollision {
                let conflictFg = FlatPalette.conflictWarningForeground(dark: dark)
                let conflictBg = FlatPalette.conflictWarningBackground(dark: dark)
                Text(en ? "Conflict" : "目录冲突")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(conflictFg)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(
                        Capsule()
                            .fill(conflictBg)
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .help(
                        en
                            ? "\(item.collisionPeerCount + 1) active sessions share this checkout (\(displayPath)) — risk of concurrent write conflicts"
                            : "检测到 \(item.collisionPeerCount + 1) 个会话共用同一工作区目录（\(displayPath)），可能产生并发写冲突"
                    )
            }
        }
    }

    private func miniTerminalPreview(
        item: AgentActivityItem,
        expanded: Bool,
        hasQueuedPrompts: Bool,
        showInlineReply: Bool,
        hasTelemetryFooter: Bool,
        showFooterHoverActions: Bool,
        cacheRemaining: Int?,
        familyColor: Color,
        statusColor: Color,
        dark: Bool
    ) -> some View {
        let maxVisibleLines = item.status == .needsInput ? 7 : 3
        let lines = expanded
            ? Array(item.terminalPreviewLines.suffix(maxVisibleLines))
            : Array(item.terminalPreviewLines.suffix(1))

        return VStack(alignment: .leading, spacing: 6) {
            if !lines.isEmpty {
                previewLinesColumn(
                    item: item,
                    lines: lines,
                    familyColor: familyColor,
                    statusColor: statusColor,
                    dark: dark
                )
            }

            if hasTelemetryFooter {
                if !lines.isEmpty {
                    Rectangle()
                        .fill(FlatPalette.faintBorder(dark: dark))
                        .frame(height: 1)
                }
                terminalTelemetryFooter(
                    item: item,
                    cacheRemaining: cacheRemaining,
                    showHoverActions: showFooterHoverActions,
                    familyColor: familyColor,
                    dark: dark
                )
            }

            if hasQueuedPrompts {
                if !lines.isEmpty || hasTelemetryFooter {
                    Rectangle()
                        .fill(FlatPalette.faintBorder(dark: dark))
                        .frame(height: 1)
                }

                // Reserve space inside the terminal well; the interactive queued prompt overlay sits right on top
                Color.clear
                    .frame(height: 20)
            }

            if showInlineReply {
                if !lines.isEmpty || hasTelemetryFooter || hasQueuedPrompts {
                    Rectangle()
                        .fill(FlatPalette.faintBorder(dark: dark))
                        .frame(height: 1)
                }

                // Reserve space inside the terminal well; the interactive prompt overlay sits right on top
                Color.clear
                    .frame(height: 21)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FlatPalette.terminalWellBackground(dark: dark))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            focusedReplyAgentID == item.id
                                ? (dark ? Color.white.opacity(0.22) : Color.black.opacity(0.18))
                                : FlatPalette.hairlineBorder(dark: dark),
                            lineWidth: 1
                        )
                )
        )
    }

    private func inlineQueuedPromptBar(
        item: AgentActivityItem,
        queuedPrompts: [String],
        isQueueEditHovered: Bool,
        isQueueSendNowHovered: Bool,
        isQueueRemoveHovered: Bool,
        familyColor: Color,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        let firstPrompt = queuedPrompts.first ?? ""
        let extraCount = max(0, queuedPrompts.count - 1)
        let dangerFg = FlatPalette.dangerInterruptForeground(dark: dark)

        return HStack(alignment: .center, spacing: 6) {
            HStack(spacing: 3.5) {
                Image(systemName: "clock")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(en ? "Queued" : "已排队")
                    .font(.system(size: 9.5, weight: .semibold))
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundStyle(familyColor)
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(familyColor.opacity(dark ? 0.18 : 0.11))
            )
            .fixedSize(horizontal: true, vertical: false)

            Text(firstPrompt)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(isQueueEditHovered ? FlatPalette.inkPrimary(dark: dark) : FlatPalette.inkSecondary(dark: dark))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    PointingHandCursorOverlay(
                        tooltip: en
                            ? "Queued for when session becomes idle (click to edit)"
                            : "待当前任务完成后自动发送（点击修改）",
                        onHoverChange: { hovering in
                            if hovering {
                                isKeyboardNavigationActive = false
                            }
                            hoveredQueueEditID = hovering ? item.id : (hoveredQueueEditID == item.id ? nil : hoveredQueueEditID)
                        },
                        onClick: {
                            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                if let popped = model.popQueuedPromptForEditing(for: item, at: 0) {
                                    replyDrafts[item.id] = popped
                                    expandedReplyAgentID = item.id
                                    focusedReplyAgentID = item.id
                                }
                            }
                        }
                    )
                }

            HStack(spacing: 3) {
                Text(en ? "Now" : "立即")
                    .font(.system(size: 9.5, weight: .medium))
                Text("⏎")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(isQueueSendNowHovered ? familyColor : FlatPalette.inkSecondary(dark: dark))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(
                        isQueueSendNowHovered
                            ? familyColor.opacity(dark ? 0.22 : 0.13)
                            : (dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en ? "Send queued prompt immediately" : "立即发送排队中的指令",
                    onHoverChange: { hovering in
                        if hovering {
                            isKeyboardNavigationActive = false
                        }
                        hoveredQueueSendNowID = hovering ? item.id : (hoveredQueueSendNowID == item.id ? nil : hoveredQueueSendNowID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            hoveredQueueSendNowID = nil
                            model.dispatchNextQueuedPromptNow(item)
                        }
                    }
                )
            }

            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isQueueRemoveHovered ? dangerFg : FlatPalette.inkSecondary(dark: dark))
                .frame(width: 17, height: 17)
                .background(
                    Circle()
                        .fill(
                            isQueueRemoveHovered
                                ? FlatPalette.dangerInterruptBackground(dark: dark, hovered: true)
                                : (dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045))
                        )
                )
                .overlay {
                    PointingHandCursorOverlay(
                        tooltip: en ? "Cancel queued prompt" : "取消该条排队指令",
                        onHoverChange: { hovering in
                            if hovering {
                                isKeyboardNavigationActive = false
                            }
                            hoveredQueueRemoveID = hovering ? item.id : (hoveredQueueRemoveID == item.id ? nil : hoveredQueueRemoveID)
                        },
                        onClick: {
                            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                hoveredQueueRemoveID = nil
                                model.removeQueuedPrompt(for: item, at: 0)
                            }
                        }
                    )
                }
        }
    }

    private func inlineTerminalReplyPromptBar(
        item: AgentActivityItem,
        isQuickSendHovered: Bool,
        familyColor: Color,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        let hostName = item.terminalHost.displayName
        let isQueueMode = item.status == .working
        let draftBinding = Binding<String>(
            get: { replyDrafts[item.id] ?? "" },
            set: { replyDrafts[item.id] = $0 }
        )
        let currentDraft = (replyDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !currentDraft.isEmpty

        return HStack(alignment: .center, spacing: 6) {
            Text(isQueueMode ? "⏳" : "❯")
                .font(.system(size: isQueueMode ? 10 : 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(familyColor)
                .overlay {
                    PointingHandCursorOverlay(
                        onHoverChange: { hovering in
                            if hovering {
                                isKeyboardNavigationActive = false
                            }
                            hoveredReplyFieldID = hovering ? item.id : (hoveredReplyFieldID == item.id ? nil : hoveredReplyFieldID)
                        },
                        onClick: {
                            focusedReplyAgentID = item.id
                        }
                    )
                }

            InlinePromptTextField(
                text: draftBinding,
                placeholder: isQueueMode
                    ? (en ? "Queue next prompt for \(hostName)… (auto-sends when idle)" : "排队下一条指令至 \(hostName)…（空闲时自动发送）")
                    : (en ? "Reply to \(hostName)… (press /)" : "发送指令至 \(hostName)…（按 / 聚焦）"),
                dark: dark,
                requestFocus: focusedReplyAgentID == item.id,
                onHoverChange: { hovering in
                    if hovering {
                        isKeyboardNavigationActive = false
                    }
                    hoveredReplyFieldID = hovering ? item.id : (hoveredReplyFieldID == item.id ? nil : hoveredReplyFieldID)
                },
                onFocusChange: { focused in
                    if focused {
                        focusedReplyAgentID = item.id
                    } else if focusedReplyAgentID == item.id {
                        focusedReplyAgentID = nil
                    }
                },
                onSubmit: {
                    submitInlineReply(for: item)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: 20)

            HStack(spacing: 3) {
                Text(
                    isQueueMode
                        ? (en ? "Queue" : "排队")
                        : (en ? "Send" : "发送")
                )
                .font(.system(size: 9.5, weight: .semibold))
                Text("⏎")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(hasText || isQuickSendHovered ? familyColor : FlatPalette.inkSecondary(dark: dark))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                Capsule()
                    .fill(
                        hasText || isQuickSendHovered
                            ? familyColor.opacity(dark ? 0.22 : 0.13)
                            : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                hasText
                                    ? familyColor.opacity(dark ? 0.42 : 0.32)
                                    : FlatPalette.hairlineBorder(dark: dark),
                                lineWidth: 1
                            )
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: isQueueMode
                        ? (en ? "Queue prompt to auto-send when session finishes current turn (Enter)" : "加入队列，待当前轮次完成后自动发送（回车）")
                        : (en ? "Send message to \(hostName) session (Enter)" : "发送指令至 \(hostName) 会话（回车）"),
                    onHoverChange: { hovering in
                        if hovering {
                            isKeyboardNavigationActive = false
                        }
                        hoveredQuickSendID = hovering ? item.id : (hoveredQuickSendID == item.id ? nil : hoveredQuickSendID)
                    },
                    onClick: {
                        if hasText {
                            submitInlineReply(for: item)
                        } else {
                            focusedReplyAgentID = item.id
                        }
                    }
                )
            }
        }
    }

    private func submitInlineReply(for item: AgentActivityItem) {
        let text = (replyDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
            replyDrafts[item.id] = nil
            expandedReplyAgentID = nil
            focusedReplyAgentID = nil
            model.submitOrQueueReply(item, text: text)
        }
    }

    private func previewLinesColumn(
        item: AgentActivityItem,
        lines: [String],
        familyColor: Color,
        statusColor: Color,
        dark: Bool
    ) -> some View {
        let primaryTextColor = FlatPalette.inkPrimary(dark: dark)
        let secondaryTextColor = FlatPalette.inkSecondary(dark: dark)
        let sigilColor = FlatPalette.terminalSigil(dark: dark)

        return VStack(alignment: .leading, spacing: 2.5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                let isFirst = idx == 0
                let isCommandOrQuestion = item.status == .needsInput && (
                    line.hasPrefix("⏺") ||
                    line.hasPrefix("•") ||
                    line.lowercased().contains("do you want") ||
                    line.lowercased().contains("would you like") ||
                    line.lowercased().contains("allow")
                )
                let isHighlightedLine = isFirst || isCommandOrQuestion
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if isFirst {
                        Text(item.status == .needsInput ? "❯" : "›")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(sigilColor)
                    }
                    Text(line)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(isHighlightedLine ? primaryTextColor : secondaryTextColor)
                        .lineLimit(item.status == .needsInput ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: item.status == .needsInput)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func terminalTelemetryFooter(
        item: AgentActivityItem,
        cacheRemaining: Int?,
        showHoverActions: Bool,
        familyColor: Color,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        let activeProgress = (item.taskProgress?.isEmpty == false) ? item.taskProgress : nil

        return HStack(alignment: .center, spacing: 6) {
            if let diff = item.gitDiff {
                HStack(spacing: 4) {
                    Text(en ? "Diff" : "变更")
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                    benchoGitDiffChip(diff: diff, dark: dark)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            if let progress = activeProgress {
                if item.gitDiff != nil {
                    Text("·")
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(FlatPalette.inkTertiary(dark: dark))
                }
                benchoTaskProgressChip(progress: progress, familyColor: familyColor, dark: dark)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if let cacheRemaining {
                if item.gitDiff != nil || activeProgress != nil {
                    Text("·")
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(FlatPalette.inkTertiary(dark: dark))
                }
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    let liveRemaining = item.cacheWarmRemainingSeconds(now: context.date) ?? cacheRemaining
                    benchoCacheWarmChip(remainingSeconds: liveRemaining, dark: dark)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            if item.gitDiff == nil && activeProgress == nil && cacheRemaining == nil {
                Text(item.terminalHost.displayName)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(FlatPalette.inkTertiary(dark: dark))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let ctx = item.contextPercentUsed {
                benchoContextMeterChip(ctx: ctx, familyColor: familyColor, dark: dark)
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(showHoverActions ? 0 : 1)
            }
        }
        .frame(height: 18)
    }

    private func inlineFooterHoverActionButtons(
        item: AgentActivityItem,
        dark: Bool,
        showInlineReply: Bool
    ) -> some View {
        let en = model.language == .english
        let isInterruptHovered = hoveredInterruptID == item.id
        let isReplyToggleHovered = hoveredReplyToggleID == item.id
        let btnShape = RoundedRectangle(cornerRadius: 4, style: .continuous)

        let stopFg = FlatPalette.dangerInterruptForeground(dark: dark)
        let stopBg = FlatPalette.dangerInterruptBackground(dark: dark, hovered: isInterruptHovered)

        let replyBg = FlatPalette.raisedBackground(dark: dark, hovered: showInlineReply || isReplyToggleHovered)
        let replyFg = FlatPalette.inkPrimary(dark: dark)

        return HStack(spacing: 4) {
            if item.status == .working {
                HStack(spacing: 3.5) {
                    Text(en ? "Stop" : "中断")
                        .font(.system(size: 10.5, weight: .medium))
                    Text("^C")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .opacity(0.75)
                }
                .foregroundStyle(stopFg)
                .padding(.horizontal, 6.5)
                .frame(height: 18)
                .background(
                    btnShape
                        .fill(stopBg)
                        .overlay(
                            btnShape
                                .strokeBorder(stopFg.opacity(0.25), lineWidth: 1)
                        )
                )
                .overlay {
                    PointingHandCursorOverlay(
                        tooltip: en
                            ? "Send Esc / Ctrl+C to interrupt current turn without closing session"
                            : "发送 Esc / Ctrl+C 中断当前执行轮次（不关闭会话窗口）",
                        onHoverChange: { hovering in
                            if hovering {
                                isKeyboardNavigationActive = false
                            }
                            hoveredInterruptID = hovering ? item.id : (hoveredInterruptID == item.id ? nil : hoveredInterruptID)
                        },
                        onClick: {
                            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                hoveredInterruptID = nil
                                expandedReplyAgentID = nil
                                focusedReplyAgentID = nil
                                model.interruptAgentSession(item)
                            }
                        }
                    )
                }
            }

            HStack(spacing: 3) {
                Text("/")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                Text(
                    item.status == .working
                        ? (en ? "Queue" : "排队")
                        : (en ? "Reply" : "快捷回复")
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(replyFg)
            }
            .padding(.horizontal, 6.5)
            .frame(height: 18)
            .background(
                btnShape
                    .fill(replyBg)
                    .overlay(
                        btnShape
                            .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: item.status == .working
                        ? (en ? "Queue next instruction to auto-send when session finishes" : "预置下一条指令，待当前任务完成后自动发送")
                        : (en ? "Type a custom reply to \(item.terminalHost.displayName)" : "输入自定义回复发送至 \(item.terminalHost.displayName)"),
                    onHoverChange: { hovering in
                        if hovering {
                            isKeyboardNavigationActive = false
                        }
                        hoveredReplyToggleID = hovering ? item.id : (hoveredReplyToggleID == item.id ? nil : hoveredReplyToggleID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            if expandedReplyAgentID == item.id || focusedReplyAgentID == item.id {
                                expandedReplyAgentID = nil
                                focusedReplyAgentID = nil
                            } else {
                                expandedReplyAgentID = item.id
                                focusedReplyAgentID = item.id
                            }
                        }
                    }
                )
            }
        }
    }

    private func benchoTaskProgressChip(progress: AgentTaskProgress, familyColor: Color, dark: Bool) -> some View {
        let en = model.language == .english
        let isDone = progress.isAllCompleted
        let accentColor: Color = isDone
            ? FlatPalette.softGoodForeground(dark: dark)
            : familyColor
        let textColor = isDone
            ? FlatPalette.softGoodForeground(dark: dark)
            : FlatPalette.inkSecondary(dark: dark)

        return HStack(spacing: 3.5) {
            if progress.totalCount > 0 {
                Text(isDone ? "✓" : "☑")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accentColor)

                Text(en ? "Tasks" : "任务")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(textColor)

                Text("\(progress.completedCount)/\(progress.totalCount)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(isDone ? accentColor : FlatPalette.inkPrimary(dark: dark))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            if progress.activeSubagentCount > 0 {
                if progress.totalCount > 0 {
                    Text("·")
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(FlatPalette.inkTertiary(dark: dark))
                }
                Text("⑂\(progress.activeSubagentCount)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(familyColor)
                    .monospacedDigit()
            }
        }
        .help(taskProgressTooltipText(progress: progress, en: en))
    }

    private func benchoGitDiffChip(diff: GitDiffSummary, dark: Bool) -> some View {
        let en = model.language == .english
        let addColor = FlatPalette.diffAddForeground(dark: dark)
        let delColor = FlatPalette.diffDeleteForeground(dark: dark)

        return HStack(spacing: 3.5) {
            if diff.insertions > 0 || diff.deletions == 0 {
                Text("+\(diff.insertions)")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(addColor)
                    .monospacedDigit()
            }
            if diff.deletions > 0 {
                Text("-\(diff.deletions)")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(delColor)
                    .monospacedDigit()
            }
        }
        .help(
            en
                ? "Git working tree changes: \(diff.changedFiles) file(s) (+\(diff.insertions) -\(diff.deletions))"
                : "Git 工作区变更：\(diff.changedFiles) 个文件（+\(diff.insertions) -\(diff.deletions)）"
        )
    }

    private func benchoCacheWarmChip(remainingSeconds: Int, dark: Bool) -> some View {
        let en = model.language == .english
        let isExpiringSoon = remainingSeconds <= 60
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        let timeStr = String(format: "%d:%02d", mins, secs)

        let dotColor: Color = isExpiringSoon
            ? FlatPalette.amberAlertForeground(dark: dark)
            : FlatPalette.softGoodForeground(dark: dark)
        let tintColor: Color = isExpiringSoon
            ? FlatPalette.amberAlertForeground(dark: dark)
            : FlatPalette.inkSecondary(dark: dark)

        return HStack(spacing: 3.5) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)

            Text(en ? "Cache" : "缓存")
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(tintColor)

            Text(timeStr)
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(tintColor)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .help(
            en
                ? "Prompt cache warm (\(timeStr) left before 5m TTL eviction)"
                : "Prompt 热缓存有效（剩余 \(timeStr)，5 分钟超时后再次对话将重新预热上下文）"
        )
    }

    private func benchoContextMeterChip(ctx: Int, familyColor: Color, dark: Bool) -> some View {
        let isWarningCtx = ctx >= 60
        let activeColor: Color = isWarningCtx
            ? FlatPalette.amberAlertForeground(dark: dark)
            : FlatPalette.accent(dark: dark)
        let textColor: Color = isWarningCtx
            ? FlatPalette.amberAlertForeground(dark: dark)
            : FlatPalette.inkSecondary(dark: dark)
        let emptySegColor = dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
        let filledSegments = max(1, min(5, Int(ceil(Double(max(1, ctx)) / 20.0))))

        return HStack(spacing: 4.5) {
            HStack(spacing: 1.5) {
                ForEach(0..<5, id: \.self) { segIdx in
                    let lit = segIdx < filledSegments && ctx > 0
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(lit ? activeColor : emptySegColor)
                        .frame(width: 2.5, height: 8)
                }
            }

            Text("\(ctx)%")
                .font(.system(size: 10.5, weight: isWarningCtx ? .medium : .regular, design: .monospaced))
                .foregroundStyle(textColor)
                .monospacedDigit()
        }
        .help(model.language == .english ? "Context window \(ctx)% used" : "上下文窗口已使用 \(ctx)%")
    }

    private func inlineApprovalReserveBar(dark: Bool) -> some View {
        let en = model.language == .english
        let amber = FlatPalette.amberAlertForeground(dark: dark)
        return HStack(spacing: 5) {
            Circle()
                .fill(amber)
                .frame(width: 6, height: 6)
            Text(en ? "Awaiting confirmation" : "等待终端权限确认")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(amber)
                .lineLimit(1)
            Spacer(minLength: 4)
            // Space reserved for the Stageshow .ss-btn-row overlay
            Color.clear
                .frame(width: 214, height: 24)
        }
        .padding(.top, 1)
    }

    private func inlineWorkingReserveBar(
        item: AgentActivityItem,
        isLongRunning: Bool,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        let hostName = item.terminalHost.displayName
        let dangerRed = FlatPalette.dangerInterruptForeground(dark: dark)
        let labelColor = isLongRunning ? dangerRed : FlatPalette.inkSecondary(dark: dark)
        return HStack(spacing: 5.5) {
            if isLongRunning {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(dangerRed)
            }
            Text(
                isLongRunning
                    ? (en ? "Long-running task · check if stalled" : "长时运行任务 · 请留意是否卡死")
                    : (en ? "Running task in \(hostName)" : "正在 \(hostName) 中执行任务")
            )
            .font(.system(size: 11.5, weight: isLongRunning ? .medium : .regular))
            .foregroundStyle(labelColor)
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 4)
            // Space reserved for the Stageshow .ss-btn-row overlay
            Color.clear
                .frame(width: 116, height: 24)
        }
        .padding(.top, 1)
    }

    private func inlineWorkingActionButtons(
        item: AgentActivityItem,
        dark: Bool,
        showInlineReply: Bool
    ) -> some View {
        let en = model.language == .english
        let isInterruptHovered = hoveredInterruptID == item.id
        let isReplyToggleHovered = hoveredReplyToggleID == item.id
        let btnShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        let stopFg = FlatPalette.dangerInterruptForeground(dark: dark)
        let stopBg = FlatPalette.dangerInterruptBackground(dark: dark, hovered: isInterruptHovered)

        let replyBg = FlatPalette.raisedBackground(dark: dark, hovered: showInlineReply || isReplyToggleHovered)
        let replyFg = FlatPalette.inkPrimary(dark: dark)

        return HStack(spacing: 5) {
            // 1. Interrupt Button: Stop ^C / 中断 ^C
            HStack(spacing: 5) {
                Text(en ? "Stop" : "中断")
                    .font(.system(size: 11.5, weight: .medium))
                Text("^C")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .opacity(0.75)
            }
            .foregroundStyle(stopFg)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(height: 24)
            .background(
                btnShape
                    .fill(stopBg)
                    .overlay(
                        btnShape
                            .strokeBorder(stopFg.opacity(0.25), lineWidth: 1)
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en
                        ? "Send Esc / Ctrl+C to interrupt current turn without closing session"
                        : "发送 Esc / Ctrl+C 中断当前执行轮次（不关闭会话窗口）",
                    onHoverChange: { hovering in
                        if hovering {
                            isKeyboardNavigationActive = false
                        }
                        hoveredInterruptID = hovering ? item.id : (hoveredInterruptID == item.id ? nil : hoveredInterruptID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            hoveredInterruptID = nil
                            expandedReplyAgentID = nil
                            focusedReplyAgentID = nil
                            model.interruptAgentSession(item)
                        }
                    }
                )
            }

            // 2. Custom Reply Toggle Button: "/"
            Text("/")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(replyFg)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(height: 24)
                .background(
                    btnShape
                        .fill(replyBg)
                        .overlay(
                            btnShape
                                .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                        )
                )
                .overlay {
                    PointingHandCursorOverlay(
                        tooltip: en ? "Type a custom reply to \(item.terminalHost.displayName)" : "输入自定义回复发送至 \(item.terminalHost.displayName)",
                        onHoverChange: { hovering in
                            if hovering {
                                isKeyboardNavigationActive = false
                            }
                            hoveredReplyToggleID = hovering ? item.id : (hoveredReplyToggleID == item.id ? nil : hoveredReplyToggleID)
                        },
                        onClick: {
                            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                if expandedReplyAgentID == item.id {
                                    expandedReplyAgentID = nil
                                    focusedReplyAgentID = nil
                                } else {
                                    expandedReplyAgentID = item.id
                                    focusedReplyAgentID = item.id
                                }
                            }
                        }
                    )
                }
        }
    }

    private func inlineApprovalActionButtons(
        item: AgentActivityItem,
        isApprove1Hovered: Bool,
        isApprove2Hovered: Bool,
        isDenyHovered: Bool,
        isReplyToggleHovered: Bool,
        showInlineReply: Bool,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        let btnShape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let greenFg = FlatPalette.softGoodForeground(dark: dark)
        let greenBg = FlatPalette.softGoodBackground(dark: dark, hovered: isApprove1Hovered)
        let raisedFg = FlatPalette.inkPrimary(dark: dark)

        // Stageshow .ss-btn-row: independent 6pt rounded buttons with 5pt spacing
        return HStack(spacing: 5) {
            // 1. Primary Approve: Allow ⏎ / 允许 ⏎
            HStack(spacing: 5) {
                Text(en ? "Allow" : "允许")
                    .font(.system(size: 11.5, weight: .medium))
                Text("⏎")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .opacity(0.75)
            }
            .foregroundStyle(greenFg)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(height: 24)
            .background(
                btnShape
                    .fill(greenBg)
                    .overlay(
                        btnShape
                            .strokeBorder(greenFg.opacity(0.25), lineWidth: 1)
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en ? "Send Enter to approve (Option 1)" : "发送回车确认允许（选项 1）",
                    onHoverChange: { hovering in
                        if hovering {
                            isKeyboardNavigationActive = false
                        }
                        hoveredApprovePrimaryID = hovering ? item.id : (hoveredApprovePrimaryID == item.id ? nil : hoveredApprovePrimaryID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            model.respondToPermission(item, choice: .approvePrimary)
                        }
                    }
                )
            }

            // 2. Option 2: 2
            Text("2")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(raisedFg)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(height: 24)
                .background(
                    btnShape
                        .fill(FlatPalette.raisedBackground(dark: dark, hovered: isApprove2Hovered))
                        .overlay(
                            btnShape
                                .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                        )
                )
                .overlay {
                    PointingHandCursorOverlay(
                        tooltip: en ? "Select Option 2 and confirm (e.g. Always allow)" : "选择第 2 项并确认（如：始终允许 / 本次会话不再询问）",
                        onHoverChange: { hovering in
                            if hovering {
                                isKeyboardNavigationActive = false
                            }
                            hoveredApproveSecondaryID = hovering ? item.id : (hoveredApproveSecondaryID == item.id ? nil : hoveredApproveSecondaryID)
                        },
                        onClick: {
                            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                model.respondToPermission(item, choice: .approveSecondary)
                            }
                        }
                    )
                }

            // 3. Deny: Deny Esc / 拒绝 Esc
            HStack(spacing: 5) {
                Text(en ? "Deny" : "拒绝")
                    .font(.system(size: 11.5, weight: .medium))
                Text("Esc")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .opacity(0.75)
            }
            .foregroundStyle(raisedFg)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(height: 24)
            .background(
                btnShape
                    .fill(FlatPalette.raisedBackground(dark: dark, hovered: isDenyHovered))
                    .overlay(
                        btnShape
                            .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en ? "Send deny or Esc to cancel" : "发送拒绝指令或 Esc 取消",
                    onHoverChange: { hovering in
                        if hovering {
                            isKeyboardNavigationActive = false
                        }
                        hoveredDenyID = hovering ? item.id : (hoveredDenyID == item.id ? nil : hoveredDenyID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            model.respondToPermission(item, choice: .deny)
                        }
                    }
                )
            }

            // 4. Custom Reply Toggle Button: "/"
            Text("/")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(raisedFg)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(height: 24)
                .background(
                    btnShape
                        .fill(FlatPalette.raisedBackground(dark: dark, hovered: showInlineReply || isReplyToggleHovered))
                        .overlay(
                            btnShape
                                .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                        )
                )
                .overlay {
                    PointingHandCursorOverlay(
                        tooltip: en ? "Type a custom reply to \(item.terminalHost.displayName)" : "输入自定义回复发送至 \(item.terminalHost.displayName)",
                        onHoverChange: { hovering in
                            if hovering {
                                isKeyboardNavigationActive = false
                            }
                            hoveredReplyToggleID = hovering ? item.id : (hoveredReplyToggleID == item.id ? nil : hoveredReplyToggleID)
                        },
                        onClick: {
                            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                if expandedReplyAgentID == item.id {
                                    expandedReplyAgentID = nil
                                    focusedReplyAgentID = nil
                                } else {
                                    expandedReplyAgentID = item.id
                                    focusedReplyAgentID = item.id
                                }
                            }
                        }
                    )
                }
        }
    }

    private func rowBorderColor(
        for item: AgentActivityItem,
        isLead: Bool,
        isHovered: Bool,
        isSelected: Bool,
        familyColor: Color,
        dark: Bool
    ) -> Color {
        if isHovered {
            return familyColor.opacity(dark ? 0.72 : 0.62)
        }
        if isSelected {
            return familyColor.opacity(dark ? 0.56 : 0.48)
        }
        if item.status == .working && item.isLongRunningWorking() {
            return Color(red: 239.0 / 255, green: 68.0 / 255, blue: 68.0 / 255).opacity(0.30)
        }
        if isLead || item.status == .needsInput {
            return Color(red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255).opacity(0.28)
        }
        return FlatPalette.hairlineBorder(dark: dark)
    }

    private func agentStatusColor(_ status: AgentTaskStatus, dark: Bool) -> Color {
        switch status {
        case .needsInput:
            return FlatPalette.amberAlertForeground(dark: dark)
        case .working:
            return FlatPalette.accentText(dark: dark)
        case .completed:
            return FlatPalette.softGoodForeground(dark: dark)
        case .idle:
            return FlatPalette.inkSecondary(dark: dark)
        }
    }

    private func formatLiveDuration(_ seconds: Int) -> String {
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

    private func formatRelativeAgo(_ seconds: Int, en: Bool) -> String {
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
        if hours < 24 {
            return en ? "\(hours)h ago" : "\(hours)h前"
        }
        let days = hours / 24
        return en ? "\(days)d ago" : "\(days)天前"
    }

    private func footer(dark: Bool) -> some View {
        let en = model.language == .english
        return HStack(spacing: 6) {
            HStack(spacing: 7) {
                footerShortcutItem(key: "↑↓", label: en ? "Select" : "选择", dark: dark)
                footerShortcutItem(key: "⏎", label: en ? "Approve/Open" : "放行/跳转", dark: dark)
                footerShortcutItem(key: "/", label: en ? "Reply" : "回复", dark: dark)
                footerShortcutItem(key: "P", label: en ? "PiP" : "画中画", dark: dark)
                footerShortcutItem(key: "⌥↵", label: en ? "Urgent" : "直达紧急", dark: dark)
            }
            Spacer(minLength: 4)
            FlatIconButton(icon: "power", size: 22, iconSize: 11, tooltip: en ? "Quit Agent Meter" : "退出应用") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func footerShortcutItem(key: String, label: String, dark: Bool) -> some View {
        HStack(spacing: 3.5) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(FlatPalette.raisedBackground(dark: dark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(dark ? 0.28 : 0.08), radius: 0, x: 0, y: 1)
                )
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(FlatPalette.inkTertiary(dark: dark))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Quick Launch & History Resume Section

    @ViewBuilder
    private func quickLaunchSection(dark: Bool) -> some View {
        if quickLaunchMode == .history {
            TimelineView(.periodic(from: .now, by: 30.0)) { context in
                historySessionSection(dark: dark, now: context.date)
            }
            .transition(.opacity)
        } else {
            newSessionLaunchSection(dark: dark)
                .transition(.opacity)
        }
    }

    private var filteredHistoricalSessions: [AgentHistorySessionItem] {
        let query = historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.historicalSessions.filter { item in
            if let selectedHistoryFamily, item.family != selectedHistoryFamily {
                return false
            }
            guard !query.isEmpty else { return true }
            return item.title.lowercased().contains(query)
                || item.workspace.lowercased().contains(query)
                || item.cwdPath.lowercased().contains(query)
                || item.family.rawValue.lowercased().contains(query)
                || (item.gitBranch?.lowercased().contains(query) ?? false)
        }
    }

    private func historySessionSection(dark: Bool, now: Date) -> some View {
        let en = model.language == .english
        let items = filteredHistoricalSessions
        let hasSearchText = !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 11) {
            // 1. Search Bar
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isHistorySearchFocused ? FlatPalette.blue : .secondary)

                InlinePromptTextField(
                    text: $historySearchQuery,
                    placeholder: en ? "Search session title, prompt, or project…" : "搜索历史标题、提示词或项目名…",
                    dark: dark,
                    requestFocus: isHistorySearchFocused,
                    onFocusChange: { focused in
                        isHistorySearchFocused = focused
                    }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 20)

                if hasSearchText {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .overlay {
                            PointingHandCursorOverlay(
                                onClick: {
                                    historySearchQuery = ""
                                }
                            )
                        }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(FlatPalette.cardBackground(dark: dark))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isHistorySearchFocused
                                    ? FlatPalette.blue.opacity(dark ? 0.55 : 0.45)
                                    : FlatPalette.hairlineBorder(dark: dark),
                                lineWidth: 1
                            )
                    )
            )

            // 2. Agent Family Filter Pills
            historyFamilyFilterBar(dark: dark)

            // 3. Historical Sessions List
            if items.isEmpty {
                let targetHostName = model.resolvedLaunchTerminalHost().displayName
                emptyStateCard(
                    icon: "clock.arrow.circlepath",
                    title: hasSearchText
                        ? (en ? "No matching historical sessions" : "没有找到匹配的历史会话")
                        : (en ? "No historical sessions found" : "暂未发现本地历史会话记录"),
                    subtitle: en
                        ? "Supports resuming Claude Code, Codex CLI, Copilot CLI & Antigravity conversations in \(targetHostName)"
                        : "自动扫描本机 Claude Code、Codex CLI、Copilot CLI 与 Antigravity 的历史会话记录，支持在 \(targetHostName) 中一键恢复"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        historySessionRow(item: item, dark: dark, now: now)
                    }
                }
            }
        }
    }

    private func historyFamilyFilterBar(dark: Bool) -> some View {
        let en = model.language == .english
        return HStack(spacing: 4) {
            historyFamilyFilterPill(
                family: nil,
                label: en ? "All" : "全部",
                count: model.historicalSessions.count,
                dark: dark
            )
            ForEach(AgentFamily.allCases) { family in
                let count = model.historicalSessions.filter { $0.family == family }.count
                if count > 0 {
                    historyFamilyFilterPill(
                        family: family,
                        label: family.shortName,
                        count: count,
                        dark: dark
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func historyFamilyFilterPill(
        family: AgentFamily?,
        label: String,
        count: Int,
        dark: Bool
    ) -> some View {
        let isSelected = selectedHistoryFamily == family
        let accent = family?.accentColor(dark: dark) ?? FlatPalette.blue
        let pillID = family?.rawValue ?? "all"

        return HStack(spacing: 3.5) {
            if let family {
                AgentFamilyGlyph(
                    family: family,
                    color: isSelected ? accent : .secondary,
                    size: 11
                )
            }
            Text(label)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
            Text("\(count)")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .opacity(isSelected ? 0.88 : 0.6)
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, 8.5)
        .padding(.vertical, 4.5)
        .background {
            if isSelected {
                Capsule()
                    .fill(FlatPalette.selectedPillBackground(dark: dark))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                family != nil ? accent.opacity(dark ? 0.42 : 0.32) : FlatPalette.hairlineBorder(dark: dark),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(dark ? 0.24 : 0.06), radius: 2, x: 0, y: 1)
                    .matchedGeometryEffect(id: "historyFamilyPill", in: historyFamilyFilterNamespace)
            } else {
                Capsule()
                    .fill(FlatPalette.trackBackground(dark: dark))
            }
        }
        .contentShape(Capsule())
        .overlay {
            PointingHandCursorOverlay(
                onClick: {
                    resetHoverAndKeyboardNavigation()
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                        selectedHistoryFamily = family
                    }
                }
            )
        }
        .id(pillID)
    }

    private func historySessionRow(
        item: AgentHistorySessionItem,
        dark: Bool,
        now: Date
    ) -> some View {
        let en = model.language == .english
        let isConfirmingDelete = confirmingHistoryDeleteID == item.id
        let isDeleteHovered = hoveredHistoryDeleteID == item.id
        let isConfirmHovered = hoveredHistoryConfirmDeleteID == item.id
        let isCancelHovered = hoveredHistoryCancelDeleteID == item.id
        let isSelected = isKeyboardNavigationActive && selectedHistoryID == item.id
        let isHovered = hoveredHistoryID == item.id || isDeleteHovered || isConfirmHovered || isCancelHovered || isConfirmingDelete || isSelected
        let accent = item.family.accentColor(dark: dark)
        let isOnline = item.onlineActivityID != nil
        let elapsed = max(0, Int(now.timeIntervalSince(item.updatedAt)))
        let timeStr = formatRelativeAgo(elapsed, en: en)
        let displayPath = abbreviateHomePath(item.cwdPath)

        return HStack(alignment: .center, spacing: 10) {
            AgentFamilyBadgeIcon(
                family: item.family,
                dark: dark,
                highlighted: isHovered || isOnline,
                size: 30
            )
            .help(item.family.badgeTitle)

            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Session Title + Top-Right Action Pill & Delete Button
                HStack(alignment: .center, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 6)

                    if isOnline {
                        let goodFg = FlatPalette.softGoodForeground(dark: dark)
                        HStack(spacing: 3.5) {
                            Circle()
                                .fill(goodFg)
                                .frame(width: 5, height: 5)
                            Text(en ? "Online ↗" : "在线 ↗")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(goodFg)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(FlatPalette.softGoodBackground(dark: dark))
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    } else if isConfirmingDelete {
                        // Reserve space for the top-trailing confirmation buttons overlay
                        Color.clear
                            .frame(width: en ? 116 : 112, height: 20)
                    } else {
                        HStack(spacing: 3) {
                            Text(en ? "Resume" : "恢复")
                                .font(.system(size: 10.5, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundStyle(isHovered && !isDeleteHovered ? accent : FlatPalette.inkSecondary(dark: dark))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(
                                    isHovered && !isDeleteHovered
                                        ? accent.opacity(dark ? 0.18 : 0.11)
                                        : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                                )
                        )
                        .fixedSize(horizontal: true, vertical: false)

                        // Reserve space for the top-trailing delete button overlay
                        Color.clear
                            .frame(width: 24, height: 20)
                    }
                }

                // Row 2: Full ~ Abbreviated Path + Branch + Relative Time
                HStack(alignment: .center, spacing: 5) {
                    HStack(spacing: 3.5) {
                        Image(systemName: "folder")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(FlatPalette.inkTertiary(dark: dark))
                        Text(displayPath)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let branch = item.gitBranch, !branch.isEmpty {
                        Text("·")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(FlatPalette.inkTertiary(dark: dark))
                        Text(branch)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Spacer(minLength: 6)

                    Text(timeStr)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(FlatPalette.inkTertiary(dark: dark))
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            let targetHostName: String = {
                if let onlineID = item.onlineActivityID,
                   let live = model.agentActivities.first(where: { $0.id == onlineID }) {
                    return live.terminalHost.displayName
                }
                return model.resolvedLaunchTerminalHost().displayName
            }()
            PointingHandCursorOverlay(
                tooltip: isOnline
                    ? (en ? "Session is already active — click to focus \(targetHostName) window (\(displayPath))" : "该会话当前已在线，点击直接跳转到对应 \(targetHostName) 窗口（\(displayPath)）")
                    : (en ? "Resume session in a new \(targetHostName) tab (\(displayPath))" : "在 \(targetHostName) 新建 Tab 恢复该历史会话（\(displayPath)）"),
                onHoverChange: { hovering in
                    if hovering {
                        isKeyboardNavigationActive = false
                    }
                    hoveredHistoryID = hovering ? item.id : (hoveredHistoryID == item.id ? nil : hoveredHistoryID)
                },
                onClick: {
                    if isConfirmingDelete {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16)) {
                            confirmingHistoryDeleteID = nil
                        }
                        return
                    }
                    selectedHistoryID = item.id
                    confirmingHistoryDeleteID = nil
                    isHistorySearchFocused = false
                    resetHoverAndKeyboardNavigation()
                    showingQuickLaunch = false
                    model.resumeOrFocusHistoricalSession(item)
                }
            )
        }
        .overlay(alignment: .topTrailing) {
            if !isOnline {
                if isConfirmingDelete {
                    confirmDeleteHistoryBar(
                        item: item,
                        isConfirmHovered: isConfirmHovered,
                        isCancelHovered: isCancelHovered,
                        dark: dark
                    )
                    .padding(.top, 9)
                    .padding(.trailing, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
                } else {
                    deleteHistoryButton(item: item, isDeleteHovered: isDeleteHovered, isRowHovered: isHovered, dark: dark)
                        .padding(.top, 9.5)
                        .padding(.trailing, 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FlatPalette.elevatedRowBackground(dark: dark, hovered: isHovered))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            (isDeleteHovered || isConfirmingDelete)
                                ? FlatPalette.dangerInterruptForeground(dark: dark).opacity(dark ? 0.42 : 0.34)
                                : (isHovered ? accent.opacity(dark ? 0.62 : 0.52) : FlatPalette.hairlineBorder(dark: dark)),
                            lineWidth: (isHovered || isDeleteHovered || isConfirmingDelete) ? 1.25 : 1
                        )
                )
        )
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16), value: isHovered)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.14), value: isDeleteHovered)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18), value: isConfirmingDelete)
        .id(item.id)
    }

    private func deleteHistoryButton(
        item: AgentHistorySessionItem,
        isDeleteHovered: Bool,
        isRowHovered: Bool,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        return Image(systemName: "trash")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(
                isDeleteHovered
                    ? FlatPalette.dangerInterruptForeground(dark: dark)
                    : Color.secondary.opacity(isRowHovered ? 0.85 : 0.5)
            )
            .frame(width: 22, height: 20)
            .background(
                Capsule()
                    .fill(
                        isDeleteHovered
                            ? FlatPalette.dangerInterruptBackground(dark: dark, hovered: true)
                            : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en ? "Delete session data" : "删除该条历史会话及本地文件",
                    onHoverChange: { hovering in
                        if hovering {
                            isKeyboardNavigationActive = false
                        }
                        hoveredHistoryDeleteID = hovering ? item.id : (hoveredHistoryDeleteID == item.id ? nil : hoveredHistoryDeleteID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            confirmingHistoryDeleteID = item.id
                        }
                    }
                )
            }
            .accessibilityLabel(en ? "Delete session data" : "删除该条历史会话及本地文件")
    }

    private func confirmDeleteHistoryBar(
        item: AgentHistorySessionItem,
        isConfirmHovered: Bool,
        isCancelHovered: Bool,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        let redFg = FlatPalette.dangerInterruptForeground(dark: dark)
        let redBg = FlatPalette.dangerInterruptBackground(dark: dark, hovered: isConfirmHovered)

        let cancelFg = FlatPalette.inkSecondary(dark: dark)
        let cancelBg = dark
            ? (isCancelHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.07))
            : (isCancelHovered ? Color.black.opacity(0.09) : Color.black.opacity(0.045))

        return HStack(spacing: 4) {
            // 1. Confirm Delete Button
            HStack(spacing: 3) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 8.5, weight: .bold))
                Text(en ? "Delete" : "确认删除")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(redFg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(redBg)
                    .overlay(
                        Capsule()
                            .strokeBorder(redFg.opacity(dark ? 0.48 : 0.35), lineWidth: 1)
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en ? "Permanently delete session files from disk" : "确认永久删除该会话及其本地数据文件",
                    onHoverChange: { hovering in
                        if hovering {
                            isKeyboardNavigationActive = false
                        }
                        hoveredHistoryConfirmDeleteID = hovering ? item.id : (hoveredHistoryConfirmDeleteID == item.id ? nil : hoveredHistoryConfirmDeleteID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.20)) {
                            confirmingHistoryDeleteID = nil
                            hoveredHistoryConfirmDeleteID = nil
                            model.deleteHistoricalSession(item)
                        }
                    }
                )
            }

            // 2. Cancel Button
            Text(en ? "Cancel" : "取消")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(cancelFg)
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(cancelBg)
                        .overlay(
                            Capsule()
                                .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                        )
                )
                .overlay {
                    PointingHandCursorOverlay(
                        tooltip: en ? "Cancel deletion" : "取消删除",
                        onHoverChange: { hovering in
                            if hovering {
                                isKeyboardNavigationActive = false
                            }
                            hoveredHistoryCancelDeleteID = hovering ? item.id : (hoveredHistoryCancelDeleteID == item.id ? nil : hoveredHistoryCancelDeleteID)
                        },
                        onClick: {
                            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16)) {
                                confirmingHistoryDeleteID = nil
                                hoveredHistoryCancelDeleteID = nil
                            }
                        }
                    )
                }
        }
    }

    private func newSessionLaunchSection(dark: Bool) -> some View {
        let en = model.language == .english
        let selectedFamily = model.preferredLaunchFamily
        let accent = selectedFamily.accentColor(dark: dark)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(en ? "WORKSPACES (LOCAL & SSH)" : "工作目录与远程 SSH")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                launchHostQuickSwitchPill(dark: dark)
                HStack(spacing: 3.5) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text(en ? "Browse…" : "浏览目录…")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(accent.opacity(dark ? 0.16 : 0.11))
                )
                .overlay {
                    PointingHandCursorOverlay(
                        onClick: {
                            pickCustomDirectoryAndLaunch(family: selectedFamily)
                        }
                    )
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 7) {
                ForEach(model.recentLaunchWorkspaces) { workspace in
                    workspaceLaunchRow(workspace: workspace, selectedFamily: selectedFamily, dark: dark)
                }
            }
        }
    }

    private func launchHostQuickSwitchPill(dark: Bool) -> some View {
        let en = model.language == .english
        let activeHost = model.resolvedLaunchTerminalHost()
        return HStack(spacing: 2) {
            ForEach(TerminalHostKind.allCases) { host in
                let isSelected = activeHost == host
                Text(host.displayName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 3)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(FlatPalette.selectedPillBackground(dark: dark))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: .black.opacity(dark ? 0.24 : 0.06), radius: 1.5, x: 0, y: 1)
                        }
                    }
                    .contentShape(Capsule())
                    .overlay {
                        PointingHandCursorOverlay(
                            tooltip: en
                                ? "Launch new sessions in \(host.displayName)"
                                : "切换为在 \(host.displayName) 中启动新会话",
                            onClick: {
                                withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                    model.preferredTerminalHost = (host == .ghostty) ? .ghostty : .rex
                                }
                            }
                        )
                    }
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(FlatPalette.trackBackground(dark: dark))
                .overlay(
                    Capsule()
                        .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                )
        )
    }

    private func workspaceLaunchRow(
        workspace: LaunchWorkspaceItem,
        selectedFamily: AgentFamily,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        let isSelected = isKeyboardNavigationActive && selectedWorkspacePath == workspace.id
        let hoveredFamilyOnThisRow: AgentFamily? = AgentFamily.allCases.first {
            hoveredWorkspaceAgentKey == "\(workspace.id):\($0.rawValue)"
        }
        let isRowHovered = hoveredWorkspacePath == workspace.id || hoveredFamilyOnThisRow != nil
        let isRowHighlighted = isRowHovered || isSelected
        let displayPath = abbreviateHomePath(workspace.path)
        let hostName = model.resolvedLaunchTerminalHost().displayName
        let rowShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        let rowTooltip: String = {
            if let sshHost = workspace.sshTarget, !sshHost.isEmpty {
                return en
                    ? "Connect to \(sshHost) (\(displayPath)) & launch \(selectedFamily.badgeTitle) in \(hostName)"
                    : "在 \(hostName) 中 SSH 连接 \(sshHost)（\(displayPath)）并启动 \(selectedFamily.badgeTitle)"
            }
            return en
                ? "Launch \(selectedFamily.badgeTitle) in \(hostName) (\(displayPath))"
                : "在 \(hostName) 中启动 \(selectedFamily.badgeTitle)（\(displayPath)）"
        }()

        let rowBorderColor: Color = {
            if let hoveredFamily = hoveredFamilyOnThisRow {
                return hoveredFamily.accentColor(dark: dark).opacity(dark ? 0.72 : 0.62)
            }
            if isRowHighlighted {
                return selectedFamily.accentColor(dark: dark).opacity(dark ? 0.56 : 0.48)
            }
            return FlatPalette.hairlineBorder(dark: dark)
        }()

        return HStack(alignment: .center, spacing: 8) {
            if let sshHost = workspace.sshTarget, !sshHost.isEmpty {
                Text("SSH · \(sshHost)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(FlatPalette.accentText(dark: dark))
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(FlatPalette.accentSoftBackground(dark: dark))
                    )
                    .fixedSize(horizontal: true, vertical: false)

                Text(displayPath)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FlatPalette.iconPrimary(dark: dark))

                Text(displayPath)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            // Reserve space for the trailing 4-icon dock overlay (4 * 26 + 3 * 4 = 116)
            Color.clear
                .frame(width: 116, height: 24)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .contentShape(rowShape)
        .overlay {
            PointingHandCursorOverlay(
                tooltip: rowTooltip,
                onHoverChange: { hovering in
                    if hovering {
                        isKeyboardNavigationActive = false
                    }
                    hoveredWorkspacePath = hovering ? workspace.id : (hoveredWorkspacePath == workspace.id ? nil : hoveredWorkspacePath)
                },
                onClick: {
                    selectedWorkspacePath = workspace.id
                    resetHoverAndKeyboardNavigation()
                    showingQuickLaunch = false
                    model.launchWorkspaceSession(family: model.preferredLaunchFamily, workspace: workspace)
                }
            )
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 4) {
                ForEach(AgentFamily.allCases) { family in
                    workspaceAgentLaunchButton(
                        workspace: workspace,
                        family: family,
                        isRowHighlighted: isRowHighlighted,
                        isKeyboardActive: isSelected && selectedFamily == family,
                        dark: dark
                    )
                }
            }
            .padding(.trailing, 11)
        }
        .background(
            rowShape
                .fill(FlatPalette.elevatedRowBackground(dark: dark, hovered: isRowHighlighted))
                .overlay(
                    rowShape
                        .strokeBorder(
                            rowBorderColor,
                            lineWidth: isRowHighlighted ? 1.25 : 1.0
                        )
                )
        )
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.14), value: isRowHighlighted)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.14), value: hoveredFamilyOnThisRow)
        .id(workspace.id)
    }

    private func workspaceAgentLaunchButton(
        workspace: LaunchWorkspaceItem,
        family: AgentFamily,
        isRowHighlighted: Bool,
        isKeyboardActive: Bool,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        let buttonKey = "\(workspace.id):\(family.rawValue)"
        let isHovered = hoveredWorkspaceAgentKey == buttonKey
        let isHighlighted = isHovered || isKeyboardActive
        let accent = family.accentColor(dark: dark)
        let displayPath = abbreviateHomePath(workspace.path)
        let hostName = model.resolvedLaunchTerminalHost().displayName
        let btnShape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let tooltipText: String = {
            if let sshHost = workspace.sshTarget, !sshHost.isEmpty {
                return en
                    ? "Connect to \(sshHost) (\(displayPath)) & launch \(family.badgeTitle) in \(hostName)"
                    : "在 \(hostName) 中 SSH 连接 \(sshHost)（\(displayPath)）并启动 \(family.badgeTitle)"
            }
            return en
                ? "Launch \(family.badgeTitle) in \(hostName) (\(displayPath))"
                : "在 \(hostName) 中启动 \(family.badgeTitle)（\(displayPath)）"
        }()

        return AgentFamilyGlyph(
            family: family,
            color: accent,
            size: 13.5
        )
        .opacity(isHighlighted ? 1.0 : (isRowHighlighted ? 0.92 : 0.75))
        .frame(width: 26, height: 26)
        .background(
            btnShape
                .fill(
                    isHighlighted
                        ? family.tintFill(dark: dark, highlighted: true)
                        : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                )
                .overlay(
                    btnShape
                        .strokeBorder(
                            isHighlighted
                                ? accent.opacity(dark ? 0.68 : 0.56)
                                : FlatPalette.hairlineBorder(dark: dark),
                            lineWidth: isHighlighted ? 1.2 : 1.0
                        )
                )
        )
        .contentShape(btnShape)
        .overlay {
            PointingHandCursorOverlay(
                tooltip: tooltipText,
                onHoverChange: { hovering in
                    if hovering {
                        isKeyboardNavigationActive = false
                    }
                    hoveredWorkspaceAgentKey = hovering ? buttonKey : (hoveredWorkspaceAgentKey == buttonKey ? nil : hoveredWorkspaceAgentKey)
                },
                onClick: {
                    selectedWorkspacePath = workspace.id
                    resetHoverAndKeyboardNavigation()
                    showingQuickLaunch = false
                    model.launchWorkspaceSession(family: family, workspace: workspace)
                }
            )
        }
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.14), value: isHighlighted)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.14), value: isRowHighlighted)
    }

    private func abbreviateHomePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "~" }
        var normalized = (trimmed as NSString).standardizingPath
        if normalized.hasPrefix("/private/tmp") {
            normalized = String(normalized.dropFirst("/private".count))
        } else if normalized.hasPrefix("/private/var") {
            normalized = String(normalized.dropFirst("/private".count))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if normalized == home { return "~" }
        if normalized.hasPrefix(home + "/") {
            return "~" + normalized.dropFirst(home.count)
        }
        return normalized
    }

    private func pickCustomDirectoryAndLaunch(family: AgentFamily) {
        let en = model.language == .english
        let hostName = model.resolvedLaunchTerminalHost().displayName
        let panel = NSOpenPanel()
        panel.title = en
            ? "Choose workspace directory to launch \(family.badgeTitle) in \(hostName)"
            : "选择要在 \(hostName) 中启动 \(family.badgeTitle) 的工作目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("code")
        NSApplication.shared.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            showingQuickLaunch = false
            model.launchNewAgentSession(family: family, cwdPath: url.path)
        }
    }
}

private struct AgentFamilyBadgeIcon: View {
    let family: AgentFamily
    let dark: Bool
    var highlighted: Bool = false
    var size: CGFloat = 28
    var muted: Bool = false

    var body: some View {
        let fg: Color = muted ? FlatPalette.inkTertiary(dark: dark) : family.accentColor(dark: dark)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        ZStack {
            shape
                .fill(
                    highlighted && !muted
                        ? family.tintFill(dark: dark, highlighted: true)
                        : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                )
                .overlay(
                    shape
                        .strokeBorder(
                            highlighted && !muted
                                ? fg.opacity(dark ? 0.42 : 0.34)
                                : FlatPalette.hairlineBorder(dark: dark),
                            lineWidth: 1
                        )
                )

            AgentFamilyGlyph(family: family, color: fg, size: size * 0.50)
        }
        .frame(width: size, height: size)
    }
}

/// Official vector brand marks rendered via native `NSImage(data:)` SVG support:
/// - Codex CLI: Official OpenAI 6-petal blossom knot
/// - Claude Code: Official Anthropic Claude starburst
/// - Copilot CLI: Official GitHub Copilot helmet/goggles mark
/// - Antigravity CLI: Official Antigravity "A" arch mark
private struct AgentFamilyGlyph: View {
    let family: AgentFamily
    let color: Color
    var size: CGFloat = 16

    @MainActor private static var cachedImages: [AgentFamily: NSImage] = [:]

    @MainActor private static func templateImage(for family: AgentFamily) -> NSImage? {
        if let cached = cachedImages[family] {
            return cached
        }
        let svgString: String
        switch family {
        case .codex:
            // Official OpenAI / Codex 6-petal blossom knot (viewBox 0 0 24 24)
            svgString = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path fill="#000000" fill-rule="evenodd" d="M9.205 8.658v-2.26c0-.19.072-.333.238-.428l4.543-2.616c.619-.357 1.356-.523 2.117-.523 2.854 0 4.662 2.212 4.662 4.566 0 .167 0 .357-.024.547l-4.71-2.759a.797.797 0 00-.856 0l-5.97 3.473zm10.609 8.8V12.06c0-.333-.143-.57-.429-.737l-5.97-3.473 1.95-1.118a.433.433 0 01.476 0l4.543 2.617c1.309.76 2.189 2.378 2.189 3.948 0 1.808-1.07 3.473-2.76 4.163zM7.802 12.703l-1.95-1.142c-.167-.095-.239-.238-.239-.428V5.899c0-2.545 1.95-4.472 4.591-4.472 1 0 1.927.333 2.712.928L8.23 5.067c-.285.166-.428.404-.428.737v6.898zM12 15.128l-2.795-1.57v-3.33L12 8.658l2.795 1.57v3.33L12 15.128zm1.796 7.23c-1 0-1.927-.332-2.712-.927l4.686-2.712c.285-.166.428-.404.428-.737v-6.898l1.974 1.142c.167.095.238.238.238.428v5.233c0 2.545-1.974 4.472-4.614 4.472zm-5.637-5.303l-4.544-2.617c-1.308-.761-2.188-2.378-2.188-3.948A4.482 4.482 0 014.21 6.327v5.423c0 .333.143.571.428.738l5.947 3.449-1.95 1.118a.432.432 0 01-.476 0zm-.262 3.9c-2.688 0-4.662-2.021-4.662-4.519 0-.19.024-.38.047-.57l4.686 2.71c.286.167.571.167.856 0l5.97-3.448v2.26c0 .19-.07.333-.237.428l-4.543 2.616c-.619.357-1.356.523-2.117.523zm5.899 2.83a5.947 5.947 0 005.827-4.756C22.287 18.339 24 15.84 24 13.296c0-1.665-.713-3.282-1.998-4.448.119-.5.19-.999.19-1.498 0-3.401-2.759-5.947-5.946-5.947-.642 0-1.26.095-1.88.31A5.962 5.962 0 0010.205 0a5.947 5.947 0 00-5.827 4.757C1.713 5.447 0 7.945 0 10.49c0 1.666.713 3.283 1.998 4.448-.119.5-.19 1-.19 1.499 0 3.401 2.759 5.946 5.946 5.946.642 0 1.26-.095 1.88-.309a5.96 5.96 0 004.162 1.713z"/>
            </svg>
            """
        case .claude:
            // Official Anthropic Claude starburst (viewBox 0 0 24 24)
            svgString = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path fill="#000000" d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"/>
            </svg>
            """
        case .copilot:
            // Official GitHub Copilot mark (viewBox 0 0 24 24)
            svgString = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path fill="#000000" d="M23.922 16.997C23.061 18.492 18.063 22.02 12 22.02 5.937 22.02.939 18.492.078 16.997A.641.641 0 0 1 0 16.741v-2.869a.883.883 0 0 1 .053-.22c.372-.935 1.347-2.292 2.605-2.656.167-.429.414-1.055.644-1.517a10.098 10.098 0 0 1-.052-1.086c0-1.331.282-2.499 1.132-3.368.397-.406.89-.717 1.474-.952C7.255 2.937 9.248 1.98 11.978 1.98c2.731 0 4.767.957 6.166 2.093.584.235 1.077.546 1.474.952.85.869 1.132 2.037 1.132 3.368 0 .368-.014.733-.052 1.086.23.462.477 1.088.644 1.517 1.258.364 2.233 1.721 2.605 2.656a.841.841 0 0 1 .053.22v2.869a.641.641 0 0 1-.078.256Zm-11.75-5.992h-.344a4.359 4.359 0 0 1-.355.508c-.77.947-1.918 1.492-3.508 1.492-1.725 0-2.989-.359-3.782-1.259a2.137 2.137 0 0 1-.085-.104L4 11.746v6.585c1.435.779 4.514 2.179 8 2.179 3.486 0 6.565-1.4 8-2.179v-6.585l-.098-.104s-.033.045-.085.104c-.793.9-2.057 1.259-3.782 1.259-1.59 0-2.738-.545-3.508-1.492a4.359 4.359 0 0 1-.355-.508Zm2.328 3.25c.549 0 1 .451 1 1v2c0 .549-.451 1-1 1-.549 0-1-.451-1-1v-2c0-.549.451-1 1-1Zm-5 0c.549 0 1 .451 1 1v2c0 .549-.451 1-1 1-.549 0-1-.451-1-1v-2c0-.549.451-1 1-1Zm3.313-6.185c.136 1.057.403 1.913.878 2.497.442.544 1.134.938 2.344.938 1.573 0 2.292-.337 2.657-.751.384-.435.558-1.15.558-2.361 0-1.14-.243-1.847-.705-2.319-.477-.488-1.319-.862-2.824-1.025-1.487-.161-2.192.138-2.533.529-.269.307-.437.808-.438 1.578v.021c0 .265.021.562.063.893Zm-1.626 0c.042-.331.063-.628.063-.894v-.02c-.001-.77-.169-1.271-.438-1.578-.341-.391-1.046-.69-2.533-.529-1.505.163-2.347.537-2.824 1.025-.462.472-.705 1.179-.705 2.319 0 1.211.175 1.926.558 2.361.365.414 1.084.751 2.657.751 1.21 0 1.902-.394 2.344-.938.475-.584.742-1.44.878-2.497Z"/>
            </svg>
            """
        case .antigravity:
            // Official Antigravity "A" levitation arch ribbon mark (viewBox 0 0 24 24)
            svgString = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path fill="#000000" d="M12 2.2C8.9 2.2 6.8 5.1 5.1 9.6C3.4 14.1 2.0 18.2 1.2 19.8C0.8 20.6 1.5 21.5 2.3 21.1C3.8 20.3 6.2 18.2 8.2 14.8C9.6 12.4 10.7 8.8 12 8.8C13.3 8.8 14.4 12.4 15.8 14.8C17.8 18.2 20.2 20.3 21.7 21.1C22.5 21.5 23.2 20.6 22.8 19.8C22.0 18.2 20.6 14.1 18.9 9.6C17.2 5.1 15.1 2.2 12 2.2Z"/>
            </svg>
            """
        }
        guard let img = NSImage(data: Data(svgString.utf8)) else {
            return nil
        }
        img.isTemplate = true
        cachedImages[family] = img
        return img
    }

    var body: some View {
        if let nsImage = Self.templateImage(for: family) {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .foregroundStyle(color)
                .frame(width: size, height: size)
        } else {
            Image(systemName: family.iconName)
                .font(.system(size: size * 0.85, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }
}

private struct AgentMeterBrandEmblem: View {
    let dark: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack {
            shape
                .fill(FlatPalette.trackBackground(dark: dark))
                .overlay(
                    shape
                        .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                )

            HStack(spacing: 0.5) {
                Text(">")
                    .foregroundStyle(FlatPalette.accent(dark: dark))
                Text("_")
                    .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .frame(width: 26, height: 26)
    }
}

private struct AgentMeterSettings: View {
    @Bindable var model: AgentMeterModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var appearanceNamespace
    @Namespace private var languageNamespace
    @Namespace private var terminalHostNamespace

    var body: some View {
        let en = model.language == .english
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(en ? "Language" : "语言").font(.callout.weight(.medium))
                languagePicker
                Text(en ? "Default is English. Switch between English and Chinese." : "支持英文与简体中文切换（默认英文）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .modifier(FlatCardSurface())

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(en ? "Launch at Login" : "开机自动启动")
                            .font(.callout.weight(.medium))
                        Text(en
                            ? "Automatically start Agent Meter in the menu bar when you log in."
                            : "登录 macOS 时自动在后台启动 Agent Meter 菜单栏监控。"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: $model.launchAtLoginEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .overlay {
                            PointingHandCursorOverlay(
                                onClick: {
                                    model.launchAtLoginEnabled.toggle()
                                }
                            )
                        }
                }
            }
            .padding(16)
            .modifier(FlatCardSurface())

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(en ? "Global Shortcuts" : "全局快捷键")
                            .font(.callout.weight(.medium))
                        Text(en
                            ? "⌥ + Space to toggle panel · ⌥ + Return to jump to most urgent session"
                            : "⌥ + Space 唤起或收起面板 · ⌥ + Return 跳转到最紧急会话"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: $model.globalHotkeysEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .overlay {
                            PointingHandCursorOverlay(
                                onClick: {
                                    model.globalHotkeysEnabled.toggle()
                                }
                            )
                        }
                }
            }
            .padding(16)
            .modifier(FlatCardSurface())

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(en ? "Prevent Sleep While Working" : "运行期间防止系统休眠")
                                .font(.callout.weight(.medium))
                            if model.isKeepAwakeAssertionActive {
                                Text(en ? "Active" : "保活中")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(FlatPalette.softGoodForeground(dark: colorScheme == .dark))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        Capsule()
                                            .fill(FlatPalette.softGoodBackground(dark: colorScheme == .dark))
                                    )
                            }
                        }
                        Text(en
                            ? "Automatically hold an IOKit power assertion while tasks run, and release when idle or stalled."
                            : "当检测到有 Agent 正在执行任务时自动阻止系统休眠，任务结束或长时卡死后自动释放。"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: $model.preventSleepWhileWorking)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .overlay {
                            PointingHandCursorOverlay(
                                onClick: {
                                    model.preventSleepWhileWorking.toggle()
                                }
                            )
                        }
                }
            }
            .padding(16)
            .modifier(FlatCardSurface())

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(en ? "Completion Sound" : "任务完成提示音")
                            .font(.callout.weight(.medium))
                        Text(en
                            ? "Play a chime when a background or active Agent session finishes."
                            : "当后台或当前 Agent 会话执行结束时播放清脆提示音。"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: $model.completionSoundEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .overlay {
                            PointingHandCursorOverlay(
                                onClick: {
                                    model.completionSoundEnabled.toggle()
                                }
                            )
                        }
                }
            }
            .padding(16)
            .modifier(FlatCardSurface())

            let resolvedHostName = model.resolvedLaunchTerminalHost().displayName
            VStack(alignment: .leading, spacing: 8) {
                Text(en ? "Terminal Host" : "首选终端").font(.callout.weight(.medium))
                terminalHostPicker
                Text(en
                    ? "Preferred terminal for launching or resuming sessions (currently active: \(resolvedHostName))."
                    : "选择新建或恢复会话时使用的目标终端（当前生效：\(resolvedHostName)）。"
                )
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .modifier(FlatCardSurface())

            VStack(alignment: .leading, spacing: 8) {
                Text(en ? "Appearance" : "外观").font(.callout.weight(.medium))
                appearancePicker
                Text(en
                    ? "Supports Dark, Light, and System automatic mode."
                    : "支持暗色、亮色与跟随系统自动切换。"
                )
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .modifier(FlatCardSurface())

            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(en ? "Agent Launch Commands" : "Agent 启动命令")
                            .font(.callout.weight(.medium))
                        Text(en
                            ? "Command executed automatically when opening a new \(resolvedHostName) terminal tab."
                            : "新建会话时在 \(resolvedHostName) 终端标签页中自动执行的命令行。"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.hasCustomLaunchCommands {
                        Text(en ? "Reset All" : "恢复默认")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FlatPalette.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .overlay {
                                PointingHandCursorOverlay(
                                    onClick: {
                                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                            model.resetLaunchCommandsToDefault()
                                        }
                                    }
                                )
                            }
                    }
                }

                VStack(spacing: 9) {
                    ForEach(AgentFamily.allCases) { family in
                        launchCommandEditorRow(for: family)
                    }
                }
            }
            .padding(16)
            .modifier(FlatCardSurface())
        }
    }

    private func launchCommandEditorRow(for family: AgentFamily) -> some View {
        let en = model.language == .english
        let dark = colorScheme == .dark
        let accent = family.accentColor(dark: dark)
        let binding = Binding<String>(
            get: { model.launchCommand(for: family) },
            set: { model.setLaunchCommand($0, for: family) }
        )

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                AgentFamilyGlyph(family: family, color: accent, size: 12)
                Text(family.badgeTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if model.customLaunchCommands[family.rawValue] != nil {
                    Text(en ? "Default" : "默认")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .overlay {
                            PointingHandCursorOverlay(
                                onClick: {
                                    model.setLaunchCommand(family.defaultLaunchCommand, for: family)
                                }
                            )
                        }
                }
            }

            HStack(spacing: 6) {
                Text("$")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                TextField(family.defaultLaunchCommand, text: binding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FlatPalette.terminalWellBackground(dark: dark))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                FlatPalette.hairlineBorder(dark: dark),
                                lineWidth: 1.0
                            )
                    )
            )
        }
    }

    private var languagePicker: some View {
        HStack(spacing: 4) {
            ForEach(AppLanguage.allCases) { lang in
                languageOptionItem(lang: lang)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FlatPalette.trackBackground(dark: colorScheme == .dark))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(FlatPalette.hairlineBorder(dark: colorScheme == .dark), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.language == .english ? "Language" : "语言")
    }

    private func languageOptionItem(lang: AppLanguage) -> some View {
        let dark = colorScheme == .dark
        let selected = model.language == lang
        return Text(lang.title)
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FlatPalette.selectedPillBackground(dark: dark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(dark ? 0.26 : 0.07), radius: 2, x: 0, y: 1)
                        .matchedGeometryEffect(id: "languageIndicator", in: languageNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                PointingHandCursorOverlay(
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                            model.language = lang
                        }
                    }
                )
            }
            .accessibilityValue(selected ? (model.language == .english ? "Selected" : "已选择") : (model.language == .english ? "Not selected" : "未选择"))
    }

    private var terminalHostPicker: some View {
        HStack(spacing: 4) {
            ForEach(PreferredTerminalHost.allCases) { host in
                terminalHostOptionItem(host: host)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FlatPalette.trackBackground(dark: colorScheme == .dark))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(FlatPalette.hairlineBorder(dark: colorScheme == .dark), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.language == .english ? "Terminal Host" : "首选终端")
    }

    private func terminalHostOptionItem(host: PreferredTerminalHost) -> some View {
        let dark = colorScheme == .dark
        let selected = model.preferredTerminalHost == host
        return Text(host.title(language: model.language))
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FlatPalette.selectedPillBackground(dark: dark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(dark ? 0.26 : 0.07), radius: 2, x: 0, y: 1)
                        .matchedGeometryEffect(id: "terminalHostIndicator", in: terminalHostNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                PointingHandCursorOverlay(
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                            model.preferredTerminalHost = host
                        }
                    }
                )
            }
            .accessibilityValue(selected ? (model.language == .english ? "Selected" : "已选择") : (model.language == .english ? "Not selected" : "未选择"))
    }

    private var appearancePicker: some View {
        HStack(spacing: 4) {
            ForEach(AppearanceMode.allCases) { mode in
                appearanceOptionItem(mode: mode)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FlatPalette.trackBackground(dark: colorScheme == .dark))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(FlatPalette.hairlineBorder(dark: colorScheme == .dark), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.language == .english ? "Appearance" : "外观")
    }

    private func appearanceOptionItem(mode: AppearanceMode) -> some View {
        let dark = colorScheme == .dark
        let selected = model.appearanceMode == mode
        return Text(mode.title(in: model.language))
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FlatPalette.selectedPillBackground(dark: dark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(dark ? 0.26 : 0.07), radius: 2, x: 0, y: 1)
                        .matchedGeometryEffect(id: "appearanceIndicator", in: appearanceNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                PointingHandCursorOverlay(
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                            model.appearanceMode = mode
                        }
                    }
                )
            }
            .accessibilityValue(selected ? (model.language == .english ? "Selected" : "已选择") : (model.language == .english ? "Not selected" : "未选择"))
    }
}

private enum AgentVectorBadgeState: Equatable {
    case working
    case needsInput
    case completed
    case stuck
    case idle
}

private struct AgentVectorStatusBadge: View {
    let state: AgentVectorBadgeState
    let dark: Bool
    var phaseOffset: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AgentVectorStatusBadgeLayerView(
            state: state,
            dark: dark,
            reduceMotion: reduceMotion,
            phaseOffset: phaseOffset
        )
        .frame(width: 34, height: 20)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Pure CoreAnimation (`CALayer` + `CABasicAnimation` / `CAKeyframeAnimation`) status badge.
/// Offloads all animation interpolation to macOS WindowServer so SwiftUI's `DisplayLink` remains completely idle (0% CPU).
private struct AgentVectorStatusBadgeLayerView: NSViewRepresentable {
    let state: AgentVectorBadgeState
    let dark: Bool
    let reduceMotion: Bool
    let phaseOffset: Double

    func makeNSView(context: Context) -> BadgeHostView {
        let view = BadgeHostView(frame: NSRect(x: 0, y: 0, width: 34, height: 20))
        view.configure(state: state, dark: dark, reduceMotion: reduceMotion, phaseOffset: phaseOffset)
        return view
    }

    func updateNSView(_ nsView: BadgeHostView, context: Context) {
        nsView.configure(state: state, dark: dark, reduceMotion: reduceMotion, phaseOffset: phaseOffset)
    }

    final class BadgeHostView: NSView {
        private var currentState: AgentVectorBadgeState?
        private var currentDark: Bool?
        private var currentReduceMotion: Bool?
        private let contentLayer = CALayer()
        private let leftGlowLayer = CAGradientLayer()
        private let rightGlowLayer = CAGradientLayer()
        private let borderLayer = CAShapeLayer()
        private let glyphContainer = CALayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = false

            let boundsRect = CGRect(x: 0, y: 0, width: 34, height: 20)
            contentLayer.frame = boundsRect
            contentLayer.cornerRadius = 6.5
            contentLayer.cornerCurve = .continuous
            contentLayer.masksToBounds = true
            layer?.addSublayer(contentLayer)

            leftGlowLayer.frame = CGRect(x: 0, y: 0, width: 14, height: 20)
            leftGlowLayer.startPoint = CGPoint(x: 0, y: 0.5)
            leftGlowLayer.endPoint = CGPoint(x: 1, y: 0.5)
            contentLayer.addSublayer(leftGlowLayer)

            rightGlowLayer.frame = CGRect(x: 20, y: 0, width: 14, height: 20)
            rightGlowLayer.startPoint = CGPoint(x: 0, y: 0.5)
            rightGlowLayer.endPoint = CGPoint(x: 1, y: 0.5)
            contentLayer.addSublayer(rightGlowLayer)

            glyphContainer.frame = boundsRect
            contentLayer.addSublayer(glyphContainer)

            borderLayer.frame = boundsRect
            let insetRect = boundsRect.insetBy(dx: 0.6, dy: 0.6)
            borderLayer.path = CGPath(roundedRect: insetRect, cornerWidth: 5.9, cornerHeight: 5.9, transform: nil)
            borderLayer.fillColor = nil
            borderLayer.lineWidth = 1.2
            contentLayer.addSublayer(borderLayer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, let s = currentState, let d = currentDark, let rm = currentReduceMotion {
                currentState = nil
                configure(state: s, dark: d, reduceMotion: rm, phaseOffset: 0)
            }
        }

        func configure(state: AgentVectorBadgeState, dark: Bool, reduceMotion: Bool, phaseOffset: Double) {
            guard currentState != state || currentDark != dark || currentReduceMotion != reduceMotion else { return }
            currentState = state
            currentDark = dark
            currentReduceMotion = reduceMotion

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            let p = Self.palette(for: state, dark: dark)
            contentLayer.backgroundColor = p.bgTint
            leftGlowLayer.colors = [p.sideGlow, NSColor.clear.cgColor]
            rightGlowLayer.colors = [NSColor.clear.cgColor, p.sideGlow]
            borderLayer.strokeColor = p.borderColor

            glyphContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
            glyphContainer.removeAllAnimations()

            let cx: CGFloat = 17.0
            let cy: CGFloat = 10.0

            switch state {
            case .working:
                let eyeGroup = CALayer()
                eyeGroup.frame = CGRect(x: 0, y: 0, width: 34, height: 20)
                let eyeW: CGFloat = 3.1
                let eyeH: CGFloat = 5.2
                let gap: CGFloat = 3.3
                for offsetX in [-gap, gap] {
                    let eye = CALayer()
                    eye.frame = CGRect(x: cx + offsetX - eyeW / 2.0, y: cy - eyeH / 2.0, width: eyeW, height: eyeH)
                    eye.cornerRadius = 1.4
                    eye.cornerCurve = .continuous
                    eye.backgroundColor = p.primaryColor
                    if !reduceMotion {
                        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
                        blink.values = [1.0, 1.0, 0.15, 1.0, 1.0]
                        blink.keyTimes = [0.0, 0.72, 0.78, 0.84, 1.0]
                        blink.duration = 2.6
                        blink.repeatCount = .infinity
                        blink.beginTime = CACurrentMediaTime() + (phaseOffset.truncatingRemainder(dividingBy: 1.2))
                        eye.add(blink, forKey: "blink")
                    }
                    eyeGroup.addSublayer(eye)
                }
                glyphContainer.addSublayer(eyeGroup)
                if !reduceMotion {
                    let scan = CABasicAnimation(keyPath: "transform.translation.x")
                    scan.fromValue = -2.4
                    scan.toValue = 2.4
                    scan.duration = 0.95
                    scan.autoreverses = true
                    scan.repeatCount = .infinity
                    scan.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    scan.beginTime = CACurrentMediaTime() + (phaseOffset.truncatingRemainder(dividingBy: 0.7))
                    eyeGroup.add(scan, forKey: "scan")
                }

            case .completed:
                // Happy arc eyes ^ ^ (flipped coordinate space: in default CALayer on macOS y=0 is bottom)
                let arcLayer = CAShapeLayer()
                arcLayer.frame = CGRect(x: 0, y: 0, width: 34, height: 20)
                let path = CGMutablePath()
                let gap: CGFloat = 3.4
                for offsetX in [-gap, gap] {
                    let ox = cx + offsetX
                    path.move(to: CGPoint(x: ox - 2.1, y: cy - 1.1))
                    path.addQuadCurve(to: CGPoint(x: ox + 2.1, y: cy - 1.1), control: CGPoint(x: ox, y: cy + 2.2))
                }
                arcLayer.path = path
                arcLayer.fillColor = nil
                arcLayer.strokeColor = p.primaryColor
                arcLayer.lineWidth = 1.85
                arcLayer.lineCap = .round
                arcLayer.lineJoin = .round
                glyphContainer.addSublayer(arcLayer)
                if !reduceMotion {
                    let bob = CABasicAnimation(keyPath: "transform.translation.y")
                    bob.fromValue = -0.35
                    bob.toValue = 0.45
                    bob.duration = 1.2
                    bob.autoreverses = true
                    bob.repeatCount = .infinity
                    bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    arcLayer.add(bob, forKey: "bob")
                }

            case .stuck:
                let xLayer = CAShapeLayer()
                xLayer.frame = CGRect(x: 0, y: 0, width: 34, height: 20)
                let path = CGMutablePath()
                let gap: CGFloat = 3.6
                let r: CGFloat = 2.05
                for offsetX in [-gap, gap] {
                    let ox = cx + offsetX
                    path.move(to: CGPoint(x: ox - r, y: cy - r))
                    path.addLine(to: CGPoint(x: ox + r, y: cy + r))
                    path.move(to: CGPoint(x: ox + r, y: cy - r))
                    path.addLine(to: CGPoint(x: ox - r, y: cy + r))
                }
                xLayer.path = path
                xLayer.fillColor = nil
                xLayer.strokeColor = p.primaryColor
                xLayer.lineWidth = 1.85
                xLayer.lineCap = .round
                xLayer.lineJoin = .round
                glyphContainer.addSublayer(xLayer)
                if !reduceMotion {
                    let pulse = CABasicAnimation(keyPath: "opacity")
                    pulse.fromValue = 0.55
                    pulse.toValue = 1.0
                    pulse.duration = 0.55
                    pulse.autoreverses = true
                    pulse.repeatCount = .infinity
                    pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    xLayer.add(pulse, forKey: "pulse")
                }

            case .needsInput, .idle:
                let chevLayer = CAShapeLayer()
                chevLayer.frame = CGRect(x: 0, y: 0, width: 34, height: 20)
                let chevPath = CGMutablePath()
                let chevronX = cx - 3.8
                chevPath.move(to: CGPoint(x: chevronX - 1.5, y: cy + 2.7))
                chevPath.addLine(to: CGPoint(x: chevronX + 1.4, y: cy))
                chevPath.addLine(to: CGPoint(x: chevronX - 1.5, y: cy - 2.7))
                chevLayer.path = chevPath
                chevLayer.fillColor = nil
                chevLayer.strokeColor = p.primaryColor
                chevLayer.lineWidth = 1.85
                chevLayer.lineCap = .round
                chevLayer.lineJoin = .round
                glyphContainer.addSublayer(chevLayer)

                let underLayer = CAShapeLayer()
                underLayer.frame = CGRect(x: 0, y: 0, width: 34, height: 20)
                let underPath = CGMutablePath()
                underPath.move(to: CGPoint(x: cx + 0.8, y: cy - 2.6))
                underPath.addLine(to: CGPoint(x: cx + 5.0, y: cy - 2.6))
                underLayer.path = underPath
                underLayer.fillColor = nil
                underLayer.strokeColor = p.secondaryColor
                underLayer.lineWidth = 1.85
                underLayer.lineCap = .round
                glyphContainer.addSublayer(underLayer)

                if !reduceMotion {
                    let blink = CABasicAnimation(keyPath: "opacity")
                    blink.fromValue = 0.16
                    blink.toValue = 1.0
                    blink.duration = (state == .needsInput) ? 0.32 : 1.35
                    blink.autoreverses = true
                    blink.repeatCount = .infinity
                    blink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    underLayer.add(blink, forKey: "cursorBlink")
                }
            }

            CATransaction.commit()
        }

        private struct CGPalette {
            let primaryColor: CGColor
            let secondaryColor: CGColor
            let bgTint: CGColor
            let sideGlow: CGColor
            let borderColor: CGColor
        }

        private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
            CGColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
        }

        private static func palette(for state: AgentVectorBadgeState, dark: Bool) -> CGPalette {
            switch (state, dark) {
            case (.working, true):
                return CGPalette(
                    primaryColor: rgba(96, 165, 250),
                    secondaryColor: rgba(147, 197, 253),
                    bgTint: rgba(16, 25, 41),
                    sideGlow: rgba(59, 130, 246, 0.20),
                    borderColor: rgba(96, 165, 250, 0.48)
                )
            case (.working, false):
                return CGPalette(
                    primaryColor: rgba(37, 99, 235),
                    secondaryColor: rgba(59, 130, 246),
                    bgTint: rgba(239, 246, 255),
                    sideGlow: rgba(59, 130, 246, 0.12),
                    borderColor: rgba(37, 99, 235, 0.32)
                )
            case (.needsInput, true):
                return CGPalette(
                    primaryColor: rgba(253, 230, 138),
                    secondaryColor: rgba(251, 191, 36),
                    bgTint: rgba(33, 24, 9),
                    sideGlow: rgba(245, 158, 11, 0.24),
                    borderColor: rgba(251, 191, 36, 0.62)
                )
            case (.needsInput, false):
                return CGPalette(
                    primaryColor: rgba(180, 83, 9),
                    secondaryColor: rgba(217, 119, 6),
                    bgTint: rgba(255, 251, 235),
                    sideGlow: rgba(245, 158, 11, 0.15),
                    borderColor: rgba(217, 119, 6, 0.40)
                )
            case (.completed, true):
                return CGPalette(
                    primaryColor: rgba(74, 222, 128),
                    secondaryColor: rgba(134, 239, 172),
                    bgTint: rgba(11, 30, 22),
                    sideGlow: rgba(16, 185, 129, 0.22),
                    borderColor: rgba(74, 222, 128, 0.50)
                )
            case (.completed, false):
                return CGPalette(
                    primaryColor: rgba(5, 150, 105),
                    secondaryColor: rgba(16, 185, 129),
                    bgTint: rgba(236, 253, 245),
                    sideGlow: rgba(16, 185, 129, 0.12),
                    borderColor: rgba(5, 150, 105, 0.34)
                )
            case (.stuck, true):
                return CGPalette(
                    primaryColor: rgba(248, 113, 113),
                    secondaryColor: rgba(239, 68, 68),
                    bgTint: rgba(34, 13, 16),
                    sideGlow: rgba(239, 68, 68, 0.24),
                    borderColor: rgba(248, 113, 113, 0.58)
                )
            case (.stuck, false):
                return CGPalette(
                    primaryColor: rgba(220, 38, 38),
                    secondaryColor: rgba(239, 68, 68),
                    bgTint: rgba(254, 242, 242),
                    sideGlow: rgba(239, 68, 68, 0.14),
                    borderColor: rgba(220, 38, 38, 0.38)
                )
            case (.idle, true):
                return CGPalette(
                    primaryColor: rgba(148, 163, 184),
                    secondaryColor: rgba(203, 213, 225),
                    bgTint: rgba(20, 23, 32),
                    sideGlow: rgba(148, 163, 184, 0.08),
                    borderColor: rgba(255, 255, 255, 0.14)
                )
            case (.idle, false):
                return CGPalette(
                    primaryColor: rgba(100, 116, 139),
                    secondaryColor: rgba(71, 85, 105),
                    bgTint: rgba(241, 245, 249),
                    sideGlow: rgba(100, 116, 139, 0.06),
                    borderColor: rgba(15, 23, 42, 0.13)
                )
            }
        }
    }
}

private struct UnreadCompletionBeacon: View {
    let dark: Bool

    private var dotColor: Color {
        FlatPalette.dangerInterruptForeground(dark: dark)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(dotColor.opacity(0.24))
                .frame(width: 11, height: 11)
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
        }
    }
}

struct AgentMiniConfirmCardView: View {
    @Bindable var model: AgentMeterModel
    let item: AgentActivityItem

    @State private var isAllow1Hovered = false
    @State private var isAllow2Hovered = false
    @State private var isDenyHovered = false
    @State private var isReplyToggleHovered = false
    @State private var isQuickSendHovered = false
    @State private var showInlineReply = false
    @State private var isReplyFocused = false
    @State private var replyDraft = ""
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var previewLines: [String] {
        let en = model.language == .english
        var lines = Array(item.terminalPreviewLines.suffix(5))
        if lines.count < 4 {
            let cwdDisplay: String = {
                if !item.cwdPath.isEmpty { return item.cwdPath }
                return item.workspace
            }()
            if !lines.contains(where: { $0.contains(cwdDisplay) }) && !cwdDisplay.isEmpty {
                lines.insert("cwd: \(cwdDisplay)" + (item.gitBranch.map { " (\($0))" } ?? ""), at: 0)
            }
            if !lines.contains(where: { $0.lowercased().contains("do you want") || $0.contains("确认") || $0.contains("allow") }) {
                lines.append(en ? "Do you want to proceed with this action?" : "是否允许终端执行上述操作？")
            }
            if !lines.contains(where: { $0.hasPrefix("1.") || $0.hasPrefix("❯ 1.") }) {
                lines.append(en ? "❯ 1. Yes, allow once" : "❯ 1. 允许本次执行 (Enter)")
                lines.append(en ? "  2. Always allow in this session  ·  Esc Deny" : "  2. 本次会话始终允许  ·  Esc 拒绝")
            }
        }
        return Array(lines.suffix(5))
    }

    var body: some View {
        let dark = (model.appearanceMode.colorScheme ?? systemColorScheme) == .dark
        let en = model.language == .english
        let familyColor = item.family.accentColor(dark: dark)
        let cardShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let amber = FlatPalette.amberAlertForeground(dark: dark)
        let greenFg = FlatPalette.softGoodForeground(dark: dark)
        let greenBg = FlatPalette.softGoodBackground(dark: dark, hovered: isAllow1Hovered)
        let raisedFg = FlatPalette.inkPrimary(dark: dark)
        let btnShape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        let shortWorkspace: String = {
            if let ssh = item.sshTarget, !ssh.isEmpty {
                return ssh
            }
            if !item.workspace.isEmpty {
                return item.workspace
            }
            return URL(fileURLWithPath: item.cwdPath).lastPathComponent
        }()

        VStack(alignment: .leading, spacing: 5) {
            // 1. Single-Line Compact Header (20pt height)
            HStack(alignment: .center, spacing: 6) {
                AgentFamilyBadgeIcon(
                    family: item.family,
                    dark: dark,
                    highlighted: true,
                    size: 20
                )

                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Text(item.terminalHost.displayName)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                        .padding(.horizontal, 4.5)
                        .frame(height: 15)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(FlatPalette.trackBackground(dark: dark))
                        )

                    if !shortWorkspace.isEmpty {
                        Text(shortWorkspace)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                            .lineLimit(1)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                AgentVectorStatusBadge(state: .needsInput, dark: dark)
                    .scaleEffect(0.84)
                    .frame(width: 28, height: 17)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en ? "Click to focus \(item.terminalHost.displayName) session · Swipe up with two fingers to hide" : "点击跳转到 \(item.terminalHost.displayName) 会话 · 双指上滑隐藏卡片",
                    onClick: {
                        model.jumpToAgentSession(item)
                    }
                )
            }

            // 2. Compact 5-Line Terminal Preview Well
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 1.5) {
                    ForEach(Array(previewLines.enumerated()), id: \.offset) { idx, line in
                        let isFirst = idx == 0
                        let isHighlighted = isFirst
                            || line.hasPrefix("⏺")
                            || line.hasPrefix("❯")
                            || line.lowercased().contains("do you want")
                            || line.lowercased().contains("allow")
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            if isFirst {
                                Text("❯")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(FlatPalette.terminalSigil(dark: dark))
                            } else {
                                Color.clear.frame(width: 7, height: 1)
                            }
                            Text(line)
                                .font(.system(size: 10.8, weight: .regular, design: .monospaced))
                                .foregroundStyle(isHighlighted ? FlatPalette.inkPrimary(dark: dark) : FlatPalette.inkSecondary(dark: dark))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .contentShape(Rectangle())
                .overlay {
                    PointingHandCursorOverlay(
                        tooltip: en ? "Click to focus \(item.terminalHost.displayName) session · Swipe up with two fingers to hide" : "点击跳转到 \(item.terminalHost.displayName) 会话 · 双指上滑隐藏卡片",
                        onClick: {
                            model.jumpToAgentSession(item)
                        }
                    )
                }

                if showInlineReply {
                    Rectangle()
                        .fill(FlatPalette.faintBorder(dark: dark))
                        .frame(height: 1)
                        .padding(.top, 2)

                    HStack(alignment: .center, spacing: 5) {
                        Text("❯")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(familyColor)

                        InlinePromptTextField(
                            text: $replyDraft,
                            placeholder: en ? "Reply to \(item.terminalHost.displayName)… (Enter)" : "输入回复发送至 \(item.terminalHost.displayName)…（回车）",
                            dark: dark,
                            requestFocus: isReplyFocused,
                            onFocusChange: { focused in
                                isReplyFocused = focused
                            },
                            onSubmit: {
                                submitMiniReply()
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)

                        let hasText = !replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        HStack(spacing: 2.5) {
                            Text(en ? "Send" : "发送")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("⏎")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(hasText || isQuickSendHovered ? familyColor : FlatPalette.inkSecondary(dark: dark))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(
                                    hasText || isQuickSendHovered
                                        ? familyColor.opacity(dark ? 0.22 : 0.13)
                                        : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                                )
                        )
                        .overlay {
                            PointingHandCursorOverlay(
                                onHoverChange: { isQuickSendHovered = $0 },
                                onClick: { submitMiniReply() }
                            )
                        }
                    }
                    .padding(.top, 1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(FlatPalette.terminalWellBackground(dark: dark))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                    )
            )

            // 3. Compact 21pt Bottom Approval Action Bar
            HStack(alignment: .center, spacing: 6) {
                HStack(spacing: 4.5) {
                    Circle()
                        .fill(amber)
                        .frame(width: 5.5, height: 5.5)
                    Text(en ? "Awaiting confirmation" : "等待终端权限确认")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(amber)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    // 1. Primary Approve: Allow ⏎ / 允许 ⏎
                    HStack(spacing: 3.5) {
                        Text(en ? "Allow" : "允许")
                            .font(.system(size: 11, weight: .medium))
                        Text("⏎")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .opacity(0.75)
                    }
                    .foregroundStyle(greenFg)
                    .padding(.horizontal, 7.5)
                    .frame(height: 21)
                    .background(
                        btnShape
                            .fill(greenBg)
                            .overlay(
                                btnShape.strokeBorder(greenFg.opacity(0.28), lineWidth: 1)
                            )
                    )
                    .overlay {
                        PointingHandCursorOverlay(
                            tooltip: en ? "Send Enter to approve (Option 1)" : "发送回车确认允许（选项 1）",
                            onHoverChange: { isAllow1Hovered = $0 },
                            onClick: {
                                model.respondToPermission(item, choice: .approvePrimary)
                            }
                        )
                    }

                    // 2. Option 2: 2
                    Text("2")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(raisedFg)
                        .padding(.horizontal, 7.5)
                        .frame(height: 21)
                        .background(
                            btnShape
                                .fill(FlatPalette.raisedBackground(dark: dark, hovered: isAllow2Hovered))
                                .overlay(
                                    btnShape.strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                                )
                        )
                        .overlay {
                            PointingHandCursorOverlay(
                                tooltip: en ? "Select Option 2 and confirm (e.g. Always allow)" : "选择第 2 项并确认（如：始终允许）",
                                onHoverChange: { isAllow2Hovered = $0 },
                                onClick: {
                                    model.respondToPermission(item, choice: .approveSecondary)
                                }
                            )
                        }

                    // 3. Deny: Deny Esc / 拒绝 Esc
                    HStack(spacing: 3.5) {
                        Text(en ? "Deny" : "拒绝")
                            .font(.system(size: 11, weight: .medium))
                        Text("Esc")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .opacity(0.75)
                    }
                    .foregroundStyle(raisedFg)
                    .padding(.horizontal, 7.5)
                    .frame(height: 21)
                    .background(
                        btnShape
                            .fill(FlatPalette.raisedBackground(dark: dark, hovered: isDenyHovered))
                            .overlay(
                                btnShape.strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                            )
                    )
                    .overlay {
                        PointingHandCursorOverlay(
                            tooltip: en ? "Send deny or Esc to cancel" : "发送拒绝指令或 Esc 取消",
                            onHoverChange: { isDenyHovered = $0 },
                            onClick: {
                                model.respondToPermission(item, choice: .deny)
                            }
                        )
                    }

                    // 4. Custom Reply Toggle Button: "/"
                    Text("/")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(raisedFg)
                        .padding(.horizontal, 7.5)
                        .frame(height: 21)
                        .background(
                            btnShape
                                .fill(FlatPalette.raisedBackground(dark: dark, hovered: showInlineReply || isReplyToggleHovered))
                                .overlay(
                                    btnShape.strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                                )
                        )
                        .overlay {
                            PointingHandCursorOverlay(
                                tooltip: en ? "Type a custom reply" : "输入自定义回复",
                                onHoverChange: { isReplyToggleHovered = $0 },
                                onClick: {
                                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16)) {
                                        showInlineReply.toggle()
                                        isReplyFocused = showInlineReply
                                    }
                                }
                            )
                        }
                }
            }
            .frame(height: 21)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: 392)
        .background {
            cardShape
                .fill(FlatPalette.cardBackground(dark: dark))
                .overlay {
                    cardShape
                        .strokeBorder(
                            Color(red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255).opacity(0.34),
                            lineWidth: 1.2
                        )
                }
        }
        .environment(\.colorScheme, model.appearanceMode.colorScheme ?? systemColorScheme)
    }

    private func submitMiniReply() {
        let trimmed = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replyDraft = ""
        showInlineReply = false
        isReplyFocused = false
        model.submitOrQueueReply(item, text: trimmed)
    }
}

struct AgentPiPCardView: View {
    @Bindable var model: AgentMeterModel
    let item: AgentActivityItem
    var onCardHoverChange: ((Bool) -> Void)? = nil

    @State private var isCollapseHovered = false
    @State private var isJumpHovered = false
    @State private var isCloseHovered = false
    @State private var isAllow1Hovered = false
    @State private var isAllow2Hovered = false
    @State private var isDenyHovered = false
    @State private var isStopHovered = false
    @State private var isReplyToggleHovered = false
    @State private var isQuickSendHovered = false
    @State private var showInlineReply = false
    @State private var isReplyFocused = false
    @State private var replyDraft = ""
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var badgeState: AgentVectorBadgeState {
        switch item.status {
        case .needsInput:
            return .needsInput
        case .working:
            return item.isLongRunningWorking() ? .stuck : .working
        case .completed:
            return .completed
        case .idle:
            return .idle
        }
    }

    /// Always returns 5 lines so the PiP terminal well maintains a constant 5-line height across all states.
    private var fivePreviewLines: [String] {
        let en = model.language == .english
        var lines = Array(item.terminalPreviewLines.suffix(5))

        if lines.isEmpty, let detail = item.detail, !detail.isEmpty {
            lines.append(detail)
        }

        if lines.count < 5 {
            var supplemental: [String] = []
            let cwdDisplay = !item.cwdPath.isEmpty ? item.cwdPath : item.workspace
            if !cwdDisplay.isEmpty, !lines.contains(where: { $0.contains(cwdDisplay) }) {
                let branchSuffix = item.gitBranch.map { " (\($0))" } ?? ""
                supplemental.append("cwd: \(cwdDisplay)\(branchSuffix)")
            }
            if let progress = item.taskProgress, progress.totalCount > 0 {
                let stepStr = progress.activeStepTitle.map { " · \($0)" } ?? ""
                supplemental.append(
                    en
                        ? "☑ Tasks \(progress.completedCount)/\(progress.totalCount)\(stepStr)"
                        : "☑ 任务进度 \(progress.completedCount)/\(progress.totalCount)\(stepStr)"
                )
            }
            if let diff = item.gitDiff, !diff.isEmpty {
                supplemental.append(
                    en
                        ? "Git working tree: \(diff.changedFiles) file(s) (+\(diff.insertions) -\(diff.deletions))"
                        : "Git 变更：\(diff.changedFiles) 个文件 (+\(diff.insertions) -\(diff.deletions))"
                )
            }
            if item.status == .needsInput {
                if !lines.contains(where: { $0.lowercased().contains("do you want") || $0.contains("确认") || $0.contains("allow") }) {
                    supplemental.append(en ? "Do you want to proceed with this action?" : "是否允许终端执行上述操作？")
                }
                if !lines.contains(where: { $0.hasPrefix("1.") || $0.hasPrefix("❯ 1.") }) {
                    supplemental.append(en ? "❯ 1. Yes, allow once  ·  2. Always allow" : "❯ 1. 允许本次执行  ·  2. 始终允许")
                }
            } else if item.status == .completed {
                supplemental.append(en ? "✓ Turn completed · ready for next prompt" : "✓ 当前轮次已完成 · 随时可发送下一条指令")
            } else if item.status == .working {
                supplemental.append(
                    en
                        ? "Streaming live output from \(item.terminalHost.displayName)…"
                        : "正在从 \(item.terminalHost.displayName) 实时同步终端输出…"
                )
            } else {
                supplemental.append(
                    en
                        ? "Standing by in \(item.terminalHost.displayName)"
                        : "在 \(item.terminalHost.displayName) 中待命"
                )
            }

            for extra in supplemental where lines.count < 5 {
                if !lines.contains(extra) {
                    lines.append(extra)
                }
            }
            while lines.count < 5 {
                lines.append(" ")
            }
        }
        return Array(lines.suffix(5))
    }

    var body: some View {
        let dark = (model.appearanceMode.colorScheme ?? systemColorScheme) == .dark
        let en = model.language == .english
        let familyColor = item.family.accentColor(dark: dark)
        let isCollapsed = model.isPiPCollapsedPill
        let radius: CGFloat = isCollapsed ? 18 : 11
        let cardShape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        let shortWorkspace: String = {
            if let ssh = item.sshTarget, !ssh.isEmpty {
                return ssh
            }
            if !item.workspace.isEmpty {
                return item.workspace
            }
            return URL(fileURLWithPath: item.cwdPath).lastPathComponent
        }()

        let hostAndWorkspace = shortWorkspace.isEmpty
            ? item.terminalHost.displayName
            : "\(item.terminalHost.displayName) · \(shortWorkspace)"

        let borderColor: Color = {
            switch badgeState {
            case .needsInput:
                return Color(red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255).opacity(0.45)
            case .stuck:
                return Color(red: 239.0 / 255, green: 68.0 / 255, blue: 68.0 / 255).opacity(0.45)
            case .working, .completed, .idle:
                return familyColor.opacity(dark ? 0.38 : 0.30)
            }
        }()

        VStack(alignment: .leading, spacing: isCollapsed ? 0 : 6) {
            // 1. Single-Line Header (Drag Handle + Double-Click to Collapse/Expand)
            HStack(alignment: .center, spacing: 6) {
                AgentFamilyBadgeIcon(
                    family: item.family,
                    dark: dark,
                    highlighted: true,
                    size: 20
                )

                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlatPalette.inkPrimary(dark: dark))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !isCollapsed {
                    Text(hostAndWorkspace)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                        .padding(.horizontal, 4.5)
                        .frame(height: 15)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(FlatPalette.trackBackground(dark: dark))
                        )
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                AgentVectorStatusBadge(state: badgeState, dark: dark)
                    .scaleEffect(0.84)
                    .frame(width: 28, height: 17)

                HStack(spacing: 3) {
                    pipWindowControlButton(
                        symbol: isCollapsed ? "rectangle.expand.vertical" : "minus",
                        hovered: isCollapseHovered,
                        active: false,
                        tooltip: isCollapsed
                            ? (en ? "Expand to 5-line monitor" : "展开为 5 行盯盘卡片")
                            : (en ? "Collapse into mini pill" : "折叠为迷你悬浮胶囊"),
                        dark: dark,
                        onHover: { isCollapseHovered = $0 },
                        action: {
                            withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                model.togglePiPCollapsedPill()
                            }
                        }
                    )

                    pipWindowControlButton(
                        symbol: "arrow.up.right",
                        hovered: isJumpHovered,
                        active: false,
                        tooltip: en ? "Focus \(item.terminalHost.displayName) window" : "跳转到 \(item.terminalHost.displayName) 终端窗口",
                        dark: dark,
                        onHover: { isJumpHovered = $0 },
                        action: {
                            model.jumpToAgentSession(item)
                        }
                    )

                    pipWindowControlButton(
                        symbol: "xmark",
                        hovered: isCloseHovered,
                        active: true,
                        tooltip: en ? "Close Picture-in-Picture" : "关闭画中画盯盘",
                        dark: dark,
                        onHover: { isCloseHovered = $0 },
                        action: {
                            model.closePiP()
                        }
                    )
                }
            }
            .frame(height: 22)

            if !isCollapsed {
                // 2. Constant 5-Line Live Terminal Preview Box
                VStack(alignment: .leading, spacing: 3) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        ForEach(Array(fivePreviewLines.enumerated()), id: \.offset) { idx, line in
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            let isFirst = idx == 0
                            let isPrimary = isFirst
                                || trimmed.hasPrefix("⏺")
                                || trimmed.hasPrefix("❯")
                                || trimmed.hasPrefix("✓")
                                || trimmed.hasPrefix("⚠")
                                || trimmed.lowercased().contains("do you want")
                            let lineColor: Color = {
                                if isPrimary {
                                    return FlatPalette.inkPrimary(dark: dark)
                                }
                                if trimmed.hasPrefix("+ ") {
                                    return FlatPalette.diffAddForeground(dark: dark)
                                }
                                if trimmed.hasPrefix("- ") {
                                    return FlatPalette.diffDeleteForeground(dark: dark)
                                }
                                return FlatPalette.inkSecondary(dark: dark)
                            }()

                            HStack(alignment: .firstTextBaseline, spacing: 5.5) {
                                if isFirst {
                                    Text(item.status == .needsInput ? "❯" : "›")
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(FlatPalette.terminalSigil(dark: dark))
                                } else {
                                    Color.clear.frame(width: 7, height: 1)
                                }
                                Text(line)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(lineColor)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 14)
                        }
                    }
                    .frame(height: 78, alignment: .topLeading)

                    if showInlineReply {
                        Rectangle()
                            .fill(FlatPalette.faintBorder(dark: dark))
                            .frame(height: 1)
                            .padding(.top, 2)

                        HStack(alignment: .center, spacing: 5) {
                            Text(item.status == .working ? "⏳" : "❯")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(familyColor)

                            InlinePromptTextField(
                                text: $replyDraft,
                                placeholder: item.status == .working
                                    ? (en ? "Queue next prompt… (Enter)" : "排队下一条指令…（回车）")
                                    : (en ? "Send prompt to \(item.terminalHost.displayName)… (Enter)" : "发送指令至 \(item.terminalHost.displayName)…（回车）"),
                                dark: dark,
                                requestFocus: isReplyFocused,
                                onFocusChange: { focused in
                                    isReplyFocused = focused
                                },
                                onSubmit: {
                                    submitPiPReply()
                                }
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 18)

                            let hasText = !replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            HStack(spacing: 2.5) {
                                Text(item.status == .working ? (en ? "Queue" : "排队") : (en ? "Send" : "发送"))
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text("⏎")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(hasText || isQuickSendHovered ? familyColor : FlatPalette.inkSecondary(dark: dark))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(
                                        hasText || isQuickSendHovered
                                            ? familyColor.opacity(dark ? 0.22 : 0.13)
                                            : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                                    )
                            )
                            .overlay {
                                PointingHandCursorOverlay(
                                    onHoverChange: { isQuickSendHovered = $0 },
                                    onClick: { submitPiPReply() }
                                )
                            }
                        }
                        .padding(.top, 1)
                    }
                }
                .padding(.horizontal, 8.5)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(FlatPalette.terminalWellBackground(dark: dark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                        )
                )

                // 3. Bottom Telemetry & Action Bar (21pt height)
                pipFooterBar(dark: dark, familyColor: familyColor)
                    .frame(height: 21)
            }
        }
        .padding(.horizontal, isCollapsed ? 9 : 10)
        .padding(.vertical, isCollapsed ? 6 : 8)
        .frame(width: isCollapsed ? 256 : 392)
        .background {
            cardShape
                .fill(FlatPalette.cardBackground(dark: dark))
                .overlay {
                    cardShape
                        .strokeBorder(borderColor, lineWidth: 1.2)
                }
        }
        .onHover { hovering in
            onCardHoverChange?(hovering)
        }
        .environment(\.colorScheme, model.appearanceMode.colorScheme ?? systemColorScheme)
    }

    private func pipWindowControlButton(
        symbol: String,
        hovered: Bool,
        active: Bool,
        tooltip: String,
        dark: Bool,
        onHover: @escaping (Bool) -> Void,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let accentFg = FlatPalette.accentText(dark: dark)
        return Image(systemName: symbol)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(
                hovered
                    ? FlatPalette.inkPrimary(dark: dark)
                    : (active ? accentFg : FlatPalette.inkSecondary(dark: dark))
            )
            .frame(width: 19, height: 19)
            .background(
                shape
                    .fill(
                        hovered
                            ? FlatPalette.raisedBackground(dark: dark, hovered: true)
                            : (active ? FlatPalette.accentSoftBackground(dark: dark) : FlatPalette.trackBackground(dark: dark))
                    )
                    .overlay(
                        shape.strokeBorder(
                            active ? accentFg.opacity(0.32) : FlatPalette.faintBorder(dark: dark),
                            lineWidth: 1
                        )
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: tooltip,
                    onHoverChange: onHover,
                    onClick: action
                )
            }
    }

    @ViewBuilder
    private func pipFooterBar(dark: Bool, familyColor: Color) -> some View {
        let en = model.language == .english
        let btnShape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let raisedFg = FlatPalette.inkPrimary(dark: dark)
        let greenFg = FlatPalette.softGoodForeground(dark: dark)
        let greenBg = FlatPalette.softGoodBackground(dark: dark, hovered: isAllow1Hovered)
        let stopFg = FlatPalette.dangerInterruptForeground(dark: dark)
        let stopBg = FlatPalette.dangerInterruptBackground(dark: dark, hovered: isStopHovered)
        let amber = FlatPalette.amberAlertForeground(dark: dark)

        HStack(alignment: .center, spacing: 6) {
            if badgeState == .needsInput {
                HStack(spacing: 4.5) {
                    Circle()
                        .fill(amber)
                        .frame(width: 5.5, height: 5.5)
                    Text(en ? "Awaiting confirmation" : "等待权限确认")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(amber)
                        .lineLimit(1)
                }
            } else if badgeState == .stuck {
                HStack(spacing: 4.5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(stopFg)
                    Text(en ? "Long-running · check if stalled" : "长时运行疑似卡住")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(stopFg)
                        .lineLimit(1)
                }
            } else {
                // Telemetry strip: Diff + Tasks + Context%
                HStack(spacing: 5) {
                    if badgeState == .completed {
                        Text(en ? "✓ Done" : "✓ 已完成")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(greenFg)
                    }
                    if let diff = item.gitDiff, !diff.isEmpty {
                        HStack(spacing: 3) {
                            Text("+\(diff.insertions)")
                                .foregroundStyle(FlatPalette.diffAddForeground(dark: dark))
                            if diff.deletions > 0 {
                                Text("-\(diff.deletions)")
                                    .foregroundStyle(FlatPalette.diffDeleteForeground(dark: dark))
                            }
                        }
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    }
                    if let progress = item.taskProgress, progress.totalCount > 0 {
                        Text("☑ \(progress.completedCount)/\(progress.totalCount)")
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(FlatPalette.inkSecondary(dark: dark))
                    }
                    if let ctx = item.contextPercentUsed {
                        Text("\(ctx)%")
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(ctx >= 60 ? amber : FlatPalette.inkSecondary(dark: dark))
                    }
                    let queuedCount = model.queuedPrompts(for: item).count
                    if queuedCount > 0 {
                        Text(en ? "⏳\(queuedCount) queued" : "⏳\(queuedCount) 排队")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(familyColor)
                    }
                }
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if badgeState == .needsInput {
                HStack(spacing: 4) {
                    HStack(spacing: 3) {
                        Text(en ? "Allow" : "允许")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("⏎")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .opacity(0.75)
                    }
                    .foregroundStyle(greenFg)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(
                        btnShape.fill(greenBg)
                            .overlay(btnShape.strokeBorder(greenFg.opacity(0.28), lineWidth: 1))
                    )
                    .overlay {
                        PointingHandCursorOverlay(
                            onHoverChange: { isAllow1Hovered = $0 },
                            onClick: { model.respondToPermission(item, choice: .approvePrimary) }
                        )
                    }

                    Text("2")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(raisedFg)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            btnShape.fill(FlatPalette.raisedBackground(dark: dark, hovered: isAllow2Hovered))
                                .overlay(btnShape.strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1))
                        )
                        .overlay {
                            PointingHandCursorOverlay(
                                onHoverChange: { isAllow2Hovered = $0 },
                                onClick: { model.respondToPermission(item, choice: .approveSecondary) }
                            )
                        }

                    HStack(spacing: 3) {
                        Text(en ? "Deny" : "拒绝")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("Esc")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .opacity(0.75)
                    }
                    .foregroundStyle(raisedFg)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(
                        btnShape.fill(FlatPalette.raisedBackground(dark: dark, hovered: isDenyHovered))
                            .overlay(btnShape.strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1))
                    )
                    .overlay {
                        PointingHandCursorOverlay(
                            onHoverChange: { isDenyHovered = $0 },
                            onClick: { model.respondToPermission(item, choice: .deny) }
                        )
                    }

                    pipReplyToggleButton(dark: dark, btnShape: btnShape, raisedFg: raisedFg)
                }
            } else {
                HStack(spacing: 4) {
                    if item.status == .working {
                        HStack(spacing: 3) {
                            Text(en ? "Stop" : "中断")
                                .font(.system(size: 10.5, weight: .medium))
                            Text("^C")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .opacity(0.75)
                        }
                        .foregroundStyle(stopFg)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            btnShape.fill(stopBg)
                                .overlay(btnShape.strokeBorder(stopFg.opacity(0.28), lineWidth: 1))
                        )
                        .overlay {
                            PointingHandCursorOverlay(
                                onHoverChange: { isStopHovered = $0 },
                                onClick: { model.interruptAgentSession(item) }
                            )
                        }
                    }

                    pipReplyToggleButton(
                        dark: dark,
                        btnShape: btnShape,
                        raisedFg: raisedFg,
                        label: item.status == .working ? (en ? "/ Queue" : "/ 排队") : (en ? "/ Reply" : "/ 回复")
                    )
                }
            }
        }
    }

    private func pipReplyToggleButton(
        dark: Bool,
        btnShape: RoundedRectangle,
        raisedFg: Color,
        label: String = "/"
    ) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(raisedFg)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                btnShape
                    .fill(FlatPalette.raisedBackground(dark: dark, hovered: showInlineReply || isReplyToggleHovered))
                    .overlay(
                        btnShape.strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    onHoverChange: { isReplyToggleHovered = $0 },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16)) {
                            showInlineReply.toggle()
                            isReplyFocused = showInlineReply
                        }
                    }
                )
            }
    }

    private func submitPiPReply() {
        let trimmed = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replyDraft = ""
        showInlineReply = false
        isReplyFocused = false
        model.submitOrQueueReply(item, text: trimmed)
    }
}

