import SwiftUI

struct ActivityHeatmapView: View {
    let weeks: [[HeatmapDayCell]]
    let onSelect: (Date) -> Void

    private let calendar = Calendar.autoupdatingCurrent
    private static let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 4
    private let weekSpacing: CGFloat = 4
    private let monthHeaderHeight: CGFloat = 14
    @State private var hoveredCell: HeatmapDayCell?

    var body: some View {
        let today = calendar.startOfDay(for: Date())

        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .trailing, spacing: cellSpacing) {
                        Color.clear
                            .frame(height: monthHeaderHeight)

                        ForEach(Self.dayLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(height: cellSize)
                        }
                    }

                    heatmapColumns(today: today)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            hoverPreview
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heatmapColumns(today: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: weekSpacing) {
                ForEach(Array(monthLabels.enumerated()), id: \.offset) { _, label in
                    ZStack(alignment: .leading) {
                        Color.clear
                            .frame(width: cellSize, height: monthHeaderHeight)

                        if !label.isEmpty {
                            Text(label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: weekSpacing) {
                ForEach(weeks, id: \.first?.date) { week in
                    VStack(spacing: cellSpacing) {
                        ForEach(week) { cell in
                            Button {
                                onSelect(cell.date)
                            } label: {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(fillColor(for: cell, today: today))
                                    .frame(width: cellSize, height: cellSize)
                            }
                            .buttonStyle(.plain)
                            .help(tooltip(for: cell))
                            .onHover { isHovering in
                                hoveredCell = isHovering ? cell : (hoveredCell?.id == cell.id ? nil : hoveredCell)
                            }
                        }
                    }
                    .frame(width: cellSize)
                }
            }
        }
        .padding(.bottom, 2)
    }

    private var hoverPreview: some View {
        Group {
            if let hoveredCell {
                HStack(spacing: 8) {
                    Text(hoveredCell.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.semibold))

                    if let usage = hoveredCell.usage {
                        Text("\(DisplayValueFormatter.compactCount(usage.totalTokens)) tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("\(DisplayValueFormatter.compactCount(usage.sessionCount)) sessions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("$\(DisplayValueFormatter.currency(usage.estimatedCostUSD))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("No usage")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: hoveredCell?.id)
    }

    private var monthLabels: [String] {
        weeks.enumerated().map { index, week in
            guard let firstDate = week.first?.date else {
                return ""
            }

            if index == 0 {
                return shortMonth(for: firstDate)
            }

            guard let previousDate = weeks[index - 1].first?.date else {
                return shortMonth(for: firstDate)
            }

            let currentMonth = calendar.component(.month, from: firstDate)
            let previousMonth = calendar.component(.month, from: previousDate)
            return currentMonth == previousMonth ? "" : shortMonth(for: firstDate)
        }
    }

    private func shortMonth(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated))
    }

    private func fillColor(for cell: HeatmapDayCell, today: Date) -> Color {
        if cell.date > today {
            return Color.secondary.opacity(0.08)
        }

        switch cell.level {
        case 0:
            return Color.secondary.opacity(0.18)
        case 1:
            return Color(red: 0.79, green: 0.92, blue: 0.78)
        case 2:
            return Color(red: 0.53, green: 0.81, blue: 0.52)
        case 3:
            return Color(red: 0.28, green: 0.67, blue: 0.29)
        default:
            return Color(red: 0.11, green: 0.50, blue: 0.12)
        }
    }

    private func tooltip(for cell: HeatmapDayCell) -> String {
        let dateLabel = cell.date.formatted(date: .abbreviated, time: .omitted)
        return "\(dateLabel): \(DisplayValueFormatter.compactCount(cell.totalTokens)) tokens"
    }
}
