import Foundation

struct HeatmapDayCell: Identifiable, Hashable {
    var id: Date { date }

    let date: Date
    let usage: DailyUsage?
    let level: Int

    var totalTokens: Int { usage?.totalTokens ?? 0 }
}
