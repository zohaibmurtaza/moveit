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
                            window.styleMask.remove(.resizable)
                            window.styleMask.insert(.titled)
                            // Match ControlsView.windowWidth / windowHeight — stable across tabs.
                            let target = NSSize(
                                width: ControlsView.windowWidth,
                                height: ControlsView.windowHeight
                            )
                            window.minSize = target
                            if abs(window.frame.width - target.width) > 1
                                || abs(window.frame.height - target.height) > 1
                            {
                                window.setContentSize(target)
                            }
                        }
                    )
            }
        }
    }
}
