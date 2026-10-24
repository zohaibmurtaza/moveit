import SwiftUI
import AppKit

struct ControlWindowView: View {
    @ObservedObject var engine: ActivityEngine

    @State private var showWelcome = !AppAppearance.didCompleteWelcome

    var body: some View {
        Group {
            if showWelcome {
                WelcomeGuideView {
                    AppAppearance.didCompleteWelcome = true
                    showWelcome = false
                    AppAppearance.closeControlsWindows()
                    AppAppearance.menuBarOnly()
                }
            } else {
                ControlsView(engine: engine, compact: false)
                    .background(
                        WindowAccessor { window in
                            AppAppearance.tagControlsWindow(window)
                            // Height follows content; keep a sensible minimum width.
                            window.styleMask.remove(.resizable)
                            window.styleMask.insert(.titled)
                            window.minSize = NSSize(width: 680, height: 200)
                        }
                    )
            }
        }
    }
}
