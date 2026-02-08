import Foundation

struct SessionUsageRecord: Identifiable, Codable, Hashable {
    let id: String
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
    let estimatedCostUSD: Double
    let usedFallbackPricing: Bool

    init(
        sessionID: String,
        projectName: String? = nil,
        model: String,
        timestamp: Date,
        latestUsageTimestamp: Date? = nil,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int,
        totalTokens: Int,
        tokensInLastHour: Int = 0,
        estimatedCostUSD: Double,
        usedFallbackPricing: Bool
    ) {
        self.id = sessionID
        self.sessionID = sessionID
        self.projectName = projectName
        self.model = model
        self.timestamp = timestamp
        self.latestUsageTimestamp = latestUsageTimestamp
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.tokensInLastHour = tokensInLastHour
        self.estimatedCostUSD = estimatedCostUSD
        self.usedFallbackPricing = usedFallbackPricing
    }
}
