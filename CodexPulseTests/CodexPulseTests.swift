import Foundation
import Testing
@testable import CodexPulse

struct CodexPulseTests {
    @Test
    @MainActor
    func scannerParsesSessionUsageAndRateLimitWindows() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionsDirectory = root.appendingPathComponent("sessions/2026/02/08", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let fileURL = sessionsDirectory.appendingPathComponent("rollout-2026-02-08T12-00-00-test.jsonl")
        let lines = [
            "{\"timestamp\":\"2026-02-08T12:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"session-1\",\"timestamp\":\"2026-02-08T12:00:00Z\"}}",
            "{\"timestamp\":\"2026-02-08T12:00:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-5.3-codex\"}}",
            "{\"timestamp\":\"2026-02-08T12:00:02Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":null,\"rate_limits\":{\"primary\":{\"used_percent\":10.0,\"window_minutes\":300,\"resets_at\":1766000000},\"secondary\":{\"used_percent\":20.0,\"window_minutes\":10080,\"resets_at\":1766600000}}}}",
            "{\"timestamp\":\"2026-02-08T12:00:03Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":200,\"cached_input_tokens\":50,\"output_tokens\":90,\"reasoning_output_tokens\":10,\"total_tokens\":300}},\"rate_limits\":{\"primary\":{\"used_percent\":37.5,\"window_minutes\":300,\"resets_at\":1766001234},\"secondary\":{\"used_percent\":12.5,\"window_minutes\":10080,\"resets_at\":1766601234}}}}",
        ]

        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let scanner = CodexSessionScanner(
            sessionsRootURL: root.appendingPathComponent("sessions", isDirectory: true),
            cacheURL: root.appendingPathComponent("cache.json")
        )

        let snapshot = try await scanner.loadSnapshot()

        #expect(snapshot.sessions.count == 1)
        let session = try #require(snapshot.sessions.first)
        #expect(session.model == "gpt-5.3-codex")
        #expect(session.totalTokens == 300)
        #expect(session.usedFallbackPricing)

        let expectedCost = 0.00077125
        #expect(abs(session.estimatedCostUSD - expectedCost) < 0.0000001)

        #expect(snapshot.latestRateLimitSnapshot.count == 2)
        let fiveHour = try #require(snapshot.latestRateLimitSnapshot.first(where: { $0.windowKind == .fiveHour }))
        let weekly = try #require(snapshot.latestRateLimitSnapshot.first(where: { $0.windowKind == .weekly }))
        #expect(fiveHour.windowMinutes == 300)
        #expect(weekly.windowMinutes == 10080)
        #expect(abs(fiveHour.usedPercent - 37.5) < 0.0001)
        #expect(abs(weekly.usedPercent - 12.5) < 0.0001)
    }

    @Test
    @MainActor
    func scannerUsesIncrementalCacheAcrossRefreshes() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionsDirectory = root.appendingPathComponent("sessions/2026/02/08", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let fileURL = sessionsDirectory.appendingPathComponent("rollout-2026-02-08T13-00-00-test.jsonl")
        let lines = [
            "{\"timestamp\":\"2026-02-08T13:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"session-2\",\"timestamp\":\"2026-02-08T13:00:00Z\"}}",
            "{\"timestamp\":\"2026-02-08T13:00:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-5.2-codex\"}}",
            "{\"timestamp\":\"2026-02-08T13:00:02Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":10,\"cached_input_tokens\":0,\"output_tokens\":4,\"reasoning_output_tokens\":0,\"total_tokens\":14}}}}",
        ]
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let scanner = CodexSessionScanner(
            sessionsRootURL: root.appendingPathComponent("sessions", isDirectory: true),
            cacheURL: root.appendingPathComponent("cache.json")
        )

        let first = try await scanner.loadSnapshot()
        let second = try await scanner.loadSnapshot()

        #expect(first.scannedFileCount == 1)
        #expect(second.scannedFileCount == 0)
        #expect(second.cacheHitCount >= 1)
    }

    @Test
    @MainActor
    func pricingAliasAndFreshnessBehaveAsExpected() {
        let estimator = CostEstimator()
        let catalog = PricingCatalog()

        let aliased = estimator.estimate(
            modelName: "gpt-5.3-codex",
            inputTokens: 500_000,
            cachedInputTokens: 200_000,
            outputTokens: 100_000,
            pricingCatalog: catalog
        )

        let base = estimator.estimate(
            modelName: "gpt-5.2-codex",
            inputTokens: 500_000,
            cachedInputTokens: 200_000,
            outputTokens: 100_000,
            pricingCatalog: catalog
        )

        #expect(abs(aliased.estimatedCostUSD - base.estimatedCostUSD) < 0.0000001)
        #expect(aliased.usedFallbackPricing)

        let now = Date()
        #expect(HeatmapViewModel.freshness(for: now.addingTimeInterval(-60), now: now) == .fresh)
        #expect(HeatmapViewModel.freshness(for: now.addingTimeInterval(-3600), now: now) == .stale)
        #expect(HeatmapViewModel.freshness(for: nil, now: now) == .unavailable)
    }

    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
