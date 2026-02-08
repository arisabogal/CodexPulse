import SwiftUI

enum ShareCardMode: String, CaseIterable, Identifiable {
    case buildHighlights = "Build Highlights"
    case weeklyRecap = "Weekly Recap"
    case buildMode = "Build Mode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buildHighlights:
            return "Build Highlights"
        case .weeklyRecap:
            return "Weekly Recap"
        case .buildMode:
            return "Build Mode"
        }
    }

    var accent: Color {
        switch self {
        case .buildHighlights:
            return Color(red: 0.08, green: 0.73, blue: 0.98)
        case .weeklyRecap:
            return Color(red: 0.16, green: 0.82, blue: 0.50)
        case .buildMode:
            return Color(red: 0.47, green: 0.58, blue: 1.00)
        }
    }
}

struct ShareWeekdayMetric: Identifiable {
    var id: String { label }

    let label: String
    let tokens: Int
}

struct ShareCardSnapshot {
    let mode: ShareCardMode
    let projectTitle: String
    let generatedAt: Date

    let currentTokensPerHour: Int
    let peakTokensPerHour: Int
    let peakHourlyDate: Date?
    let weeklyPeakTokensPerHour: Int
    let weeklyPeakHourlyDate: Date?

    let fiveHourUsedPercent: Double?

    let todayTokens: Int
    let weekTokens: Int
    let monthTokens: Int

    let mostProductiveDayDate: Date?
    let mostProductiveDayTokens: Int
    let weeklyMostProductiveDayDate: Date?
    let weeklyMostProductiveDayTokens: Int
    let longestStreakDays: Int

    let weeklyBreakdown: [ShareWeekdayMetric]
}

struct ShareCardView: View {
    let snapshot: ShareCardSnapshot

    private let cardCornerRadius: CGFloat = 36

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 22) {
                header

                modeContent

                footer
            }
            .padding(.horizontal, 42)
            .padding(.top, 42)
            .padding(.bottom, 52)
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.10, blue: 0.17),
                    Color(red: 0.09, green: 0.13, blue: 0.21),
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(snapshot.mode.accent.opacity(0.28))
                .frame(width: 380, height: 380)
                .blur(radius: 46)
                .offset(x: 420, y: -210)

            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 260, height: 260)
                .blur(radius: 34)
                .offset(x: -430, y: 250)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.mode.title)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(snapshot.projectTitle)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            Text("Codex Usage")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.white.opacity(0.10), in: Capsule())
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch snapshot.mode {
        case .buildHighlights:
            buildHighlightsContent
        case .weeklyRecap:
            weeklyContent
        case .buildMode:
            buildModeContent
        }
    }

    private var buildHighlightsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroPanel(
                title: "Top Building Speed",
                value: speedLabel(snapshot.peakTokensPerHour),
                detail: snapshot.peakHourlyDate.map { "Recorded \($0.formatted(.dateTime.month(.abbreviated).day().hour().minute()))" }
            )

            HStack(spacing: 12) {
                tokenSummaryTile(title: "Today", tokens: snapshot.todayTokens)
                tokenSummaryTile(title: "Week", tokens: snapshot.weekTokens)
                tokenSummaryTile(title: "30 Days", tokens: snapshot.monthTokens)
            }

            HStack(spacing: 12) {
                milestoneTile(
                    title: "Most Productive Day",
                    value: mostProductiveDayPrimaryLabel(date: snapshot.mostProductiveDayDate),
                    detail: mostProductiveDaySecondaryLabel(tokens: snapshot.mostProductiveDayTokens)
                )
                streakTile(days: snapshot.longestStreakDays)
            }
        }
    }

    private var weeklyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroPanel(
                title: "Total Tokens This Week",
                value: tokenCountLabel(snapshot.weekTokens),
                detail: nil
            )

            HStack(spacing: 12) {
                infoTile(
                    title: "Top Building Speed (Week)",
                    value: speedLabel(snapshot.weeklyPeakTokensPerHour),
                    detail: snapshot.weeklyPeakHourlyDate.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
                )

                infoTile(
                    title: "Most Productive Day (Week)",
                    value: mostProductiveDayPrimaryLabel(date: snapshot.weeklyMostProductiveDayDate),
                    detail: mostProductiveDaySecondaryLabel(tokens: snapshot.weeklyMostProductiveDayTokens)
                )
            }

            weeklyHorizontalBars
        }
    }

    private var buildModeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroPanel(
                title: "Current Building Speed",
                value: speedLabel(snapshot.currentTokensPerHour),
                detail: "Live now"
            )

            HStack(spacing: 12) {
                infoTile(
                    title: "Today",
                    value: tokenCountLabel(snapshot.todayTokens),
                    detail: nil
                )

                infoTile(
                    title: "5-hour Window",
                    value: fiveHourWindowPrimaryLabel,
                    detail: nil
                )
            }
        }
    }

    private func heroPanel(title: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            Text(value)
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .monospacedDigit()

            if let detail {
                Text(detail)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(snapshot.mode.accent.opacity(0.20), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func tokenSummaryTile(title: String, tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            Text(tokenCountLabel(tokens))
                .font(.system(size: 33, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func infoTile(title: String, value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .monospacedDigit()

            if let detail {
                Text(detail)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func streakTile(days: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Longest Streak")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))

            Spacer(minLength: 0)

            Text("\(days) days")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .monospacedDigit()

            Text("lifetime")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func milestoneTile(title: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .monospacedDigit()

            if let detail {
                Text(detail)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var weeklyHorizontalBars: some View {
        let maxTokens = max(snapshot.weeklyBreakdown.map(\.tokens).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Week Activity")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            ForEach(snapshot.weeklyBreakdown) { day in
                HStack(spacing: 10) {
                    Text(day.label)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))
                        .frame(width: 36, alignment: .leading)

                    GeometryReader { proxy in
                        let ratio = Double(day.tokens) / Double(maxTokens)
                        let fillWidth = max(8, proxy.size.width * CGFloat(ratio))

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.12))

                            Capsule()
                                .fill(snapshot.mode.accent.opacity(0.90))
                                .frame(width: fillWidth)
                        }
                    }
                    .frame(height: 12)

                    Text(tokenCountLabel(day.tokens))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 108, alignment: .trailing)
                        .monospacedDigit()
                }
                .frame(height: 18)
            }
        }
        .padding(16)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var fiveHourWindowPrimaryLabel: String {
        guard let used = snapshot.fiveHourUsedPercent else {
            return "Unavailable"
        }
        return "\(DisplayValueFormatter.percent(used, fractionDigits: 0))% used"
    }

    private func tokenCountLabel(_ value: Int) -> String {
        "\(DisplayValueFormatter.compactCount(value)) tokens"
    }

    private func speedLabel(_ value: Int) -> String {
        "\(DisplayValueFormatter.compactCount(value)) tokens/hr"
    }

    private func mostProductiveDayPrimaryLabel(date: Date?) -> String {
        guard let date else {
            return "No data"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func mostProductiveDaySecondaryLabel(tokens: Int) -> String? {
        guard tokens > 0 else {
            return nil
        }
        return "\(DisplayValueFormatter.compactCount(tokens)) tokens"
    }

    private var footer: some View {
        Text("Updated \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.64))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
