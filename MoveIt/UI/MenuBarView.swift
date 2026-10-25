import SwiftUI

struct MenuBarView: View {
    @ObservedObject var engine: ActivityEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlsView(engine: engine, compact: true)
                .frame(width: 340)

            Divider()

            Button("Open \(BuildIdentity.displayName) Window…") {
                AppAppearance.showInDock()
                openWindow(id: "controls")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}
