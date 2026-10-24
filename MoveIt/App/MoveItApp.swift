import SwiftUI

@main
struct MoveItApp: App {
    @StateObject private var engine = ActivityEngine()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIconOption.storageKey) private var menuBarIconRaw = MenuBarIconOption.moveit.rawValue

    private var menuBarIcon: MenuBarIconOption {
        MenuBarIconOption(rawValue: menuBarIconRaw) ?? .moveit
    }

    var body: some Scene {
        Window("MoveIt", id: "controls") {
            ControlWindowView(engine: engine)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView(engine: engine)
        } label: {
            // Template / SF Symbols: macOS tints for light/dark menu bar. Keep ~16pt like system glyphs.
            menuBarIcon.labelImage(size: 16)
                .opacity(engine.phase == .waitingForIdle ? 0.55 : 1.0)
                .accessibilityLabel(menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarAccessibilityLabel: String {
        switch engine.phase {
        case .stopped: return "MoveIt — Stopped"
        case .waitingForIdle: return "MoveIt — Waiting for idle"
        case .simulating: return "MoveIt — Simulating"
        }
    }
}
