import Foundation

struct PricingRates: Codable, Hashable {
    let inputPerMillion: Double
    let cachedInputPerMillion: Double
    let outputPerMillion: Double
}

enum PricingTier: String, Codable, Hashable {
    case gpt52Codex
    case gpt52CodexMini
    case gpt53CodexAliasTo52
    case fallbackCodex
    case fallbackCodexMini

    var rates: PricingRates {
        switch self {
        case .gpt52Codex, .gpt53CodexAliasTo52, .fallbackCodex:
            return PricingRates(inputPerMillion: 1.50, cachedInputPerMillion: 0.125, outputPerMillion: 6.00)
        case .gpt52CodexMini, .fallbackCodexMini:
            return PricingRates(inputPerMillion: 0.30, cachedInputPerMillion: 0.025, outputPerMillion: 1.20)
        }
    }

    var usedFallbackPricing: Bool {
        switch self {
        case .gpt52Codex, .gpt52CodexMini:
            return false
        case .gpt53CodexAliasTo52, .fallbackCodex, .fallbackCodexMini:
            return true
        }
    }
}
