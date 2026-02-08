import SwiftUI

struct DayDetailView: View {
    let usage: DailyUsage?
    let date: Date
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 6) {
            HStack {
                Text(date.formatted(date: isCompact ? .abbreviated : .complete, time: .omitted))
                    .font((isCompact ? Font.caption : .subheadline).weight(.semibold))

                Spacer()

                if usage?.containsFallbackPricing == true {
                    Text("Alias/Fallback Pricing")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
            }

            if let usage {
                if isCompact {
                    VStack(alignment: .leading, spacing: 6) {
                        metricRow(label: "Tokens", value: DisplayValueFormatter.compactCount(usage.totalTokens))
                        metricRow(label: "Sessions", value: DisplayValueFormatter.compactCount(usage.sessionCount))
                        metricRow(label: "Cost", value: "$\(DisplayValueFormatter.currency(usage.estimatedCostUSD))")
                    }
                } else {
                    HStack(spacing: 14) {
                        metric(label: "Tokens", value: DisplayValueFormatter.compactCount(usage.totalTokens))
                        metric(label: "Sessions", value: DisplayValueFormatter.compactCount(usage.sessionCount))
                        metric(label: "Cost", value: DisplayValueFormatter.currency(usage.estimatedCostUSD), isCurrency: true)
                    }
                }
            } else {
                Text("No usage for this day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func metric(label: String, value: String, isCurrency: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(isCurrency ? "$\(value)" : value)
                .font(.caption.weight(.semibold))
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}
