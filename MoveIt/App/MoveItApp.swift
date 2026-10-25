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
        Window(BuildIdentity.displayName, id: "controls") {
            ControlWindowView(engine: engine)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView(engine: engine)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: some View {
        // macOS template status items don't reliably honor fade/opacity — keep solid.
        ZStack(alignment: .bottomTrailing) {
            menuBarIcon.labelImage(size: 16)

            if BuildIdentity.isDev {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 4, height: 4)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(menuBarAccessibilityLabel)
    }

    private var menuBarAccessibilityLabel: String {
        let name = BuildIdentity.displayName
        switch engine.phase {
        case .stopped: return "\(name) — Stopped"
        case .waitingForIdle: return "\(name) — Waiting for idle"
        case .simulating: return "\(name) — Simulating"
        }
    }
}
