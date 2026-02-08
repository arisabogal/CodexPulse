import SwiftUI

@main
struct CodexPulseApp: App {
    @StateObject private var viewModel = HeatmapViewModel()

    init() {
        SingleInstanceController.enforceSingleInstance()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.xaxis")
                Text(viewModel.menuBarFiveHourLeftLabel)
            }
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
