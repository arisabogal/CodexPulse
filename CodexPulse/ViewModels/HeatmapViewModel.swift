import Foundation
import SwiftUI
import Combine

struct ProjectScope: Identifiable, Equatable, Hashable {
    static let allID = "__all_projects__"
    static let unassignedID = "__unassigned__"

    static let all = ProjectScope(id: allID, title: "All Projects")
    static let unassigned = ProjectScope(id: unassignedID, title: "Unassigned")

    let id: String
    let title: String
}

enum TrendDirection {
    case up
    case down
    case flat
}

struct TrendSnapshot: Equatable {
    let direction: TrendDirection
    let percentMagnitude: Int
}

@MainActor
final class HeatmapViewModel: ObservableObject {
    private static let selectedProjectDefaultsKey = "heatmap.selected_project_scope"

    @Published private(set) var heatmapWeeks: [[HeatmapDayCell]] = []
    @Published private(set) var dailyUsageByDate: [Date: DailyUsage] = [:]
    @Published var selectedDate: Date = Date()

    @Published private(set) var latestRateLimitSnapshot: [RateLimitSnapshot] = []
    @Published private(set) var rateLimitFreshness: RateLimitFreshness = .unavailable

    @Published private(set) var projectScopes: [ProjectScope] = [ProjectScope.all]
    @Published private(set) var selectedProjectScopeID = ProjectScope.allID

    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastRateLimitCaptureDate: Date?
    @Published private(set) var fallbackPricingUsedInVisibleRange = false
    @Published private(set) var totalTokensInVisibleRange = 0
    @Published private(set) var totalCostInVisibleRange = 0.0
    @Published private(set) var todayTokens = 0
    @Published private(set) var weeklyTokens = 0
    @Published private(set) var last30DaysTokens = 0
    @Published private(set) var dailyCostUSD = 0.0
    @Published private(set) var weeklyCostUSD = 0.0
    @Published private(set) var last30DaysCostUSD = 0.0

    @Published private(set) var todayTrend: TrendSnapshot = .flat
    @Published private(set) var weeklyTrend: TrendSnapshot = .flat
    @Published private(set) var last30DaysTrend: TrendSnapshot = .flat

    @Published private(set) var currentHourTokens = 0
    @Published private(set) var typicalHourTokens = 0.0
    @Published private(set) var peakHourlyTokens = 0
    @Published private(set) var peakHourlyDate: Date?
    @Published private(set) var longestUsageStreakDays = 0
    @Published private(set) var mostProductiveDayDate: Date?
    @Published private(set) var mostProductiveDayTokens = 0
    @Published private(set) var weeklyMostProductiveDayDate: Date?
    @Published private(set) var weeklyMostProductiveDayTokens = 0
    @Published private(set) var weeklyPeakHourlyTokens = 0
    @Published private(set) var weeklyPeakHourlyDate: Date?

    @Published private(set) var canInstallCurrentBuild = false
    @Published private(set) var installDestinationPath = ""
    @Published private(set) var isInstallingCurrentBuild = false
    @Published private(set) var installStatusMessage: String?
    @Published private(set) var errorMessage: String?

    private let scanner: CodexSessionScanner
    private let aggregator = UsageAggregator()
    private let defaults = UserDefaults.standard
    private let alertService = UsageAlertService.shared
    private var calendar = Calendar.autoupdatingCurrent

    private var pendingRefreshTask: Task<Void, Never>?
    private var runningRefreshTask: Task<UsageScanSnapshot, Error>?
    private var backgroundActivityScheduler: NSBackgroundActivityScheduler?
    private var foregroundRefreshTask: Task<Void, Never>?
    private var alertEvaluationTask: Task<Void, Never>?
    private var lastAlertEvaluationInput: AlertEvaluationInput?
    private var lastAppliedDay: Date?
    private var lastAppliedHour: Date?
    private var latestSessions: [SessionUsageRecord] = []

    init(scanner: CodexSessionScanner? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsRoot = home.appendingPathComponent(".codex/sessions", isDirectory: true)

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let cacheURL = appSupport
            .appendingPathComponent("CodexPulse", isDirectory: true)
            .appendingPathComponent("usage-cache.json", isDirectory: false)

        self.scanner = scanner ?? CodexSessionScanner(sessionsRootURL: sessionsRoot, cacheURL: cacheURL)

        self.selectedProjectScopeID = defaults.string(forKey: Self.selectedProjectDefaultsKey) ?? ProjectScope.allID

        startBackgroundRefreshTimer()
        refreshInstallAvailability()
        scheduleRefresh(reason: .launch, debounceSeconds: 0)
    }

