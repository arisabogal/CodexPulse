import Foundation

struct PricingResolution: Hashable {
    let tier: PricingTier
    let normalizedModel: String
}

struct PricingCatalog {
    func resolution(for modelName: String) -> PricingResolution {
        let normalized = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.contains("gpt-5.3-codex") {
            return PricingResolution(tier: .gpt53CodexAliasTo52, normalizedModel: "gpt-5.3-codex")
        }
        if normalized.contains("gpt-5.2-codex-mini") {
            return PricingResolution(tier: .gpt52CodexMini, normalizedModel: "gpt-5.2-codex-mini")
        }
        if normalized.contains("gpt-5.2-codex") {
            return PricingResolution(tier: .gpt52Codex, normalizedModel: "gpt-5.2-codex")
        }
        if normalized.contains("codex-mini") {
            return PricingResolution(tier: .fallbackCodexMini, normalizedModel: normalized)
        }
        if normalized.contains("codex") {
            return PricingResolution(tier: .fallbackCodex, normalizedModel: normalized)
        }

        return PricingResolution(tier: .fallbackCodex, normalizedModel: normalized.isEmpty ? "unknown-codex" : normalized)
    }
}
