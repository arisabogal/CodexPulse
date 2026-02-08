import Foundation

struct DailyUsage: Identifiable, Codable, Hashable {
    var id: Date { date }

    let date: Date
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let sessionCount: Int
    let estimatedCostUSD: Double
    let containsFallbackPricing: Bool
}

enum DisplayValueFormatter {
    private static let oneDecimalStyle = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
    private static let groupingStyle = IntegerFormatStyle<Int>.number.grouping(.automatic)

    static func compactCount(_ value: Int) -> String {
        let absoluteValue = abs(Double(value))
        let sign = value < 0 ? "-" : ""

        if absoluteValue >= 1_000_000_000 {
            let scaled = absoluteValue / 1_000_000_000
            return "\(sign)\(scaled.formatted(oneDecimalStyle))B"
        }

        if absoluteValue >= 1_000_000 {
            let scaled = absoluteValue / 1_000_000
            return "\(sign)\(scaled.formatted(oneDecimalStyle))M"
        }

        return value.formatted(groupingStyle)
    }

    static func currency(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    static func percent(_ value: Double, fractionDigits: Int = 1) -> String {
        let clampedDigits = max(0, fractionDigits)
        return value.formatted(.number.precision(.fractionLength(clampedDigits)))
    }
}