    deinit {
        pendingRefreshTask?.cancel()
        runningRefreshTask?.cancel()
        backgroundActivityScheduler?.invalidate()
        foregroundRefreshTask?.cancel()
        alertEvaluationTask?.cancel()
    }

    func popoverDidAppear() {
        startForegroundRefreshTimer()
        refreshInstallAvailability()
        scheduleRefresh(reason: .popoverOpen, debounceSeconds: 0)
    }

    func popoverDidDisappear() {
        foregroundRefreshTask?.cancel()
        foregroundRefreshTask = nil
    }

    func manualRefresh() {
        refreshInstallAvailability()
        scheduleRefresh(reason: .manual, debounceSeconds: 0.1)
    }

    func selectProjectScope(id: String) {
        let normalizedID = projectScopes.contains(where: { $0.id == id }) ? id : ProjectScope.allID
        guard normalizedID != selectedProjectScopeID else { return }
        publishIfChanged(\.selectedProjectScopeID, normalizedID)
        defaults.set(normalizedID, forKey: Self.selectedProjectDefaultsKey)
        rebuildFromCachedSessions(now: Date())
    }

    func installCurrentBuild() {
        guard !isInstallingCurrentBuild else { return }
        publishIfChanged(\.isInstallingCurrentBuild, true)
        publishIfChanged(\.installStatusMessage, nil)

        Task(priority: .utility) {
            let result = await Task.detached(priority: .utility) { () -> Result<URL, Error> in
                do {
                    return .success(try AppInstallationService.installCurrentBuild())
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let destinationURL):
                publishIfChanged(\.installStatusMessage, "Installed latest build to \(destinationURL.path)")
            case .failure:
                publishIfChanged(\.installStatusMessage, "Install failed. Check Applications folder permissions.")
            }

            refreshInstallAvailability()
            publishIfChanged(\.isInstallingCurrentBuild, false)
        }
    }

    func selectDate(_ date: Date) {
        let normalizedDate = calendar.startOfDay(for: date)
        guard normalizedDate != selectedDate else { return }
        selectedDate = normalizedDate
    }

    var todayUsage: DailyUsage? {
        dailyUsageByDate[calendar.startOfDay(for: Date())]
    }

    var selectedUsage: DailyUsage? {
        dailyUsageByDate[calendar.startOfDay(for: selectedDate)]
    }

    var fiveHourRemainingPercent: Double? {
        latestRateLimitSnapshot.first(where: { $0.windowKind == .fiveHour })?.remainingPercent
    }

    var menuBarFiveHourLeftLabel: String {
        guard let fiveHourRemainingPercent else { return "--%" }
        return "\(DisplayValueFormatter.percent(fiveHourRemainingPercent, fractionDigits: 0))%"
    }

    var rateLimitUpdatedLabel: String {
        guard let lastRateLimitCaptureDate else { return "No rate-limit snapshot yet" }
        return "Updated \(lastRateLimitCaptureDate.formatted(.relative(presentation: .named)))"
    }

    var refreshUpdatedLabel: String {
        guard let lastUpdatedAt else { return "Not refreshed yet" }
        return "Refreshed \(lastUpdatedAt.formatted(date: .omitted, time: .standard))"
    }

    var dataFreshnessLabel: String {
        let refreshText: String
        if let lastUpdatedAt {
            refreshText = "Refreshed \(lastUpdatedAt.formatted(date: .omitted, time: .standard))"
        } else {
            refreshText = "Refresh pending"
        }

        let rateLimitText: String
        if let lastRateLimitCaptureDate {
            rateLimitText = "Rate limits \(lastRateLimitCaptureDate.formatted(.relative(presentation: .named)))"
        } else {
            rateLimitText = "Rate limits unavailable"
        }

        return "\(refreshText) • \(rateLimitText)"
    }

    var currentVsTypicalRatio: Double? {
        guard typicalHourTokens > 0 else { return nil }
        return Double(currentHourTokens) / typicalHourTokens
    }

