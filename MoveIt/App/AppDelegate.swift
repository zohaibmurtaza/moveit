import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BuildIdentity.applyDisguiseIfNeeded()
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow,
                  AppAppearance.isControlsWindow(window) else { return }
            // Closing the control / welcome window → menu bar only (no Dock).
            DispatchQueue.main.async {
                let stillOpen = NSApp.windows.contains {
                    AppAppearance.isControlsWindow($0) && $0.isVisible && $0 !== window
                }
                if !stillOpen {
                    AppAppearance.menuBarOnly()
                }
            }
        }

        _ = Permissions.ensureAccessibility(prompt: false)
        LaunchAtLogin.enableByDefaultIfNeeded()
        Task { @MainActor in
            AppUpdater.shared.start()
        }

        if AppAppearance.didCompleteWelcome {
            // Returning users: menu bar only, no Dock / no floating window.
            AppAppearance.menuBarOnly()
            DispatchQueue.main.async {
                AppAppearance.closeControlsWindows()
            }
        } else {
            // First launch: show Dock + welcome window.
            AppAppearance.showInDock()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock icon click (when visible) reopens controls.
        AppAppearance.openControlsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Only the in-app Quit button should kill the process.
        // Dock → Quit / ⌘Q while the window is open just hides back to the menu bar.
        if AppAppearance.allowFullQuit {
            return .terminateNow
        }
        AppAppearance.dismissToMenuBar()
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
    }
}

