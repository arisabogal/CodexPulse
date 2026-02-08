import Foundation

struct UsageScanSnapshot {
    let sessions: [SessionUsageRecord]
    let latestRateLimitSnapshot: [RateLimitSnapshot]
    let scannedFileCount: Int
    let cacheHitCount: Int
}

actor CodexSessionScanner {
    private static let cacheVersion = 3

    private let sessionsRootURL: URL
    private let cacheURL: URL
    private let pricingCatalog: PricingCatalog
    private let costEstimator: CostEstimator
    private let fileManager = FileManager.default

    init(
        sessionsRootURL: URL,
        cacheURL: URL,
        pricingCatalog: PricingCatalog = PricingCatalog(),
        costEstimator: CostEstimator = CostEstimator()
    ) {
        self.sessionsRootURL = sessionsRootURL
        self.cacheURL = cacheURL
        self.pricingCatalog = pricingCatalog
        self.costEstimator = costEstimator
    }

    func loadSnapshot(now: Date = Date()) async throws -> UsageScanSnapshot {
        var cache = loadCache()
        let cachedFileCountBeforeScan = cache.files.count
        let sessionFiles = discoverSessionFiles()

        var scannedFileCount = 0
        var cacheHitCount = 0
        var currentPaths: Set<String> = []

        for file in sessionFiles {
            if Task.isCancelled { throw CancellationError() }
            currentPaths.insert(file.path)

            if let cached = cache.files[file.path],
               cached.fingerprint == file.fingerprint,
               !shouldRescanRecentFile(cached: cached, now: now) {
                cacheHitCount += 1
                continue
            }

            scannedFileCount += 1
            do {
                let parsed = try await parse(file: file, now: now)
                cache.files[file.path] = CachedFile(
                    fingerprint: file.fingerprint,
                    summary: parsed.summary,
                    latestRateLimitEvent: parsed.latestRateLimitEvent
                )
            } catch {
                // Keep refresh resilient to malformed or inaccessible files.
                cache.files[file.path] = CachedFile(
                    fingerprint: file.fingerprint,
                    summary: nil,
                    latestRateLimitEvent: nil
                )
            }
        }

        let removedPathCount = cache.files.keys.filter { !currentPaths.contains($0) }.count
        cache.files = cache.files.filter { currentPaths.contains($0.key) }

        if scannedFileCount > 0 || removedPathCount > 0 || cache.files.count != cachedFileCountBeforeScan {
            cache.updatedAt = Date()
            saveCache(cache)
        }

        let sessionSummaries = cache.files.values.compactMap(\ .summary)
        let sessions = sessionSummaries.map { summary in
            let estimate = costEstimator.estimate(
                modelName: summary.model,
                inputTokens: summary.inputTokens,
                cachedInputTokens: summary.cachedInputTokens,
                outputTokens: summary.outputTokens,
                pricingCatalog: pricingCatalog
            )

            return SessionUsageRecord(
                sessionID: summary.sessionID,
                projectName: summary.projectName,
                model: summary.model,
                timestamp: summary.timestamp,
                latestUsageTimestamp: summary.latestUsageTimestamp,
                inputTokens: summary.inputTokens,
                cachedInputTokens: summary.cachedInputTokens,
                outputTokens: summary.outputTokens,
                reasoningTokens: summary.reasoningTokens,
                totalTokens: summary.totalTokens,
                tokensInLastHour: summary.tokensInLastHour,
                estimatedCostUSD: estimate.estimatedCostUSD,
                usedFallbackPricing: estimate.usedFallbackPricing
            )
        }

        let latestRateEvent = cache.files.values
            .compactMap(\ .latestRateLimitEvent)
            .max(by: { $0.capturedAt < $1.capturedAt })

        return UsageScanSnapshot(
            sessions: sessions,
            latestRateLimitSnapshot: makeRateLimitSnapshots(from: latestRateEvent),
            scannedFileCount: scannedFileCount,
            cacheHitCount: cacheHitCount
        )
    }

    private func discoverSessionFiles() -> [SessionFile] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsRootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [SessionFile] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]), values.isRegularFile == true else {
                continue
            }

            let size = Int64(values.fileSize ?? 0)
            let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let fingerprint = FileFingerprint(size: size, modifiedAt: mtime)
            files.append(SessionFile(url: url, path: url.path, fingerprint: fingerprint))
        }

        return files.sorted(by: { $0.path < $1.path })
    }

    private func parse(file: SessionFile, now: Date) async throws -> ParsedFile {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        var sessionID: String?
        var sessionTimestamp: Date?
        var model: String?
        var workingDirectory: String?
        var repositoryURL: String?
        var maxTotalTokens = -1
        var maxUsage: RawTokenUsage?
        var latestUsageTimestamp: Date?
        var latestRateLimitEvent: CachedRateLimitEvent?
        var usageCheckpoints: [TokenUsageCheckpoint] = []

        for try await line in handle.bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8) else { continue }
            guard let raw = try? decoder.decode(RawEnvelope.self, from: data) else { continue }

            switch raw.type {
            case "session_meta":
                if sessionID == nil {
                    sessionID = raw.payload?.id
                }
                if sessionTimestamp == nil {
                    sessionTimestamp = parseDate(raw.payload?.timestamp) ?? parseDate(raw.timestamp)
                }
                if workingDirectory == nil {
                    workingDirectory = raw.payload?.cwd
                }
                if repositoryURL == nil {
                    repositoryURL = raw.payload?.git?.repositoryUrl
                }

            case "turn_context":
                if let parsedModel = raw.payload?.model, !parsedModel.isEmpty {
                    model = parsedModel
                }
                if workingDirectory == nil {
                    workingDirectory = raw.payload?.cwd
                }

            case "event_msg":
                guard raw.payload?.type == "token_count" else { continue }
                let eventTimestamp = parseDate(raw.timestamp)

                if let usage = raw.payload?.info?.totalTokenUsage,
                   let totalTokens = usage.totalTokens,
                   totalTokens >= maxTotalTokens {
                    maxTotalTokens = totalTokens
                    maxUsage = usage
                    latestUsageTimestamp = eventTimestamp
                }

                if let usage = raw.payload?.info?.totalTokenUsage,
                   let totalTokens = usage.totalTokens,
                   let eventTimestamp {
                    usageCheckpoints.append(
                        TokenUsageCheckpoint(
                            timestamp: eventTimestamp,
                            totalTokens: totalTokens
                        )
                    )
                }

                if let rateLimits = raw.payload?.rateLimits,
                   (rateLimits.primary != nil || rateLimits.secondary != nil) {
                    let capturedAt = eventTimestamp ?? Date(timeIntervalSince1970: file.fingerprint.modifiedAt)
                    if latestRateLimitEvent == nil || (latestRateLimitEvent?.capturedAt ?? .distantPast) <= capturedAt {
                        latestRateLimitEvent = CachedRateLimitEvent(
                            capturedAt: capturedAt,
                            primary: CachedRateWindowPayload(rateLimits.primary),
                            secondary: CachedRateWindowPayload(rateLimits.secondary)
                        )
                    }
                }

            default:
                continue
            }
        }

        guard let finalUsage = maxUsage, maxTotalTokens >= 0 else {
            return ParsedFile(summary: nil, latestRateLimitEvent: latestRateLimitEvent)
        }

        let resolvedSessionID = sessionID ?? file.url.deletingPathExtension().lastPathComponent
        let resolvedTimestamp = sessionTimestamp
            ?? latestUsageTimestamp
            ?? Date(timeIntervalSince1970: file.fingerprint.modifiedAt)
        let resolvedLatestUsageTimestamp = latestUsageTimestamp ?? usageCheckpoints.map(\.timestamp).max()
        let tokensInLastHour = rollingHourTokenDelta(from: usageCheckpoints, now: now)

        let summary = CachedSessionSummary(
            sessionID: resolvedSessionID,
            projectName: resolveProjectName(cwd: workingDirectory, repositoryURL: repositoryURL),
            model: model ?? "unknown-codex",
            timestamp: resolvedTimestamp,
            latestUsageTimestamp: resolvedLatestUsageTimestamp,
            inputTokens: finalUsage.inputTokens ?? 0,
            cachedInputTokens: finalUsage.cachedInputTokens ?? 0,
            outputTokens: finalUsage.outputTokens ?? 0,
            reasoningTokens: finalUsage.reasoningOutputTokens ?? 0,
            totalTokens: finalUsage.totalTokens ?? 0,
            tokensInLastHour: tokensInLastHour
        )

        return ParsedFile(summary: summary, latestRateLimitEvent: latestRateLimitEvent)
    }

    private func makeRateLimitSnapshots(from event: CachedRateLimitEvent?) -> [RateLimitSnapshot] {
        guard let event else { return [] }

        var snapshots: [RateLimitSnapshot] = []

        if let primary = event.primary, primary.windowMinutes == 300 {
            let used = clampPercentage(primary.usedPercent)
            snapshots.append(
                RateLimitSnapshot(
                    windowKind: .fiveHour,
                    usedPercent: used,
                    remainingPercent: max(0, 100 - used),
                    windowMinutes: primary.windowMinutes,
                    resetsAt: Date(timeIntervalSince1970: primary.resetsAt),
                    capturedAt: event.capturedAt
                )
            )
        }

        if let secondary = event.secondary, secondary.windowMinutes == 10080 {
            let used = clampPercentage(secondary.usedPercent)
            snapshots.append(
                RateLimitSnapshot(
                    windowKind: .weekly,
                    usedPercent: used,
                    remainingPercent: max(0, 100 - used),
                    windowMinutes: secondary.windowMinutes,
                    resetsAt: Date(timeIntervalSince1970: secondary.resetsAt),
                    capturedAt: event.capturedAt
                )
            )
        }

        return snapshots.sorted(by: { $0.windowMinutes < $1.windowMinutes })
    }

    private func clampPercentage(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private func shouldRescanRecentFile(cached: CachedFile, now: Date) -> Bool {
        guard let summary = cached.summary else { return false }
        if summary.tokensInLastHour > 0 { return true }
        guard let latestUsageTimestamp = summary.latestUsageTimestamp else { return false }
        return latestUsageTimestamp >= now.addingTimeInterval(-2 * 3600)
    }

    private func rollingHourTokenDelta(from checkpoints: [TokenUsageCheckpoint], now: Date) -> Int {
        guard !checkpoints.isEmpty else { return 0 }

        let cutoff = now.addingTimeInterval(-3600)
        let sortedCheckpoints = checkpoints.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.totalTokens < rhs.totalTokens
            }
            return lhs.timestamp < rhs.timestamp
        }

        var latestTotal: Int?
        var baselineTotal = 0
        var hasBaseline = false

        for checkpoint in sortedCheckpoints {
            guard checkpoint.timestamp <= now else { break }
            latestTotal = checkpoint.totalTokens
            if checkpoint.timestamp <= cutoff {
                baselineTotal = checkpoint.totalTokens
                hasBaseline = true
            }
        }

        guard let latestTotal else { return 0 }
        let baseline = hasBaseline ? baselineTotal : 0
        return max(0, latestTotal - baseline)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return Self.fractionalDateFormatter.date(from: value) ?? Self.dateFormatter.date(from: value)
    }

    private func resolveProjectName(cwd: String?, repositoryURL: String?) -> String? {
        if let repositoryURL {
            let repoName = URL(string: repositoryURL)?
                .deletingPathExtension()
                .lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let repoName, !repoName.isEmpty {
                return repoName
            }
        }

        if let cwd {
            let folderName = URL(fileURLWithPath: cwd)
                .standardizedFileURL
                .lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !folderName.isEmpty {
                return folderName
            }
        }

        return nil
    }

    private func loadCache() -> ScannerCache {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(ScannerCache.self, from: data)
        else {
            return ScannerCache(version: Self.cacheVersion, files: [:], updatedAt: Date())
        }

        guard cache.version == Self.cacheVersion else {
            return ScannerCache(version: Self.cacheVersion, files: [:], updatedAt: Date())
        }

        return cache
    }

    private func saveCache(_ cache: ScannerCache) {
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Ignore cache-write failures; the next refresh can still proceed.
        }
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct SessionFile {
    let url: URL
    let path: String
    let fingerprint: FileFingerprint
}