    private func startBackgroundRefreshTimer() {
        guard backgroundActivityScheduler == nil else { return }

        let scheduler = NSBackgroundActivityScheduler(identifier: "arisabogal.CodexPulse.background-refresh")
        scheduler.repeats = true
        scheduler.interval = 30 * 60
        scheduler.tolerance = 5 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            self?.scheduleRefresh(reason: .backgroundTimer, debounceSeconds: 0)
            completion(.finished)
        }
        backgroundActivityScheduler = scheduler
    }

    private func startForegroundRefreshTimer() {
        guard foregroundRefreshTask == nil else { return }

        foregroundRefreshTask = Task(priority: .utility) { [weak self] in
            while !(Task.isCancelled) {
                do {
                    try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                } catch {
                    return
                }
                self?.scheduleRefresh(reason: .foregroundTimer, debounceSeconds: 0)
            }
        }
    }

    private func scheduleRefresh(reason _: RefreshReason, debounceSeconds: TimeInterval) {
        pendingRefreshTask?.cancel()

        pendingRefreshTask = Task { [weak self] in
            if debounceSeconds > 0 {
                let nanos = UInt64(debounceSeconds * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    return
                }
            }

            guard let self, !Task.isCancelled else { return }
            await self.performRefresh()
        }
    }

    private func performRefresh() async {
        runningRefreshTask?.cancel()
        publishIfChanged(\.errorMessage, nil)
        publishIfChanged(\.isRefreshing, true)
        defer {
            publishIfChanged(\.lastUpdatedAt, Date())
            publishIfChanged(\.isRefreshing, false)
        }

        let scanTask = Task(priority: .utility) { [scanner] in
            try await scanner.loadSnapshot()
        }
        runningRefreshTask = scanTask

        do {
            let snapshot = try await scanTask.value
            let now = Date()

            publishIfChanged(\.latestRateLimitSnapshot, snapshot.latestRateLimitSnapshot)
            publishIfChanged(\.lastRateLimitCaptureDate, snapshot.latestRateLimitSnapshot.map(\.capturedAt).max())
            publishIfChanged(\.rateLimitFreshness, freshness(for: lastRateLimitCaptureDate, now: now))

            if shouldSkipRebuild(for: snapshot, now: now) {
                await evaluateAlerts()
            } else {
                latestSessions = snapshot.sessions
                applyUsageState(allSessions: snapshot.sessions, now: now)
                lastAppliedDay = calendar.startOfDay(for: now)
                lastAppliedHour = calendar.dateInterval(of: .hour, for: now)?.start
            }
        } catch is CancellationError {
            // Ignore cancellations when a newer refresh supersedes this one.
        } catch {
            publishIfChanged(\.errorMessage, "Unable to refresh from ~/.codex/sessions")
        }
    }

    private func refreshInstallAvailability() {
        let status = AppInstallationService.status()
        publishIfChanged(\.canInstallCurrentBuild, status.canInstallCurrentBuild)
        publishIfChanged(\.installDestinationPath, status.destinationURL.path)
    }

    private func rebuildFromCachedSessions(now: Date) {
        publishIfChanged(\.rateLimitFreshness, freshness(for: lastRateLimitCaptureDate, now: now))
        applyUsageState(allSessions: latestSessions, now: now)
    }

    private func applyUsageState(allSessions: [SessionUsageRecord], now: Date) {
        let normalizedScopes = makeProjectScopes(from: allSessions)
        publishIfChanged(\.projectScopes, normalizedScopes)

        if !normalizedScopes.contains(where: { $0.id == selectedProjectScopeID }) {
            publishIfChanged(\.selectedProjectScopeID, ProjectScope.allID)
            defaults.set(ProjectScope.allID, forKey: Self.selectedProjectDefaultsKey)
        }

        let selectedSessions = sessionsForSelectedScope(from: allSessions)
        let interval = visibleRange(anchoredAt: now)

        let selectedDailyUsage = aggregator.aggregateDailyUsage(
            sessions: selectedSessions,
            within: interval,
            calendar: calendar
        )
        let selectedMap = Dictionary(uniqueKeysWithValues: selectedDailyUsage.map { (calendar.startOfDay(for: $0.date), $0) })

        publishIfChanged(\.dailyUsageByDate, selectedMap)
        publishIfChanged(\.heatmapWeeks, makeHeatmapWeeks(from: selectedMap, anchorDate: now))
        publishIfChanged(\.fallbackPricingUsedInVisibleRange, selectedDailyUsage.contains { $0.containsFallbackPricing })

        var selectedTotalTokens = 0
        var selectedTotalCost = 0.0
        for usage in selectedDailyUsage {
            selectedTotalTokens += usage.totalTokens
            selectedTotalCost += usage.estimatedCostUSD
        }
        publishIfChanged(\.totalTokensInVisibleRange, selectedTotalTokens)
        publishIfChanged(\.totalCostInVisibleRange, selectedTotalCost)

        let selectedRollups = periodRollups(from: selectedMap, now: now)
        publishIfChanged(\.todayTokens, selectedRollups.dailyTokens)
        publishIfChanged(\.weeklyTokens, selectedRollups.weeklyTokens)
        publishIfChanged(\.last30DaysTokens, selectedRollups.last30DaysTokens)
        publishIfChanged(\.dailyCostUSD, selectedRollups.dailyCost)
        publishIfChanged(\.weeklyCostUSD, selectedRollups.weeklyCost)
        publishIfChanged(\.last30DaysCostUSD, selectedRollups.last30DaysCost)

        publishIfChanged(\.todayTrend, selectedRollups.dailyTrend)
        publishIfChanged(\.weeklyTrend, selectedRollups.weeklyTrend)
        publishIfChanged(\.last30DaysTrend, selectedRollups.last30DaysTrend)

        let hotHour = currentVsTypicalHour(from: selectedSessions, now: now)
        publishIfChanged(\.currentHourTokens, hotHour.currentHourTokens)
        publishIfChanged(\.typicalHourTokens, hotHour.typicalHourTokens)
        publishIfChanged(\.peakHourlyTokens, hotHour.peakHourlyTokens)
        publishIfChanged(\.peakHourlyDate, hotHour.peakHourlyDate)

        let milestones = usageMilestones(from: selectedSessions, now: now)
        publishIfChanged(\.longestUsageStreakDays, milestones.longestUsageStreakDays)
        publishIfChanged(\.mostProductiveDayDate, milestones.mostProductiveDayDate)
        publishIfChanged(\.mostProductiveDayTokens, milestones.mostProductiveDayTokens)
        publishIfChanged(\.weeklyMostProductiveDayDate, milestones.weeklyMostProductiveDayDate)
        publishIfChanged(\.weeklyMostProductiveDayTokens, milestones.weeklyMostProductiveDayTokens)
        publishIfChanged(\.weeklyPeakHourlyTokens, milestones.weeklyPeakHourlyTokens)
        publishIfChanged(\.weeklyPeakHourlyDate, milestones.weeklyPeakHourlyDate)

        if selectedMap[calendar.startOfDay(for: selectedDate)] == nil {
            publishIfChanged(\.selectedDate, calendar.startOfDay(for: now))
        }

        scheduleAlertEvaluation(
            rateLimitSnapshots: latestRateLimitSnapshot
        )
    }

    private func evaluateAlerts() async {
        scheduleAlertEvaluation(
            rateLimitSnapshots: latestRateLimitSnapshot
        )
    }

    private func scheduleAlertEvaluation(rateLimitSnapshots: [RateLimitSnapshot]) {
        let input = AlertEvaluationInput(rateLimitSnapshots: rateLimitSnapshots)
        guard input != lastAlertEvaluationInput else { return }
        lastAlertEvaluationInput = input

        alertEvaluationTask?.cancel()
        alertEvaluationTask = Task(priority: .utility) { [alertService] in
            await alertService.evaluate(rateLimitSnapshots: rateLimitSnapshots)
        }
    }

    private func makeProjectScopes(from sessions: [SessionUsageRecord]) -> [ProjectScope] {
        var projectNames: Set<String> = []
        var containsUnassigned = false

        for session in sessions {
            if let projectName = normalizedProjectName(session.projectName) {
                projectNames.insert(projectName)
            } else {
                containsUnassigned = true
            }
        }

        var scopes: [ProjectScope] = [ProjectScope.all]
        scopes.append(contentsOf: projectNames.sorted().map { ProjectScope(id: $0, title: $0) })
        if containsUnassigned {
            scopes.append(.unassigned)
        }
        return scopes
    }

    private func sessionsForSelectedScope(from sessions: [SessionUsageRecord]) -> [SessionUsageRecord] {
        switch selectedProjectScopeID {
        case ProjectScope.allID:
            return sessions
        case ProjectScope.unassignedID:
            return sessions.filter { normalizedProjectName($0.projectName) == nil }
        default:
            return sessions.filter { normalizedProjectName($0.projectName) == selectedProjectScopeID }
        }
    }

    private func normalizedProjectName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shouldSkipRebuild(for snapshot: UsageScanSnapshot, now: Date) -> Bool {
        let today = calendar.startOfDay(for: now)
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start
        return snapshot.scannedFileCount == 0
            && snapshot.latestRateLimitSnapshot == latestRateLimitSnapshot
            && lastAppliedDay == today
            && lastAppliedHour == hourStart
    }

    private func periodRollups(from map: [Date: DailyUsage], now: Date) -> PeriodRollups {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let dailyTokens = map[today]?.totalTokens ?? 0
        let dailyCost = map[today]?.estimatedCostUSD ?? 0
        let previousDailyTokens = map[yesterday]?.totalTokens ?? 0

        var weeklyTokens = 0
        var weeklyCost = 0.0
        var previousWeeklyTokens = 0

        for offset in 0 ..< 7 {
            let currentDay = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            if let usage = map[currentDay] {
                weeklyTokens += usage.totalTokens
                weeklyCost += usage.estimatedCostUSD
            }

            let previousWindowDay = calendar.date(byAdding: .day, value: -(offset + 7), to: today) ?? today
            previousWeeklyTokens += map[previousWindowDay]?.totalTokens ?? 0
        }

        var last30DaysTokens = 0
        var last30DaysCost = 0.0
        var previous30DaysTokens = 0

        for offset in 0 ..< 30 {
            let currentDay = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            if let usage = map[currentDay] {
                last30DaysTokens += usage.totalTokens
                last30DaysCost += usage.estimatedCostUSD
            }

            let previousDay = calendar.date(byAdding: .day, value: -(offset + 30), to: today) ?? today
            previous30DaysTokens += map[previousDay]?.totalTokens ?? 0
        }

        return PeriodRollups(
            dailyTokens: dailyTokens,
            weeklyTokens: weeklyTokens,
            last30DaysTokens: last30DaysTokens,
            dailyCost: dailyCost,
            weeklyCost: weeklyCost,
            last30DaysCost: last30DaysCost,
            dailyTrend: trendSnapshot(current: dailyTokens, previous: previousDailyTokens),
            weeklyTrend: trendSnapshot(current: weeklyTokens, previous: previousWeeklyTokens),
            last30DaysTrend: trendSnapshot(current: last30DaysTokens, previous: previous30DaysTokens)
        )
    }

    private func trendSnapshot(current: Int, previous: Int) -> TrendSnapshot {
        guard previous > 0 else {
            if current == 0 { return .flat }
            return TrendSnapshot(direction: .up, percentMagnitude: 100)
        }

        let delta = Double(current - previous)
        let percent = (delta / Double(previous)) * 100
        let magnitude = Int(abs(percent).rounded())

        if magnitude == 0 {
            return .flat
        }
        return percent > 0
            ? TrendSnapshot(direction: .up, percentMagnitude: magnitude)
            : TrendSnapshot(direction: .down, percentMagnitude: magnitude)
    }

    private func currentVsTypicalHour(from sessions: [SessionUsageRecord], now: Date) -> CurrentHourStats {
        guard let hourInterval = calendar.dateInterval(of: .hour, for: now) else {
            return CurrentHourStats(
                currentHourTokens: 0,
                typicalHourTokens: 0,
                peakHourlyTokens: 0,
                peakHourlyDate: nil
            )
        }

        let hourStart = hourInterval.start
        let weekday = calendar.component(.weekday, from: hourStart)
        let hour = calendar.component(.hour, from: hourStart)
        let lookbackStart = calendar.date(byAdding: .day, value: -84, to: hourStart) ?? .distantPast

        var currentHourTokens = 0
        var historicalBuckets: [Date: Int] = [:]
        var hourlyBuckets: [Date: Int] = [:]

        for session in sessions {
            let timestamp = session.timestamp

            currentHourTokens += max(0, session.tokensInLastHour)

            if let bucketHour = calendar.dateInterval(of: .hour, for: timestamp)?.start {
                hourlyBuckets[bucketHour, default: 0] += session.totalTokens
            }

            guard timestamp >= lookbackStart, timestamp < hourStart else { continue }
            guard calendar.component(.weekday, from: timestamp) == weekday else { continue }
            guard calendar.component(.hour, from: timestamp) == hour else { continue }

            let day = calendar.startOfDay(for: timestamp)
            historicalBuckets[day, default: 0] += session.totalTokens
        }

        let recentDays = historicalBuckets.keys.sorted(by: >).prefix(8)
        let typicalHourTokens: Double
        if recentDays.isEmpty {
            typicalHourTokens = 0
        } else {
            let sum = recentDays.reduce(0) { $0 + (historicalBuckets[$1] ?? 0) }
            typicalHourTokens = Double(sum) / Double(recentDays.count)
        }

        let peakEntry = hourlyBuckets.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value < rhs.value
        }

        return CurrentHourStats(
            currentHourTokens: currentHourTokens,
            typicalHourTokens: typicalHourTokens,
            peakHourlyTokens: peakEntry?.value ?? 0,
            peakHourlyDate: peakEntry?.key
        )
    }

    private func usageMilestones(from sessions: [SessionUsageRecord], now: Date) -> UsageMilestones {
        guard !sessions.isEmpty else {
            return UsageMilestones(
                longestUsageStreakDays: 0,
                mostProductiveDayDate: nil,
                mostProductiveDayTokens: 0,
                weeklyMostProductiveDayDate: nil,
                weeklyMostProductiveDayTokens: 0,
                weeklyPeakHourlyTokens: 0,
                weeklyPeakHourlyDate: nil
            )
        }

        let today = calendar.startOfDay(for: now)
        let rollingWeekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let rollingWeekEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? now

        var dailyTotals: [Date: Int] = [:]
        var hourlyTotals: [Date: Int] = [:]

        for session in sessions {
            let day = calendar.startOfDay(for: session.timestamp)
            dailyTotals[day, default: 0] += session.totalTokens

            if let hourBucket = calendar.dateInterval(of: .hour, for: session.timestamp)?.start {
                hourlyTotals[hourBucket, default: 0] += session.totalTokens
            }
        }

        let mostProductiveDay = dailyTotals.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value < rhs.value
        }

        let weeklyMostProductiveDay = dailyTotals
            .filter { $0.key >= rollingWeekStart && $0.key < rollingWeekEnd }
            .max { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value < rhs.value
            }

        let weeklyPeakHourly = hourlyTotals
            .filter { $0.key >= rollingWeekStart && $0.key < rollingWeekEnd }
            .max { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value < rhs.value
            }

        return UsageMilestones(
            longestUsageStreakDays: longestStreakLength(in: Set(dailyTotals.keys)),
            mostProductiveDayDate: mostProductiveDay?.key,
            mostProductiveDayTokens: mostProductiveDay?.value ?? 0,
            weeklyMostProductiveDayDate: weeklyMostProductiveDay?.key,
            weeklyMostProductiveDayTokens: weeklyMostProductiveDay?.value ?? 0,
            weeklyPeakHourlyTokens: weeklyPeakHourly?.value ?? 0,
            weeklyPeakHourlyDate: weeklyPeakHourly?.key
        )
    }

    private func longestStreakLength(in usageDays: Set<Date>) -> Int {
        let sortedDays = usageDays.sorted()
        guard let firstDay = sortedDays.first else { return 0 }

        var previousDay = firstDay
        var currentStreak = 1
        var longestStreak = 1

        for day in sortedDays.dropFirst() {
            let distance = calendar.dateComponents([.day], from: previousDay, to: day).day ?? 0
            if distance == 1 {
                currentStreak += 1
            } else if distance > 1 {
                currentStreak = 1
            }
            longestStreak = max(longestStreak, currentStreak)
            previousDay = day
        }

        return longestStreak
    }

    private func visibleRange(anchoredAt date: Date) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -364, to: startOfToday) ?? startOfToday
        let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? date
        return DateInterval(start: start, end: end)
    }

    private func makeHeatmapWeeks(from map: [Date: DailyUsage], anchorDate: Date) -> [[HeatmapDayCell]] {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone

        let todayStart = calendar.startOfDay(for: anchorDate)
        let currentWeekStart = iso.date(from: iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: todayStart)) ?? todayStart
        let gridStart = iso.date(byAdding: .weekOfYear, value: -51, to: currentWeekStart) ?? todayStart

        var provisionalWeeks: [[HeatmapDayCell]] = []
        var positiveTotals: [Int] = []

        for weekOffset in 0 ..< 52 {
            var week: [HeatmapDayCell] = []
            for dayOffset in 0 ..< 7 {
                let dayIndex = (weekOffset * 7) + dayOffset
                let date = iso.date(byAdding: .day, value: dayIndex, to: gridStart) ?? gridStart
                let day = calendar.startOfDay(for: date)
                let usage = map[day]
                if let total = usage?.totalTokens, total > 0 {
                    positiveTotals.append(total)
                }
                week.append(HeatmapDayCell(date: day, usage: usage, level: 0))
            }
            provisionalWeeks.append(week)
        }

        let thresholds = intensityThresholds(from: positiveTotals)

        return provisionalWeeks.map { week in
            week.map { cell in
                let level = intensityLevel(for: cell.totalTokens, thresholds: thresholds)
                return HeatmapDayCell(date: cell.date, usage: cell.usage, level: level)
            }
        }
    }

    private func intensityThresholds(from totals: [Int]) -> [Int] {
        let sorted = totals.sorted()
        guard !sorted.isEmpty else { return [] }

        func percentile(_ p: Double) -> Int {
            let index = Int(Double(sorted.count - 1) * p)
            return sorted[max(0, min(index, sorted.count - 1))]
        }

        return [
            percentile(0.20),
            percentile(0.40),
            percentile(0.60),
            percentile(0.80),
        ]
    }

    private func intensityLevel(for totalTokens: Int, thresholds: [Int]) -> Int {
        guard totalTokens > 0 else { return 0 }
        guard thresholds.count == 4 else { return 1 }

        if totalTokens <= thresholds[0] { return 1 }
        if totalTokens <= thresholds[1] { return 2 }
        if totalTokens <= thresholds[2] { return 3 }
        return 4
    }

    func freshness(for captureDate: Date?, now: Date = Date()) -> RateLimitFreshness {
        Self.freshness(for: captureDate, now: now)
    }

    static func freshness(for captureDate: Date?, now: Date = Date()) -> RateLimitFreshness {
        guard let captureDate else { return .unavailable }
        let age = now.timeIntervalSince(captureDate)
        return age <= 15 * 60 ? .fresh : .stale
    }

    private func publishIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<HeatmapViewModel, T>, _ newValue: T) {
        guard self[keyPath: keyPath] != newValue else { return }
        self[keyPath: keyPath] = newValue
    }
}

