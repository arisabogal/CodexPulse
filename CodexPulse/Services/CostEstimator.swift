import Foundation

struct CostEstimate: Hashable {
    let estimatedCostUSD: Double
    let usedFallbackPricing: Bool
    let pricingTier: PricingTier
}

struct CostEstimator {
    func estimate(
        modelName: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        pricingCatalog: PricingCatalog
    ) -> CostEstimate {
        let resolution = pricingCatalog.resolution(for: modelName)
        let rates = resolution.tier.rates

        let safeInput = max(0, inputTokens)
        let safeCached = max(0, cachedInputTokens)
        let safeOutput = max(0, outputTokens)
        let nonCachedInput = max(0, safeInput - safeCached)

        let inputCost = Double(nonCachedInput) / 1_000_000.0 * rates.inputPerMillion
        let cachedInputCost = Double(safeCached) / 1_000_000.0 * rates.cachedInputPerMillion
        let outputCost = Double(safeOutput) / 1_000_000.0 * rates.outputPerMillion

        return CostEstimate(
            estimatedCostUSD: inputCost + cachedInputCost + outputCost,
            usedFallbackPricing: resolution.tier.usedFallbackPricing,
            pricingTier: resolution.tier
        )
    }
}
