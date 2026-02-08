import SwiftUI

struct HeatmapLegendView: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color(for: level))
                    .frame(width: 10, height: 10)
            }

            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for level: Int) -> Color {
        switch level {
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
}
