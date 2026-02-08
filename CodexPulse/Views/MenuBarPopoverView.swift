import SwiftUI
#if os(macOS)
import AppKit
#endif

private enum HeatmapRangeOption: String, CaseIterable, Identifiable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"

    var id: String { rawValue }

    var months: Int {
        switch self {
        case .oneMonth:
            return 1
        case .threeMonths:
            return 3
        case .sixMonths:
            return 6
        }
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: HeatmapViewModel

    @State private var showsPacingDetails = false
    @State private var isDayDetailPinned = false
    @State private var showsLegend = false
    @State private var heatmapRange: HeatmapRangeOption = .oneMonth
    @State private var shareFeedbackMessage: String?
    @State private var shareFeedbackTask: Task<Void, Never>?

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            pacingPanel

            usageSummaryPanel

            activityAndDetailPanel

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(width: 640)
        .onAppear {
            viewModel.popoverDidAppear()
        }
        .onDisappear {
            shareFeedbackTask?.cancel()
            viewModel.popoverDidDisappear()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Usage")
                    .font(.headline)

                Text(updatedStatusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            headerControls
        }
    }

    @ViewBuilder
    private var headerControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                shareCardMenu(isCompact: false)
                shareFeedbackBadge
                updateInstallButton(isCompact: false)
                refreshButton
            }

            HStack(spacing: 8) {
                shareCardMenu(isCompact: true)
                shareFeedbackBadge
                updateInstallButton(isCompact: true)
                refreshButton
            }
        }
    }

    @ViewBuilder
    private var shareFeedbackBadge: some View {
        if let shareFeedbackMessage {
            Label(shareFeedbackMessage, systemImage: "doc.on.clipboard")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.10), in: Capsule())
                .transition(.opacity)
        }
    }

    private func shareCardMenu(isCompact: Bool) -> some View {
        Menu {
            ForEach(ShareCardMode.allCases) { mode in
                Button("Copy \(mode.rawValue)") {
                    copyShareCard(mode)
                }
            }
        } label: {
            if isCompact {
                Image(systemName: "square.and.arrow.up")
            } else {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .help("Copy a shareable card image")
    }

    @ViewBuilder
    private func updateInstallButton(isCompact: Bool) -> some View {
        if viewModel.canInstallCurrentBuild {
            Button {
                viewModel.installCurrentBuild()
            } label: {
                if viewModel.isInstallingCurrentBuild {
                    ProgressView()
                        .controlSize(.small)
                } else if isCompact {
                    Image(systemName: "arrow.down.app")
                } else {
                    Label("Update App", systemImage: "arrow.down.app")
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Install this build to \(viewModel.installDestinationPath)")
        }
    }

    private var refreshButton: some View {
        Button {
            viewModel.manualRefresh()
        } label: {
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.borderless)
        .help("Refresh usage")
    }

    private var pacingPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Pacing")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button(showsPacingDetails ? "Hide details" : "Show details") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsPacingDetails.toggle()
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            projectSelector

            currentVsTypicalRow

            fiveHourSummaryRow

            if showsPacingDetails {
                Divider()

                pacingDetailsSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .modifier(CardStyle())
    }

    private var pacingDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage Windows")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if viewModel.latestRateLimitSnapshot.isEmpty {
                Text("Rate-limit data unavailable in local telemetry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.latestRateLimitSnapshot) { snapshot in
                    RateLimitRow(snapshot: snapshot)
                }
            }
        }
    }

    private var projectSelector: some View {
        HStack(spacing: 8) {
            Text("Project")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.projectScopes.count <= 3 {
                Picker("", selection: projectSelectionBinding) {
                    ForEach(viewModel.projectScopes) { scope in
                        Text(scope.title)
                            .tag(scope.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            } else {
                Picker("", selection: projectSelectionBinding) {
                    ForEach(viewModel.projectScopes) { scope in
                        Text(scope.title)
                            .tag(scope.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 280, alignment: .leading)
            }

            Spacer()
        }
    }

    private var currentVsTypicalRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("Top Building Speed")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if viewModel.peakHourlyTokens > 0 {
                        Text("\(DisplayValueFormatter.compactCount(viewModel.peakHourlyTokens)) tokens/hr")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Spacer()

                Label {
                    Text("\(DisplayValueFormatter.compactCount(viewModel.currentHourTokens)) tokens/hr")
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "speedometer")
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let ratio = viewModel.currentVsTypicalRatio {
                    let deltaPercent = Int(((ratio - 1) * 100).rounded())
                    Text("Pace \(deltaPercent >= 0 ? "+" : "")\(deltaPercent)%")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(deltaPercent > 0 ? .green : (deltaPercent < 0 ? .red : .secondary))
                        .monospacedDigit()
                }
            }
        }
    }

    private var fiveHourSummaryRow: some View {
        Group {
            if let fiveHourSnapshot = fiveHourSnapshot {
                HStack(alignment: .center, spacing: 14) {
                    Text("5-hour window")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .stroke(.secondary.opacity(0.24), lineWidth: 3)
                            .overlay {
                                Circle()
                                    .trim(from: 0, to: CGFloat(clampedRemainingPercent(for: fiveHourSnapshot) / 100))
                                    .stroke(
                                        fiveHourProgressTint(for: fiveHourSnapshot),
                                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 12, height: 12)

                        Text("\(DisplayValueFormatter.percent(clampedRemainingPercent(for: fiveHourSnapshot), fractionDigits: 0))% left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }

                    Text("Resets \(fiveHourSnapshot.resetsAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 16.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("5-hour window")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Unavailable")
                        .font(.system(size: 16.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var usageSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage Summary")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                summaryMetricCard(
                    title: "Today",
                    tokens: viewModel.todayTokens,
                    cost: viewModel.dailyCostUSD,
                    trend: viewModel.todayTrend
                )

                summaryMetricCard(
                    title: "This Week",
                    tokens: viewModel.weeklyTokens,
                    cost: viewModel.weeklyCostUSD,
                    trend: viewModel.weeklyTrend
                )

                summaryMetricCard(
                    title: "Last 30 Days",
                    tokens: viewModel.last30DaysTokens,
                    cost: viewModel.last30DaysCostUSD,
                    trend: viewModel.last30DaysTrend
                )
            }
        }
        .modifier(CardStyle())
    }

    private func summaryMetricCard(title: String, tokens: Int, cost: Double, trend: TrendSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                trendBadge(trend)
            }

            Text(DisplayValueFormatter.compactCount(tokens))
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            Text("$\(DisplayValueFormatter.currency(cost))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var activityAndDetailPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            activityPanel

            if isDayDetailPinned {
                pinnedDayDetailDrawer
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Picker("Range", selection: $heatmapRange) {
                    ForEach(HeatmapRangeOption.allCases) { option in
                        Text(option.rawValue)
                            .tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 130)

                Button(showsLegend ? "Hide legend" : "Show legend") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsLegend.toggle()
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)

                if !isDayDetailPinned {
                    Button("Pin details") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDayDetailPinned = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                ActivityHeatmapView(weeks: filteredHeatmapWeeks) { selected in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectDate(selected)
                    }
                }
                Spacer(minLength: 0)
            }

            if showsLegend {
                HeatmapLegendView()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .modifier(CardStyle())
    }

    private var pinnedDayDetailDrawer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Pinned Day Detail")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Unpin") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDayDetailPinned = false
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            DayDetailView(usage: viewModel.selectedUsage, date: viewModel.selectedDate, isCompact: true)
        }
    }

    private func trendBadge(_ trend: TrendSnapshot) -> some View {
        let symbol: String
        let color: Color

        switch trend.direction {
        case .up:
            symbol = "↑"
            color = .red
        case .down:
            symbol = "↓"
            color = .green
        case .flat:
            symbol = "→"
            color = .secondary
        }

        return Text("\(symbol) \(trend.percentMagnitude)%")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .monospacedDigit()
    }

    private var projectSelectionBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedProjectScopeID },
            set: { viewModel.selectProjectScope(id: $0) }
        )
    }

    private var fiveHourSnapshot: RateLimitSnapshot? {
        viewModel.latestRateLimitSnapshot.first(where: { $0.windowKind == .fiveHour })
    }

    private func clampedRemainingPercent(for snapshot: RateLimitSnapshot) -> Double {
        min(100, max(0, snapshot.remainingPercent))
    }

    private func fiveHourProgressTint(for snapshot: RateLimitSnapshot) -> Color {
        clampedRemainingPercent(for: snapshot) > 10 ? .green : .red
    }

    private func targetRemainingPercent(for snapshot: RateLimitSnapshot) -> Double {
        let duration = max(Double(snapshot.windowMinutes) * 60, 1)
        let remainingSeconds = snapshot.resetsAt.timeIntervalSince(snapshot.capturedAt)
        let clampedRemainingSeconds = min(max(remainingSeconds, 0), duration)
        return (clampedRemainingSeconds / duration) * 100
    }

    private func paceDelta(for snapshot: RateLimitSnapshot) -> Double {
        clampedRemainingPercent(for: snapshot) - targetRemainingPercent(for: snapshot)
    }

    private func paceDeltaLabel(for snapshot: RateLimitSnapshot) -> String {
        let value = paceDelta(for: snapshot)
        let rounded = Int(abs(value).rounded())
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(rounded)%"
    }

    private func paceDeltaColor(for snapshot: RateLimitSnapshot) -> Color {
        if abs(paceDelta(for: snapshot)) < 1 {
            return .secondary
        }
        return paceDelta(for: snapshot) >= 0 ? .green : .red
    }

    private func remainingTint(for snapshot: RateLimitSnapshot) -> Color {
        let remaining = clampedRemainingPercent(for: snapshot)
        if remaining <= 10 {
            return .red
        }
        if remaining <= 30 {
            return .orange
        }
        return .green
    }

    private var updatedStatusLabel: String {
        guard let lastUpdatedAt = viewModel.lastUpdatedAt else {
            return "Update pending"
        }
        return "Updated \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
    }

    private var filteredHeatmapWeeks: [[HeatmapDayCell]] {
        guard !viewModel.heatmapWeeks.isEmpty else { return viewModel.heatmapWeeks }

        let now = Date()
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
            ?? calendar.startOfDay(for: now)
        if heatmapRange == .oneMonth {
            return currentMonthWeeksIncludingFuture(from: currentMonthStart)
        }

        let cutoffDate = calendar.date(byAdding: .month, value: -(heatmapRange.months - 1), to: currentMonthStart)
            ?? currentMonthStart
        let endDate = calendar.startOfDay(for: now)

        let filtered = viewModel.heatmapWeeks.filter { week in
            guard let first = week.first?.date, let last = week.last?.date else { return false }
            return last >= cutoffDate && first <= endDate
        }

        return filtered.isEmpty ? viewModel.heatmapWeeks : filtered
    }

    private func currentMonthWeeksIncludingFuture(from monthStart: Date) -> [[HeatmapDayCell]] {
        guard let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart),
              let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonthStart) else {
            return viewModel.heatmapWeeks
        }

        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone

        let monthGridStart = iso.date(from: iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: monthStart))
            ?? monthStart
        let monthGridEndWeekStart = iso.date(from: iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: monthEnd))
            ?? monthEnd
        let monthGridEnd = iso.date(byAdding: .day, value: 6, to: monthGridEndWeekStart) ?? monthEnd

        let existingCells = Dictionary(uniqueKeysWithValues: viewModel.heatmapWeeks
            .flatMap { $0 }
            .map { (calendar.startOfDay(for: $0.date), $0) })

        var weeks: [[HeatmapDayCell]] = []
        var weekStart = monthGridStart
        while weekStart <= monthGridEnd {
            var week: [HeatmapDayCell] = []
            for dayOffset in 0 ..< 7 {
                let date = iso.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
                let normalizedDate = calendar.startOfDay(for: date)
                let cell = existingCells[normalizedDate] ?? HeatmapDayCell(date: normalizedDate, usage: nil, level: 0)
                week.append(cell)
            }
            weeks.append(week)
            weekStart = iso.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? monthGridEnd.addingTimeInterval(1)
        }

        return weeks
    }

    private func copyShareCard(_ mode: ShareCardMode) {
#if os(macOS)
        let snapshot = makeShareCardSnapshot(mode: mode)
        let image: NSImage?

        if mode == .buildMode {
            let renderedView = ShareCardView(snapshot: snapshot)
                .frame(width: 1200)
                .fixedSize(horizontal: false, vertical: true)
            let renderer = ImageRenderer(content: renderedView)
            renderer.proposedSize = .init(width: 1200, height: nil)
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
            image = renderer.nsImage
        } else {
            let renderedView = ShareCardView(snapshot: snapshot)
                .frame(width: 1200, height: 760)
            let renderer = ImageRenderer(content: renderedView)
            renderer.proposedSize = .init(width: 1200, height: 760)
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
            image = renderer.nsImage
        }

        guard let image else {
            scheduleShareFeedback("Unable to render \(mode.rawValue)")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.writeObjects([image]) {
            scheduleShareFeedback("Copied \(mode.rawValue)")
        } else {
            scheduleShareFeedback("Copy failed")
        }
#endif
    }

    private func scheduleShareFeedback(_ message: String) {
        shareFeedbackTask?.cancel()
        shareFeedbackMessage = message
        shareFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                shareFeedbackMessage = nil
            }
        }
    }

    private func makeShareCardSnapshot(mode: ShareCardMode) -> ShareCardSnapshot {
        let fiveHour = fiveHourSnapshot

        return ShareCardSnapshot(
            mode: mode,
            projectTitle: viewModel.projectScopes.first(where: { $0.id == viewModel.selectedProjectScopeID })?.title ?? "All Projects",
            generatedAt: viewModel.lastUpdatedAt ?? Date(),
            currentTokensPerHour: viewModel.currentHourTokens,
            peakTokensPerHour: viewModel.peakHourlyTokens,
            peakHourlyDate: viewModel.peakHourlyDate,
            weeklyPeakTokensPerHour: viewModel.weeklyPeakHourlyTokens,
            weeklyPeakHourlyDate: viewModel.weeklyPeakHourlyDate,
            fiveHourUsedPercent: fiveHour?.usedPercent,
            todayTokens: viewModel.todayTokens,
            weekTokens: viewModel.weeklyTokens,
            monthTokens: viewModel.last30DaysTokens,
            mostProductiveDayDate: viewModel.mostProductiveDayDate,
            mostProductiveDayTokens: viewModel.mostProductiveDayTokens,
            weeklyMostProductiveDayDate: viewModel.weeklyMostProductiveDayDate,
            weeklyMostProductiveDayTokens: viewModel.weeklyMostProductiveDayTokens,
            longestStreakDays: viewModel.longestUsageStreakDays,
            weeklyBreakdown: currentWeekBreakdown
        )
    }

    private var currentWeekBreakdown: [ShareWeekdayMetric] {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let rollingWeekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        return (0 ..< 7).map { index in
            let day = calendar.date(byAdding: .day, value: index, to: rollingWeekStart) ?? rollingWeekStart
            let normalized = calendar.startOfDay(for: day)
            let tokens = viewModel.dailyUsageByDate[normalized]?.totalTokens ?? 0
            let label = normalized.formatted(.dateTime.weekday(.abbreviated))
            return ShareWeekdayMetric(label: label, tokens: tokens)
        }
    }

}

