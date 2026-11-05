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
    @State private var hoveredCloseID: String?
    @State private var hoveredApprovePrimaryID: String?
    @State private var hoveredApproveSecondaryID: String?
    @State private var hoveredDenyID: String?
    @State private var hoveredReplyToggleID: String?
    @State private var hoveredReplyFieldID: String?
    @State private var hoveredQuickCompactID: String?
    @State private var hoveredQuickSendID: String?
    @State private var hoveredWorkspacePath: String?
    @State private var hoveredHistoryID: String?
    @State private var hoveredHistoryDeleteID: String?
    @State private var hoveredHistoryConfirmDeleteID: String?
    @State private var hoveredHistoryCancelDeleteID: String?
    @State private var confirmingHistoryDeleteID: String?
    @State private var replyDrafts: [String: String] = [:]
    @State private var expandedReplyAgentID: String?
    @State private var focusedReplyAgentID: String?
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var filterNamespace
    @Namespace private var launchFamilyNamespace
    @Namespace private var quickLaunchModeNamespace
    @Namespace private var historyFamilyFilterNamespace

    private var filteredActivities: [AgentActivityItem] {
        switch selectedFilter {
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
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if showingSettings {
                        AgentMeterSettings(model: model)
                            .transition(.opacity)
                    } else if showingQuickLaunch {
                        quickLaunchSection(dark: dark)
                            .transition(.opacity)
                    } else {
                        TimelineView(.periodic(from: .now, by: 1.0)) { context in
                            agentDynamicSection(dark: dark, now: context.date)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22), value: model.agentActivities)
                .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.20), value: selectedFilter)
            }
            .scrollIndicators(.automatic)
            .defaultScrollAnchor(.top)

            footer(dark: dark)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(FlatPanelSurface())
        .tint(FlatPalette.blue)
        .background(
            PanelWindowMask(appearanceMode: model.appearanceMode) { visible in
                if visible {
                    model.panelDidOpen()
                } else {
                    model.panelDidClose()
                }
            }
        )
        .environment(\.colorScheme, model.appearanceMode.colorScheme ?? systemColorScheme)
    }

    private func header(dark: Bool) -> some View {
        let en = model.language == .english
        let workingCount = model.activeAgentWorkingCount
        return HStack(alignment: .center, spacing: 10) {
            if showingSettings {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FlatPalette.blue)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(FlatPalette.cardBackground(dark: dark))
                            .shadow(color: .black.opacity(dark ? 0.18 : 0.04), radius: 4, x: 0, y: 1.5)
                    )
            } else if showingQuickLaunch {
                Image(systemName: quickLaunchMode == .newSession ? "plus.rectangle.on.rectangle" : "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.preferredLaunchFamily.accentColor(dark: dark))
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(FlatPalette.cardBackground(dark: dark))
                            .shadow(color: .black.opacity(dark ? 0.18 : 0.04), radius: 4, x: 0, y: 1.5)
                    )
            } else {
                AgentMeterBrandEmblem(dark: dark)
                    .frame(width: 34, height: 34)
            }

            if showingSettings {
                Text(en ? "Settings" : "设置")
                    .font(.system(size: 16, weight: .semibold))
            } else if showingQuickLaunch {
                quickLaunchModeSegmentedControl(dark: dark)
            } else {
                HStack(spacing: 7) {
                    Text("Agent Meter")
                        .font(.system(size: 15.5, weight: .semibold))
                    if model.activeAgentNeedsInputCount > 0 {
                        Text(en ? "\(model.activeAgentNeedsInputCount) Confirm" : "\(model.activeAgentNeedsInputCount) 待确认")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.96, green: 0.64, blue: 0.18))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(
                                    dark
                                        ? Color(red: 0.34, green: 0.23, blue: 0.10)
                                        : Color(red: 1.0, green: 0.94, blue: 0.84)
                                )
                            )
                    } else if workingCount > 0 {
                        Text(en ? "\(workingCount) Running" : "\(workingCount) 运行中")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(FlatPalette.blue)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(
                                    dark
                                        ? Color(red: 0.13, green: 0.23, blue: 0.38)
                                        : Color(red: 0.88, green: 0.93, blue: 1.0)
                                )
                            )
                    } else if !model.agentActivities.isEmpty {
                        Text(en ? "\(model.agentActivities.count) Online" : "\(model.agentActivities.count) 在线")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(FlatPalette.cardBackground(dark: dark)))
                    }
                }
            }

            Spacer(minLength: 0)

            if showingSettings || showingQuickLaunch {
                FlatCapsuleButton(title: en ? "Back" : "返回", compact: true) {
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                        showingSettings = false
                        showingQuickLaunch = false
                        isHistorySearchFocused = false
                    }
                }
            } else {
                HStack(spacing: 8) {
                    FlatIconButton(icon: "plus", iconSize: 13.5, tooltip: en ? "New Agent Session" : "快速新建 Agent 会话") {
                        quickLaunchMode = .newSession
                        model.refreshLaunchWorkspaces()
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                            showingQuickLaunch = true
                        }
                    }

                    FlatIconButton(icon: "clock.arrow.circlepath", iconSize: 13, tooltip: en ? "Resume History Session" : "恢复历史 Agent 会话") {
                        quickLaunchMode = .history
                        model.refreshHistoricalSessions()
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                            showingQuickLaunch = true
                        }
                    }

                    FlatIconButton(icon: "gearshape", rotatesOnHover: true, tooltip: en ? "Settings" : "设置") {
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
        .padding(3)
        .background(
            Capsule()
                .fill(FlatPalette.trackBackground(dark: dark))
                .overlay(
                    Capsule()
                        .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                )
        )
    }

    private func quickLaunchModePill(mode: QuickLaunchMode, dark: Bool) -> some View {
        let isSelected = quickLaunchMode == mode
        let count = mode == .history ? model.historicalSessions.count : 0
        return HStack(spacing: 4) {
            Text(mode.title(in: model.language))
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .opacity(isSelected ? 0.88 : 0.6)
            }
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 4.5)
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
                    .shadow(color: .black.opacity(dark ? 0.28 : 0.08), radius: 2, x: 0, y: 1)
                    .matchedGeometryEffect(id: "quickLaunchModePill", in: quickLaunchModeNamespace)
            }
        }
        .contentShape(Capsule())
        .overlay {
            PointingHandCursorOverlay(
                onClick: {
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
    private func agentDynamicSection(dark: Bool, now: Date) -> some View {
        let en = model.language == .english
        let workingCount = model.activeAgentWorkingCount
        let needsInputCount = model.activeAgentNeedsInputCount
        let unreadCount = model.unreadCompletionCount

        VStack(alignment: .leading, spacing: 10) {
            // Section toolbar: status pulse + filter pills + mark-all-read action
            HStack(spacing: 6) {
                AgentPulseDot(
                    status: needsInputCount > 0
                        ? .needsInput
                        : (workingCount > 0 ? .working : (model.agentActivities.contains { $0.status == .completed } ? .completed : .idle))
                )
                Text(en ? "AGENT ACTIVITY" : "AGENT 动态")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                if unreadCount > 0 {
                    HStack(spacing: 3.5) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.22, blue: 0.44))
                            .frame(width: 5, height: 5)
                        Text(en ? "Read" : "已读")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(dark ? Color(white: 0.90) : Color(white: 0.20))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule()
                            .fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
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
            .padding(.horizontal, 2)

            if model.agentActivities.isEmpty {
                emptyStateCard(
                    icon: "terminal",
                    title: en ? "No active CLI Agent sessions detected" : "当前未检测到正在运行的 CLI Agent",
                    subtitle: en
                        ? "Automatically discovers Codex, Claude, Copilot & Antigravity sessions in Rex"
                        : "支持自动发现本机及 Rex SSH 中的 Codex、Claude、Copilot 与 Antigravity 会话"
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
                VStack(spacing: 11) {
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
        .padding(2.5)
        .background(
            Capsule()
                .fill(FlatPalette.trackBackground(dark: dark))
                .overlay(
                    Capsule()
                        .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                )
        )
    }

    private func filterPillItem(filter: AgentListFilter, dark: Bool) -> some View {
        let isSelected = selectedFilter == filter
        let count = filterCount(for: filter)
        return HStack(spacing: 3) {
            Text(filter.title(in: model.language))
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .opacity(isSelected ? 0.9 : 0.65)
            }
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
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
                    .shadow(color: .black.opacity(dark ? 0.28 : 0.08), radius: 2, x: 0, y: 1)
                    .matchedGeometryEffect(id: "filterPill", in: filterNamespace)
            }
        }
        .contentShape(Capsule())
        .overlay {
            PointingHandCursorOverlay(
                onClick: {
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
        .padding(14)
        .modifier(FlatCardSurface(cornerRadius: 12))
    }

    private func shouldShowExtendedPreview(for item: AgentActivityItem, isHovered: Bool) -> Bool {
        if item.status == .needsInput { return true }
        if isHovered && item.terminalPreviewLines.count > 1 { return true }
        return false
    }

    private func agentActivityRow(_ item: AgentActivityItem, dark: Bool, now: Date) -> some View {
        let isCloseHovered = hoveredCloseID == item.id
        let isApprove1Hovered = hoveredApprovePrimaryID == item.id
        let isApprove2Hovered = hoveredApproveSecondaryID == item.id
        let isDenyHovered = hoveredDenyID == item.id
        let isReplyToggleHovered = hoveredReplyToggleID == item.id
        let isReplyFieldHovered = hoveredReplyFieldID == item.id
        let isQuickCompactHovered = hoveredQuickCompactID == item.id
        let isQuickSendHovered = hoveredQuickSendID == item.id
        let isHovered = hoveredAgentID == item.id
            || isCloseHovered
            || isApprove1Hovered
            || isApprove2Hovered
            || isDenyHovered
            || isReplyToggleHovered
            || isReplyFieldHovered
            || isQuickCompactHovered
            || isQuickSendHovered
        let familyColor = item.family.accentColor(dark: dark)
        let statusColor = agentStatusColor(item.status, dark: dark)
        let isExpanded = shouldShowExtendedPreview(for: item, isHovered: isHovered)
        let hasDraft = !(replyDrafts[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let isReplyFocused = focusedReplyAgentID == item.id
        let showInlineReply: Bool = {
            switch item.status {
            case .completed, .idle:
                return isHovered || isReplyFocused || hasDraft || expandedReplyAgentID == item.id
            case .needsInput:
                return expandedReplyAgentID == item.id || isReplyFocused || hasDraft
            case .working:
                return false
            }
        }()
        let hasPreview = !item.terminalPreviewLines.isEmpty || showInlineReply

        return VStack(alignment: .leading, spacing: 10) {
            agentRowHeader(
                item: item,
                isHovered: isHovered,
                familyColor: familyColor,
                statusColor: statusColor,
                dark: dark,
                now: now
            )

            // Live Micro Terminal Preview Box (100% full width, expands automatically on hover)
            if hasPreview {
                miniTerminalPreview(
                    item: item,
                    expanded: isExpanded,
                    showInlineReply: showInlineReply,
                    familyColor: familyColor,
                    statusColor: statusColor,
                    dark: dark
                )
            }

            // Inline Permission Approval Bar when the session is waiting for confirmation
            if item.status == .needsInput {
                inlineApprovalReserveBar(dark: dark)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Full-card tracking region (never shrinks when expanded, so moving mouse down into the prompt never drops hover)
        .overlay {
            PointingHandCursorOverlay(
                onHoverChange: { hovering in
                    hoveredAgentID = hovering ? item.id : (hoveredAgentID == item.id ? nil : hoveredAgentID)
                },
                onClick: {
                    model.jumpToAgentSession(item)
                }
            )
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                closeSessionButton(item: item, isCloseHovered: isCloseHovered, isRowHovered: isHovered, dark: dark)
                    .offset(x: 5, y: -5)
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
        }
        .overlay(alignment: .bottom) {
            if showInlineReply {
                inlineTerminalReplyPromptBar(
                    item: item,
                    isQuickCompactHovered: isQuickCompactHovered,
                    isQuickSendHovered: isQuickSendHovered,
                    familyColor: familyColor,
                    dark: dark
                )
                .padding(.horizontal, 24)
                .padding(.bottom, item.status == .needsInput ? 56.5 : 20.5)
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
                .padding(.bottom, 13)
                .padding(.trailing, 14)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FlatPalette.elevatedRowBackground(dark: dark, hovered: isHovered))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            rowBorderColor(for: item, isHovered: isHovered, familyColor: familyColor, dark: dark),
                            lineWidth: item.status == .needsInput ? 1.2 : 1.0
                        )
                }
                .shadow(
                    color: .black.opacity(dark ? (isHovered ? 0.24 : 0.14) : (isHovered ? 0.06 : 0.025)),
                    radius: isHovered ? 5 : 2.5,
                    x: 0,
                    y: isHovered ? 2 : 1
                )
        }
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16), value: isHovered)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18), value: isExpanded)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18), value: showInlineReply)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.14), value: isCloseHovered)
        .help(item.title)
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
        let statusLabel: String = {
            switch item.status {
            case .needsInput: return en ? "Confirm" : "待确认"
            case .working: return en ? "Running" : "运行中"
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

        let cacheRemaining = item.cacheWarmRemainingSeconds(now: now)

        return HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                AgentFamilyBadgeIcon(
                    family: item.family,
                    dark: dark,
                    highlighted: item.status == .working || item.status == .needsInput || isHovered,
                    size: 32
                )
                .help(item.family.badgeTitle)

                if item.isUnreadCompletion {
                    UnreadCompletionBeacon()
                        .offset(x: 3, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                // Row 1: Title + Status Badge
                HStack(alignment: .center, spacing: 6) {
                    HStack(spacing: 5.5) {
                        if item.isFocusedInHost {
                            Circle()
                                .fill(familyColor)
                                .frame(width: 5.5, height: 5.5)
                                .help(en ? "Focused terminal window" : "当前焦点终端窗口")
                        }
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 6)

                    // Status badge (incorporates live duration only when running)
                    HStack(spacing: 5) {
                        if item.status == .needsInput {
                            AgentPulseDot(status: .needsInput, size: 5)
                        } else if item.status == .working {
                            AgentPulseDot(status: .working, size: 5)
                        } else if item.status == .completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(statusColor)
                        } else {
                            Circle()
                                .fill(.secondary.opacity(0.45))
                                .frame(width: 5, height: 5)
                        }
                        Text(statusLabel)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(item.status == .idle ? .secondary : statusColor)

                        if let elapsedText {
                            Text(elapsedText)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle((item.status == .idle ? Color.secondary : statusColor).opacity(0.82))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background {
                        Capsule()
                            .fill(statusBadgeFill(item.status, dark: dark))
                            .overlay {
                                Capsule()
                                    .strokeBorder(statusBadgeStroke(item.status, dark: dark), lineWidth: 1)
                            }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                // Row 2: Subtitle + Right-aligned Inline Git Diff, Cache Warm & Context Meter
                HStack(alignment: .center, spacing: 6) {
                    subtitleRow(item: item, familyColor: familyColor)

                    Spacer(minLength: 4)

                    if item.gitDiff != nil || cacheRemaining != nil || item.contextPercentUsed != nil {
                        previewRightAccessory(
                            item: item,
                            cacheRemaining: cacheRemaining,
                            familyColor: familyColor,
                            dark: dark
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
    }

    private func closeSessionButton(
        item: AgentActivityItem,
        isCloseHovered: Bool,
        isRowHovered: Bool,
        dark: Bool
    ) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(
                isCloseHovered
                    ? Color(red: 0.96, green: 0.32, blue: 0.38)
                    : FlatPalette.inkSecondary(dark: dark)
            )
            .frame(width: 20, height: 20)
            .background {
                Circle()
                    .fill(
                        isCloseHovered
                            ? (dark ? Color(red: 0.36, green: 0.14, blue: 0.17) : Color(red: 1.0, green: 0.90, blue: 0.92))
                            : (dark ? Color(red: 0.20, green: 0.20, blue: 0.22) : Color.white)
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isCloseHovered
                                    ? Color(red: 0.96, green: 0.32, blue: 0.38).opacity(0.45)
                                    : (dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(dark ? 0.45 : 0.12), radius: 3, x: 0, y: 1)
            }
            .overlay {
                PointingHandCursorOverlay(
                    onHoverChange: { hovering in
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

        HStack(spacing: 4.5) {
            if let sshTarget = item.sshTarget, !sshTarget.isEmpty {
                HStack(spacing: 3.5) {
                    Image(systemName: "network")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(familyColor.opacity(0.85))
                    Text(sshTarget)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

                if !item.cwdPath.isEmpty {
                    Text("·")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text(displayPath)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(familyColor.opacity(0.85))
                Text(displayPath)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func miniTerminalPreview(
        item: AgentActivityItem,
        expanded: Bool,
        showInlineReply: Bool,
        familyColor: Color,
        statusColor: Color,
        dark: Bool
    ) -> some View {
        let maxVisibleLines = item.status == .needsInput ? 7 : 3
        let lines = expanded
            ? Array(item.terminalPreviewLines.suffix(maxVisibleLines))
            : Array(item.terminalPreviewLines.suffix(1))

        return VStack(alignment: .leading, spacing: 6.5) {
            if !lines.isEmpty {
                previewLinesColumn(
                    item: item,
                    lines: lines,
                    familyColor: familyColor,
                    statusColor: statusColor,
                    dark: dark
                )
            }

            if showInlineReply {
                if !lines.isEmpty {
                    Rectangle()
                        .fill(FlatPalette.hairlineBorder(dark: dark))
                        .frame(height: 1)
                }

                // Reserve space inside the terminal well; the interactive prompt overlay sits right on top
                Color.clear
                    .frame(height: 21)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7.5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(FlatPalette.terminalWellBackground(dark: dark))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            focusedReplyAgentID == item.id
                                ? familyColor.opacity(dark ? 0.55 : 0.45)
                                : FlatPalette.hairlineBorder(dark: dark),
                            lineWidth: 1
                        )
                )
        )
    }

    private func inlineTerminalReplyPromptBar(
        item: AgentActivityItem,
        isQuickCompactHovered: Bool,
        isQuickSendHovered: Bool,
        familyColor: Color,
        dark: Bool
    ) -> some View {
        let en = model.language == .english
        let draftBinding = Binding<String>(
            get: { replyDrafts[item.id] ?? "" },
            set: { replyDrafts[item.id] = $0 }
        )
        let currentDraft = (replyDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !currentDraft.isEmpty

        return HStack(alignment: .center, spacing: 6) {
            Text("❯")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(familyColor)
                .overlay {
                    PointingHandCursorOverlay(
                        onHoverChange: { hovering in
                            hoveredReplyFieldID = hovering ? item.id : (hoveredReplyFieldID == item.id ? nil : hoveredReplyFieldID)
                        },
                        onClick: {
                            focusedReplyAgentID = item.id
                        }
                    )
                }

            InlinePromptTextField(
                text: draftBinding,
                placeholder: en ? "Reply to Rex…" : "发送指令至 Rex…",
                dark: dark,
                requestFocus: focusedReplyAgentID == item.id,
                onHoverChange: { hovering in
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

            if item.family == .claude || item.family == .codex {
                Text("/compact")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isQuickCompactHovered ? familyColor : FlatPalette.inkSecondary(dark: dark))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(
                                isQuickCompactHovered
                                    ? familyColor.opacity(dark ? 0.20 : 0.12)
                                    : (dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                            )
                    )
                    .overlay {
                        PointingHandCursorOverlay(
                            tooltip: en ? "Send /compact to compact context window" : "发送 /compact 压缩上下文窗口",
                            onHoverChange: { hovering in
                                hoveredQuickCompactID = hovering ? item.id : (hoveredQuickCompactID == item.id ? nil : hoveredQuickCompactID)
                            },
                            onClick: {
                                withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                                    expandedReplyAgentID = nil
                                    focusedReplyAgentID = nil
                                    model.sendQuickReply(item, text: "/compact")
                                }
                            }
                        )
                    }
            }

            HStack(spacing: 3) {
                Text(en ? "Send" : "发送")
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
                    tooltip: en ? "Send message to Rex session (Enter)" : "发送指令至 Rex 会话（回车）",
                    onHoverChange: { hovering in
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
            model.sendQuickReply(item, text: text)
        }
    }

    private func previewLinesColumn(
        item: AgentActivityItem,
        lines: [String],
        familyColor: Color,
        statusColor: Color,
        dark: Bool
    ) -> some View {
        let primaryTextColor = dark ? Color(white: 0.93) : Color(white: 0.14)
        let secondaryTextColor = dark ? Color(white: 0.68) : Color(white: 0.38)
        let barColor = item.status == .idle ? familyColor.opacity(0.65) : statusColor.opacity(0.90)
        let chevronColor = item.status == .idle ? familyColor.opacity(0.85) : statusColor

        return HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(barColor)
                .frame(width: 2.5)
                .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 3.5) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    let isLast = idx == lines.count - 1
                    let isCommandOrQuestion = item.status == .needsInput && (
                        line.hasPrefix("⏺") ||
                        line.hasPrefix("•") ||
                        line.lowercased().contains("do you want") ||
                        line.lowercased().contains("would you like") ||
                        line.lowercased().contains("allow")
                    )
                    let isHighlightedLine = isLast || isCommandOrQuestion
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if lines.count == 1 {
                            Text("›")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(chevronColor)
                        }
                        Text(line)
                            .font(.system(size: 10.5, weight: isCommandOrQuestion ? .semibold : (isLast ? .medium : .regular), design: .monospaced))
                            .foregroundStyle(isHighlightedLine ? primaryTextColor : secondaryTextColor)
                            .lineLimit(item.status == .needsInput ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: item.status == .needsInput)
                            .truncationMode(.tail)
                    }
                }
            }
            Spacer(minLength: 4)
        }
    }

    private func previewRightAccessory(
        item: AgentActivityItem,
        cacheRemaining: Int?,
        familyColor: Color,
        dark: Bool
    ) -> some View {
        let hasDiff = item.gitDiff != nil
        let hasCache = cacheRemaining != nil
        let hasCtx = item.contextPercentUsed != nil

        return HStack(spacing: 5) {
            if let diff = item.gitDiff {
                benchoGitDiffChip(diff: diff, dark: dark)
            }
            if hasDiff && (hasCache || hasCtx) {
                Text("·")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            if let cacheRemaining {
                benchoCacheWarmChip(remainingSeconds: cacheRemaining, dark: dark)
            }
            if hasCache && hasCtx {
                Text("·")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            if let ctx = item.contextPercentUsed {
                benchoContextMeterChip(ctx: ctx, familyColor: familyColor, dark: dark)
            }
        }
        .padding(.trailing, 2)
    }

    private func benchoGitDiffChip(diff: GitDiffSummary, dark: Bool) -> some View {
        let en = model.language == .english
        let addColor = dark
            ? Color(red: 0.28, green: 0.88, blue: 0.58)
            : Color(red: 0.08, green: 0.56, blue: 0.34)
        let delColor = dark
            ? Color(red: 0.98, green: 0.44, blue: 0.48)
            : Color(red: 0.82, green: 0.20, blue: 0.26)

        return HStack(spacing: 3) {
            if diff.insertions > 0 || diff.deletions == 0 {
                Text("+\(diff.insertions)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(addColor)
                    .monospacedDigit()
            }
            if diff.deletions > 0 {
                Text("-\(diff.deletions)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
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
        let isExpiringSoon = remainingSeconds <= 90
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        let timeStr = String(format: "%d:%02d", mins, secs)

        let tintColor: Color = isExpiringSoon
            ? (dark ? Color(red: 0.98, green: 0.68, blue: 0.22) : Color(red: 0.84, green: 0.44, blue: 0.06))
            : (dark ? Color(red: 0.24, green: 0.86, blue: 0.62) : Color(red: 0.08, green: 0.56, blue: 0.36))

        return HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(tintColor)

            Text(timeStr)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(isExpiringSoon ? tintColor : FlatPalette.inkSecondary(dark: dark))
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
        let isHighCtx = ctx >= 80
        let isMidCtx = ctx >= 55 && ctx < 80
        let activeColor: Color = isHighCtx
            ? Color(red: 0.96, green: 0.42, blue: 0.22)
            : (isMidCtx ? Color(red: 0.94, green: 0.66, blue: 0.18) : familyColor)
        let emptySegColor = dark ? Color.white.opacity(0.14) : Color.black.opacity(0.11)
        let filledSegments = max(1, min(5, Int(ceil(Double(max(1, ctx)) / 20.0))))

        return HStack(spacing: 4.5) {
            // Bencho 5-segment micro bar (.ctx-bar)
            HStack(spacing: 1.5) {
                ForEach(0..<5, id: \.self) { segIdx in
                    let lit = segIdx < filledSegments && ctx > 0
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .fill(lit ? activeColor : emptySegColor)
                        .frame(width: 2.5, height: lit ? 8.5 : 6.5)
                }
            }

            Text("\(ctx)%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(isHighCtx ? activeColor : FlatPalette.inkSecondary(dark: dark))
                .monospacedDigit()
        }
        .help(model.language == .english ? "Context window \(ctx)% used" : "上下文窗口已使用 \(ctx)%")
    }

    private func inlineApprovalReserveBar(dark: Bool) -> some View {
        let en = model.language == .english
        let amber = dark
            ? Color(red: 0.98, green: 0.70, blue: 0.24)
            : Color(red: 0.72, green: 0.36, blue: 0.04)
        return HStack(spacing: 5.5) {
            Circle()
                .fill(amber)
                .frame(width: 5, height: 5)
            Text(en ? "Awaiting confirmation" : "等待权限确认")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(amber)
            Spacer(minLength: 4)
            // Space reserved for the Bencho action dock overlay
            Color.clear
                .frame(width: 224, height: 26)
        }
        .padding(.leading, 4)
    }

    private func kbdBadge(_ text: String, tint: Color, dark: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint.opacity(0.9))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .strokeBorder(tint.opacity(0.22), lineWidth: 1)
                    )
            )
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
        let familyColor = item.family.accentColor(dark: dark)
        let greenFg = dark
            ? Color(red: 0.24, green: 0.88, blue: 0.54)
            : Color(red: 0.06, green: 0.50, blue: 0.24)
        let greenBg = dark
            ? (isApprove1Hovered ? Color(red: 0.14, green: 0.32, blue: 0.21) : Color(red: 0.10, green: 0.23, blue: 0.15))
            : (isApprove1Hovered ? Color(red: 0.82, green: 0.95, blue: 0.86) : Color(red: 0.90, green: 0.97, blue: 0.92))

        let opt2Fg = FlatPalette.inkPrimary(dark: dark)
        let opt2Bg = dark
            ? (isApprove2Hovered ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
            : (isApprove2Hovered ? Color.black.opacity(0.09) : Color.white)

        let denyFg = isDenyHovered
            ? Color(red: 0.94, green: 0.30, blue: 0.36)
            : FlatPalette.inkSecondary(dark: dark)
        let denyBg = dark
            ? (isDenyHovered ? Color(red: 0.32, green: 0.13, blue: 0.15) : Color.white.opacity(0.04))
            : (isDenyHovered ? Color(red: 1.0, green: 0.91, blue: 0.92) : Color.white)

        let replyFg = (showInlineReply || isReplyToggleHovered) ? familyColor : FlatPalette.inkSecondary(dark: dark)
        let replyBg = (showInlineReply || isReplyToggleHovered)
            ? familyColor.opacity(dark ? 0.20 : 0.12)
            : (dark ? Color.white.opacity(0.05) : Color.white)

        // Bencho-style unified pill action dock (.pill-track)
        return HStack(spacing: 3) {
            // 1. Primary Approve: Allow [⏎] / 允许 [⏎]
            HStack(spacing: 4) {
                Text(en ? "Allow" : "允许")
                    .font(.system(size: 10.5, weight: .semibold))
                kbdBadge("⏎", tint: greenFg, dark: dark)
            }
            .foregroundStyle(greenFg)
            .padding(.leading, 8.5)
            .padding(.trailing, 6)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(greenBg)
                    .overlay(
                        Capsule()
                            .strokeBorder(greenFg.opacity(dark ? 0.38 : 0.28), lineWidth: 1)
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en ? "Send Enter to approve (Option 1)" : "发送回车确认允许（选项 1）",
                    onHoverChange: { hovering in
                        hoveredApprovePrimaryID = hovering ? item.id : (hoveredApprovePrimaryID == item.id ? nil : hoveredApprovePrimaryID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            model.respondToPermission(item, choice: .approvePrimary)
                        }
                    }
                )
            }

            // 2. Option 2: [2]
            HStack(spacing: 3) {
                kbdBadge("2", tint: opt2Fg, dark: dark)
            }
            .padding(.horizontal, 4.5)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(opt2Bg)
                    .overlay(
                        Capsule()
                            .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en ? "Select Option 2 and confirm (e.g. Always allow)" : "选择第 2 项并确认（如：始终允许 / 本次会话不再询问）",
                    onHoverChange: { hovering in
                        hoveredApproveSecondaryID = hovering ? item.id : (hoveredApproveSecondaryID == item.id ? nil : hoveredApproveSecondaryID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            model.respondToPermission(item, choice: .approveSecondary)
                        }
                    }
                )
            }

            // 3. Deny: Deny [Esc] / 拒绝 [Esc]
            HStack(spacing: 4) {
                Text(en ? "Deny" : "拒绝")
                    .font(.system(size: 10.5, weight: .medium))
                kbdBadge("Esc", tint: denyFg, dark: dark)
            }
            .foregroundStyle(denyFg)
            .padding(.leading, 7.5)
            .padding(.trailing, 5.5)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(denyBg)
                    .overlay(
                        Capsule()
                            .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en ? "Send deny or Esc to cancel" : "发送拒绝指令或 Esc 取消",
                    onHoverChange: { hovering in
                        hoveredDenyID = hovering ? item.id : (hoveredDenyID == item.id ? nil : hoveredDenyID)
                    },
                    onClick: {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18)) {
                            model.respondToPermission(item, choice: .deny)
                        }
                    }
                )
            }

            // 4. Custom Reply Toggle Button
            Image(systemName: "text.bubble")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(replyFg)
                .frame(width: 24, height: 21)
                .background(
                    Capsule()
                        .fill(replyBg)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    showInlineReply ? familyColor.opacity(0.4) : FlatPalette.hairlineBorder(dark: dark),
                                    lineWidth: 1
                                )
                        )
                )
                .overlay {
                    PointingHandCursorOverlay(
                        tooltip: en ? "Type a custom reply to Rex" : "输入自定义回复发送至 Rex",
                        onHoverChange: { hovering in
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
        .padding(2.5)
        .background(
            Capsule()
                .fill(FlatPalette.trackBackground(dark: dark))
                .overlay(
                    Capsule()
                        .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                )
        )
    }

    private func rowBorderColor(for item: AgentActivityItem, isHovered: Bool, familyColor: Color, dark: Bool) -> Color {
        if item.status == .needsInput {
            return Color(red: 0.98, green: 0.66, blue: 0.18).opacity(dark ? 0.58 : 0.48)
        }
        if item.isUnreadCompletion {
            return Color(red: 1.0, green: 0.22, blue: 0.44).opacity(dark ? 0.45 : 0.34)
        }
        if isHovered {
            return familyColor.opacity(dark ? 0.42 : 0.32)
        }
        return FlatPalette.hairlineBorder(dark: dark)
    }

    private func statusBadgeFill(_ status: AgentTaskStatus, dark: Bool) -> Color {
        switch status {
        case .idle:
            return dark ? Color.white.opacity(0.04) : Color.black.opacity(0.035)
        case .completed:
            return dark ? Color(red: 0.08, green: 0.22, blue: 0.14) : Color(red: 0.90, green: 0.97, blue: 0.92)
        case .needsInput:
            return dark ? Color(red: 0.28, green: 0.18, blue: 0.07) : Color(red: 1.0, green: 0.95, blue: 0.86)
        case .working:
            return dark ? Color(red: 0.09, green: 0.20, blue: 0.34) : Color(red: 0.90, green: 0.95, blue: 1.0)
        }
    }

    private func statusBadgeStroke(_ status: AgentTaskStatus, dark: Bool) -> Color {
        switch status {
        case .idle:
            return FlatPalette.hairlineBorder(dark: dark)
        case .completed:
            return agentStatusColor(.completed, dark: dark).opacity(dark ? 0.32 : 0.22)
        case .needsInput:
            return agentStatusColor(.needsInput, dark: dark).opacity(dark ? 0.38 : 0.28)
        case .working:
            return agentStatusColor(.working, dark: dark).opacity(dark ? 0.32 : 0.22)
        }
    }

    private func agentStatusColor(_ status: AgentTaskStatus, dark: Bool) -> Color {
        switch status {
        case .needsInput:
            return dark
                ? Color(red: 0.98, green: 0.70, blue: 0.24)
                : Color(red: 0.82, green: 0.44, blue: 0.06)
        case .working:
            return FlatPalette.blue
        case .completed:
            return dark
                ? Color(red: 0.34, green: 0.86, blue: 0.58)
                : Color(red: 0.10, green: 0.58, blue: 0.34)
        case .idle:
            return .secondary
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
        return HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(FlatPalette.blue)
                    .frame(width: 5.5, height: 5.5)
                Text(en ? "Monitoring Codex · Claude · Copilot · Antigravity" : "实时监控 Codex · Claude · Copilot · Antigravity")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            FlatIconButton(icon: "power", size: 28, iconSize: 12, tooltip: en ? "Quit Agent Meter" : "退出应用") {
                NSApplication.shared.terminate(nil)
            }
        }
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
                emptyStateCard(
                    icon: "clock.arrow.circlepath",
                    title: hasSearchText
                        ? (en ? "No matching historical sessions" : "没有找到匹配的历史会话")
                        : (en ? "No historical sessions found" : "暂未发现本地历史会话记录"),
                    subtitle: en
                        ? "Supports resuming Claude Code, Codex CLI, Copilot CLI & Antigravity conversations in Rex"
                        : "自动扫描本机 Claude Code、Codex CLI、Copilot CLI 与 Antigravity 的历史会话记录"
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
        let isHovered = hoveredHistoryID == item.id || isDeleteHovered || isConfirmHovered || isCancelHovered || isConfirmingDelete
        let accent = item.family.accentColor(dark: dark)
        let isOnline = item.onlineActivityID != nil
        let elapsed = max(0, Int(now.timeIntervalSince(item.updatedAt)))
        let timeStr = formatRelativeAgo(elapsed, en: en)
        let displayPath = abbreviateHomePath(item.cwdPath)

        return HStack(alignment: .center, spacing: 11) {
            AgentFamilyBadgeIcon(
                family: item.family,
                dark: dark,
                highlighted: isHovered || isOnline,
                size: 32
            )
            .help(item.family.badgeTitle)

            VStack(alignment: .leading, spacing: 4.5) {
                // Row 1: Session Title + Top-Right Action Pill & Delete Button
                HStack(alignment: .center, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 6)

                    if isOnline {
                        HStack(spacing: 3.5) {
                            Circle()
                                .fill(Color(red: 0.16, green: 0.78, blue: 0.48))
                                .frame(width: 5, height: 5)
                            Text(en ? "Online ↗" : "在线 ↗")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(dark ? Color(red: 0.34, green: 0.88, blue: 0.62) : Color(red: 0.08, green: 0.56, blue: 0.36))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(dark ? Color(red: 0.10, green: 0.25, blue: 0.18) : Color(red: 0.88, green: 0.97, blue: 0.92))
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    } else if isConfirmingDelete {
                        // Reserve space for the top-trailing confirmation buttons overlay
                        Color.clear
                            .frame(width: en ? 116 : 112, height: 20)
                    } else {
                        HStack(spacing: 3) {
                            Text(en ? "Resume" : "恢复")
                                .font(.system(size: 10, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundStyle(isHovered && !isDeleteHovered ? accent : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(
                                    isHovered && !isDeleteHovered
                                        ? accent.opacity(dark ? 0.20 : 0.12)
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
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(accent.opacity(0.85))
                        Text(displayPath)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let branch = item.gitBranch, !branch.isEmpty {
                        Text("·")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(branch)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Spacer(minLength: 6)

                    Text(timeStr)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            PointingHandCursorOverlay(
                tooltip: isOnline
                    ? (en ? "Session is already active — click to focus Rex window (\(displayPath))" : "该会话当前已在线，点击直接跳转到对应 Rex 窗口（\(displayPath)）")
                    : (en ? "Resume session in a new Rex tab (\(displayPath))" : "在 Rex 新建 Tab 恢复该历史会话（\(displayPath)）"),
                onHoverChange: { hovering in
                    hoveredHistoryID = hovering ? item.id : (hoveredHistoryID == item.id ? nil : hoveredHistoryID)
                },
                onClick: {
                    if isConfirmingDelete {
                        withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16)) {
                            confirmingHistoryDeleteID = nil
                        }
                        return
                    }
                    confirmingHistoryDeleteID = nil
                    isHistorySearchFocused = false
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
                    .padding(.trailing, 11)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
                } else {
                    deleteHistoryButton(item: item, isDeleteHovered: isDeleteHovered, isRowHovered: isHovered, dark: dark)
                        .padding(.top, 9.5)
                        .padding(.trailing, 11)
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
                                ? Color(red: 0.96, green: 0.32, blue: 0.38).opacity(dark ? 0.52 : 0.42)
                                : (isHovered ? accent.opacity(dark ? 0.42 : 0.32) : FlatPalette.hairlineBorder(dark: dark)),
                            lineWidth: isConfirmingDelete ? 1.2 : 1
                        )
                )
        )
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.16), value: isHovered)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.14), value: isDeleteHovered)
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.18), value: isConfirmingDelete)
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
                    ? Color(red: 0.96, green: 0.32, blue: 0.38)
                    : Color.secondary.opacity(isRowHovered ? 0.85 : 0.5)
            )
            .frame(width: 22, height: 20)
            .background(
                Capsule()
                    .fill(
                        isDeleteHovered
                            ? (dark ? Color(red: 0.36, green: 0.14, blue: 0.17) : Color(red: 1.0, green: 0.90, blue: 0.92))
                            : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                    )
            )
            .overlay {
                PointingHandCursorOverlay(
                    tooltip: en ? "Delete session data" : "删除该条历史会话及本地文件",
                    onHoverChange: { hovering in
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
        let redFg = dark
            ? Color(red: 1.0, green: 0.42, blue: 0.48)
            : Color(red: 0.84, green: 0.14, blue: 0.22)
        let redBg = dark
            ? (isConfirmHovered ? Color(red: 0.48, green: 0.14, blue: 0.19) : Color(red: 0.36, green: 0.12, blue: 0.16))
            : (isConfirmHovered ? Color(red: 1.0, green: 0.82, blue: 0.85) : Color(red: 1.0, green: 0.90, blue: 0.92))

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

        return VStack(alignment: .leading, spacing: 14) {
            // 1. Agent Family Selector
            VStack(alignment: .leading, spacing: 8) {
                Text(en ? "SELECT CLI AGENT" : "选择 CLI AGENT")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                HStack(spacing: 6) {
                    ForEach(AgentFamily.allCases) { family in
                        launchFamilyCardItem(family: family, selectedFamily: selectedFamily, dark: dark)
                    }
                }
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(FlatPalette.trackBackground(dark: dark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                        )
                )

                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                    Text(model.launchCommand(for: selectedFamily))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(en ? "Edit" : "修改命令")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .overlay {
                            PointingHandCursorOverlay(
                                onClick: {
                                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.22)) {
                                        showingQuickLaunch = false
                                        showingSettings = true
                                    }
                                }
                            )
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(FlatPalette.terminalWellBackground(dark: dark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(FlatPalette.hairlineBorder(dark: dark), lineWidth: 1)
                        )
                )
            }

            // 2. Workspace Directory List
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(en ? "WORKSPACE (CLICK TO LAUNCH IN REX)" : "选择工作目录（点击即在 Rex 新建 Tab 启动）")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
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

                VStack(spacing: 8) {
                    ForEach(model.recentLaunchWorkspaces, id: \.self) { path in
                        workspaceLaunchRow(path: path, family: selectedFamily, accent: accent, dark: dark)
                    }
                }
            }
        }
    }

    private func launchFamilyCardItem(
        family: AgentFamily,
        selectedFamily: AgentFamily,
        dark: Bool
    ) -> some View {
        let isSelected = selectedFamily == family
        let fColor = family.accentColor(dark: dark)
        return VStack(spacing: 5) {
            AgentFamilyBadgeIcon(
                family: family,
                dark: dark,
                highlighted: isSelected,
                size: 28,
                muted: !isSelected
            )
            Text(family.shortName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(FlatPalette.selectedPillBackground(dark: dark))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(fColor.opacity(dark ? 0.45 : 0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(dark ? 0.24 : 0.06), radius: 2, x: 0, y: 1)
                    .matchedGeometryEffect(id: "launchFamilyCard", in: launchFamilyNamespace)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            PointingHandCursorOverlay(
                onClick: {
                    withAnimation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.20)) {
                        model.preferredLaunchFamily = family
                    }
                }
            )
        }
    }

    private func workspaceLaunchRow(
        path: String,
        family: AgentFamily,
        accent: Color,
        dark: Bool
    ) -> some View {
        let isHovered = hoveredWorkspacePath == path
        let name = URL(fileURLWithPath: path).lastPathComponent
        let displayPath = abbreviateHomePath(path)

        return HStack(spacing: 11) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovered ? accent : .secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(
                            isHovered
                                ? family.tintFill(dark: dark, highlighted: true)
                                : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                        )
                )

            VStack(alignment: .leading, spacing: 2.5) {
                let en = model.language == .english
                Text(name.isEmpty || name == "/" ? (en ? "Home" : "主目录") : name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(displayPath)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text(model.language == .english ? "Launch \(family.shortName)" : "启动 \(family.shortName)")
                    .font(.system(size: 10.5, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(isHovered ? accent : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(
                        isHovered
                            ? accent.opacity(dark ? 0.20 : 0.12)
                            : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                    )
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            PointingHandCursorOverlay(
                onHoverChange: { hovering in
                    hoveredWorkspacePath = hovering ? path : (hoveredWorkspacePath == path ? nil : hoveredWorkspacePath)
                },
                onClick: {
                    showingQuickLaunch = false
                    model.launchNewAgentSession(family: family, cwdPath: path)
                }
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FlatPalette.elevatedRowBackground(dark: dark, hovered: isHovered))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isHovered ? accent.opacity(dark ? 0.38 : 0.28) : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)),
                            lineWidth: 0.8
                        )
                )
        )
        .animation(FlatMotion.snappy(reduceMotion: reduceMotion, duration: 0.15), value: isHovered)
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
        let panel = NSOpenPanel()
        panel.title = en
            ? "Choose workspace directory to launch \(family.badgeTitle)"
            : "选择要启动 \(family.badgeTitle) 的工作目录"
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
    var size: CGFloat = 32
    var muted: Bool = false

    var body: some View {
        let accent = family.accentColor(dark: dark)
        let fg: Color = muted ? .secondary : accent
        let corner = round(size * 0.28)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        ZStack {
            shape
                .fill(family.tintFill(dark: dark, highlighted: highlighted))
                .overlay(
                    shape
                        .strokeBorder(
                            accent.opacity(highlighted ? (dark ? 0.42 : 0.30) : (dark ? 0.22 : 0.16)),
                            lineWidth: 1
                        )
                )

            AgentFamilyGlyph(family: family, color: fg, size: size * 0.52)
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
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.16, blue: 0.19),
                            Color(red: 0.07, green: 0.08, blue: 0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(dark ? 0.26 : 0.10), radius: 5, x: 0, y: 2)

            HStack(spacing: 3.5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color(white: 0.95))

                VStack(alignment: .leading, spacing: 2.6) {
                    Capsule()
                        .fill(Color(red: 0.18, green: 0.88, blue: 0.64))
                        .frame(width: 9.5, height: 2.4)
                    HStack(spacing: 2) {
                        Capsule()
                            .fill(Color(red: 0.32, green: 0.64, blue: 0.99))
                            .frame(width: 6.5, height: 2.4)
                        Circle()
                            .fill(Color(red: 1.0, green: 0.22, blue: 0.44))
                            .frame(width: 2.6, height: 2.6)
                    }
                    Capsule()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: 4.5, height: 2.4)
                }
            }
        }
    }
}

private struct AgentMeterSettings: View {
    @Bindable var model: AgentMeterModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var appearanceNamespace
    @Namespace private var languageNamespace

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
                            ? "Command executed automatically when opening a new Rex tab."
                            : "新建会话时在 Rex 终端自动执行的命令行。"
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

private struct AgentPulseDot: View {
    let status: AgentTaskStatus
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var dotColor: Color {
        switch status {
        case .needsInput:
            return Color(red: 0.98, green: 0.68, blue: 0.20)
        case .working:
            return FlatPalette.blue
        case .completed:
            return Color(red: 0.22, green: 0.78, blue: 0.50)
        case .idle:
            return .secondary.opacity(0.55)
        }
    }

    var body: some View {
        let activePulse = (status == .working || status == .needsInput) && !reduceMotion && pulsing
        Circle()
            .fill(dotColor)
            .frame(width: size, height: size)
            .scaleEffect(activePulse ? 1.25 : 1.0)
            .opacity(activePulse ? 0.6 : 1.0)
            .onAppear {
                updateAnimation(for: status)
            }
            .onChange(of: status) { _, newValue in
                updateAnimation(for: newValue)
            }
    }

    private func updateAnimation(for currentStatus: AgentTaskStatus) {
        guard !reduceMotion else {
            pulsing = false
            return
        }
        if currentStatus == .working || currentStatus == .needsInput {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pulsing = false
            }
        }
    }
}

private struct UnreadCompletionBeacon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false

    // Distinct bright coral-red/magenta color to contrast with Emerald (Codex), Blue (Copilot), Amber (Antigravity), and Green (Completed badge)
    private let dotColor = Color(red: 1.0, green: 0.22, blue: 0.44)

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(dotColor.opacity(glowing ? 0.42 : 0.16))
                    .frame(width: glowing ? 14 : 8, height: glowing ? 14 : 8)
            }
            Circle()
                .fill(dotColor)
                .frame(width: 7.5, height: 7.5)
                .shadow(color: dotColor.opacity(0.9), radius: 4, x: 0, y: 0)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                glowing = true
            }
        }
    }
}
