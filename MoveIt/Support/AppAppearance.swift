import AppKit
import Foundation

enum AppAppearance {
    static let didCompleteWelcomeKey = "moveit.didCompleteWelcome"
    static let controlsWindowID = "moveit.controls"

    /// Set only when the user explicitly presses Quit in MoveIt’s UI.
    /// Dock → Quit / ⌘Q otherwise just returns to the menu bar.
    static var allowFullQuit = false

    static var didCompleteWelcome: Bool {
        get { UserDefaults.standard.bool(forKey: didCompleteWelcomeKey) }
        set { UserDefaults.standard.set(newValue, forKey: didCompleteWelcomeKey) }
    }

    /// Show Dock icon (needed while the control / welcome window is open).
    static func showInDock() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hide Dock icon; keep running via the menu bar only.
    static func menuBarOnly() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Fully exit the process (menu bar Quit button).
    static func quitCompletely() {
        allowFullQuit = true
        NSApp.terminate(nil)
    }

    /// Close windows and leave only the menu bar item (used instead of Dock Quit).
    static func dismissToMenuBar() {
        closeControlsWindows()
        menuBarOnly()
    }

    static func tagControlsWindow(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(controlsWindowID)
        window.title = BuildIdentity.displayName
        window.representedURL = nil
        // Avoid restoring a previously stretched frame from an earlier layout.
        window.setFrameAutosaveName("")
        // Do not clear/override the window background — on macOS 26+ the system
        // supplies Liquid Glass. Custom clear/VFX layers kill that and look solid.
    }

    static func isControlsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == controlsWindowID
            || window.title == "MoveIt"
            || window.title == "MoveIt Dev"
            || window.title == "MoveIt (Dev)"
            || window.title == BuildIdentity.displayName
    }

    static func closeControlsWindows() {
        for window in NSApp.windows where isControlsWindow(window) {
            window.close()
        }
    }

    static func openControlsWindow() {
        showInDock()
        // Prefer the existing SwiftUI window if present; otherwise order any titled MoveIt window.
        if let existing = NSApp.windows.first(where: { isControlsWindow($0) }) {
            existing.makeKeyAndOrderFront(nil)
        } else if let fallback = NSApp.windows
            .filter({ $0.isVisible || $0.isMiniaturized })
            .first(where: { !$0.className.contains("StatusBar") })
        {
            fallback.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
