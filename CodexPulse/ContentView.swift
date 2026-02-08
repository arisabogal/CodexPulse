import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CodexPulse")
                .font(.headline)
            Text("This app runs from the menu bar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
