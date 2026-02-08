import Foundation

struct UsageAggregator {
    func aggregateDailyUsage(
        sessions: [SessionUsageRecord],
        within range: DateInterval,
        calendar: Calendar
    ) -> [DailyUsage] {
        var buckets: [Date: (input: Int, cached: Int, output: Int, total: Int, sessions: Int, cost: Double, fallback: Bool)] = [:]

        for session in sessions {
            guard range.contains(session.timestamp) else { continue }
            let day = calendar.startOfDay(for: session.timestamp)
            let existing = buckets[day] ?? (0, 0, 0, 0, 0, 0, false)

            buckets[day] = (
                input: existing.input + session.inputTokens,
                cached: existing.cached + session.cachedInputTokens,
                output: existing.output + session.outputTokens,
                total: existing.total + session.totalTokens,
                sessions: existing.sessions + 1,
                cost: existing.cost + session.estimatedCostUSD,
                fallback: existing.fallback || session.usedFallbackPricing
            )
        }

        return buckets.keys.sorted().map { day in
            let bucket = buckets[day] ?? (0, 0, 0, 0, 0, 0, false)
            return DailyUsage(
                date: day,
                inputTokens: bucket.input,
                cachedInputTokens: bucket.cached,
                outputTokens: bucket.output,
                totalTokens: bucket.total,
                sessionCount: bucket.sessions,
                estimatedCostUSD: bucket.cost,
                containsFallbackPricing: bucket.fallback
            )
        }
    }
}