private struct ParsedFile {
    let summary: CachedSessionSummary?
    let latestRateLimitEvent: CachedRateLimitEvent?
}

private struct ScannerCache: Codable {
    let version: Int
    var files: [String: CachedFile]
    var updatedAt: Date
}

private struct CachedFile: Codable {
    let fingerprint: FileFingerprint
    let summary: CachedSessionSummary?
    let latestRateLimitEvent: CachedRateLimitEvent?
}

private struct FileFingerprint: Codable, Equatable {
    let size: Int64
    let modifiedAt: TimeInterval
}

private struct CachedSessionSummary: Codable {
    let sessionID: String
    let projectName: String?
    let model: String
    let timestamp: Date
    let latestUsageTimestamp: Date?
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let tokensInLastHour: Int
}

private struct TokenUsageCheckpoint {
    let timestamp: Date
    let totalTokens: Int
}

private struct CachedRateLimitEvent: Codable {
    let capturedAt: Date
    let primary: CachedRateWindowPayload?
    let secondary: CachedRateWindowPayload?
}

private struct CachedRateWindowPayload: Codable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: TimeInterval

    init?(_ payload: RawRateWindow?) {
        guard let payload,
              let usedPercent = payload.usedPercent,
              let windowMinutes = payload.windowMinutes,
              let resetsAt = payload.resetsAt
        else {
            return nil
        }

        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

private struct RawEnvelope: Decodable {
    let timestamp: String?
    let type: String
    let payload: RawPayload?
}

private struct RawPayload: Decodable {
    let id: String?
    let timestamp: String?
    let cwd: String?
    let model: String?
    let type: String?
    let info: RawTokenInfo?
    let rateLimits: RawRateLimits?
    let git: RawGit?
}

private struct RawGit: Decodable {
    let repositoryUrl: String?
}

private struct RawTokenInfo: Decodable {
    let totalTokenUsage: RawTokenUsage?
}

private struct RawTokenUsage: Decodable {
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
    let reasoningOutputTokens: Int?
    let totalTokens: Int?
}

private struct RawRateLimits: Decodable {
    let primary: RawRateWindow?
    let secondary: RawRateWindow?
}

private struct RawRateWindow: Decodable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: TimeInterval?
}