private struct RateLimitRow: View {
    let snapshot: RateLimitSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))

                Spacer()

                Text("\(DisplayValueFormatter.percent(clampedRemainingPercent, fractionDigits: 0))% left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(remainingTint)
                    .monospacedDigit()
            }

            PaceProgressBar(
                remainingPercent: clampedRemainingPercent,
                targetRemainingPercent: targetRemainingPercent,
                tint: remainingTint
            )

            HStack {
                Text("Pace \(paceDeltaLabel)")
                    .foregroundStyle(paceDeltaColor)
                    .monospacedDigit()
                Spacer()
                Text("Used \(DisplayValueFormatter.percent(snapshot.usedPercent, fractionDigits: 0))%")
                    .monospacedDigit()
                Spacer()
                Text("Resets \(snapshot.resetsAt.formatted(date: .omitted, time: .shortened))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        switch snapshot.windowKind {
        case .fiveHour:
            return "5-hour window"
        case .weekly:
            return "Weekly window"
        }
    }

    private var remainingTint: Color {
        if clampedRemainingPercent <= 10 {
            return .red
        }
        if clampedRemainingPercent <= 30 {
            return .orange
        }
        return .green
    }

    private var targetRemainingPercent: Double {
        let duration = max(Double(snapshot.windowMinutes) * 60, 1)
        let remainingSeconds = snapshot.resetsAt.timeIntervalSince(snapshot.capturedAt)
        let clampedRemainingSeconds = min(max(remainingSeconds, 0), duration)
        return (clampedRemainingSeconds / duration) * 100
    }

    private var paceDelta: Double {
        clampedRemainingPercent - targetRemainingPercent
    }

    private var paceDeltaLabel: String {
        let rounded = Int(abs(paceDelta).rounded())
        let sign = paceDelta >= 0 ? "+" : "-"
        return "\(sign)\(rounded)%"
    }

    private var paceDeltaColor: Color {
        if abs(paceDelta) < 1 {
            return .secondary
        }
        return paceDelta >= 0 ? .green : .red
    }

    private var clampedRemainingPercent: Double {
        min(100, max(0, snapshot.remainingPercent))
    }
}

private struct PaceProgressBar: View {
    let remainingPercent: Double
    let targetRemainingPercent: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fillWidth = width * CGFloat(clamp(remainingPercent) / 100)
            let markerX = width * CGFloat(clamp(targetRemainingPercent) / 100)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))

                Capsule()
                    .fill(tint.opacity(0.9))
                    .frame(width: fillWidth)

                Capsule()
                    .fill(.blue)
                    .frame(width: 3, height: 12)
                    .offset(x: markerX - 1.5)
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }

    private func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