private struct CurrentHourStats {
    let currentHourTokens: Int
    let typicalHourTokens: Double
    let peakHourlyTokens: Int
    let peakHourlyDate: Date?
}

private struct UsageMilestones {
    let longestUsageStreakDays: Int
    let mostProductiveDayDate: Date?
    let mostProductiveDayTokens: Int
    let weeklyMostProductiveDayDate: Date?
    let weeklyMostProductiveDayTokens: Int
    let weeklyPeakHourlyTokens: Int
    let weeklyPeakHourlyDate: Date?
}

private struct PeriodRollups {
    let dailyTokens: Int
    let weeklyTokens: Int
    let last30DaysTokens: Int
    let dailyCost: Double
    let weeklyCost: Double
    let last30DaysCost: Double
    let dailyTrend: TrendSnapshot
    let weeklyTrend: TrendSnapshot
    let last30DaysTrend: TrendSnapshot
}

private struct AlertEvaluationInput: Equatable {
    let rateLimitSnapshots: [RateLimitSnapshot]
}

private extension TrendSnapshot {
    static let flat = TrendSnapshot(direction: .flat, percentMagnitude: 0)
}

private enum RefreshReason {
    case launch
    case popoverOpen
    case manual
    case foregroundTimer
    case backgroundTimer
}
