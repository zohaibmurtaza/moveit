import AppKit
import ApplicationServices

/// A user-chosen app (and optional window titles) that MoveIt may switch to.
struct SwitchAppTarget: Codable, Identifiable, Hashable {
    var bundleIdentifier: String
    var displayName: String
    /// Empty means any window of this app is fair game.
    var selectedWindowTitles: [String]

    var id: String { bundleIdentifier }

    var restrictsWindows: Bool { !selectedWindowTitles.isEmpty }
}

struct RunningAppInfo: Identifiable, Hashable {
    var bundleIdentifier: String
    var displayName: String
    var icon: NSImage?

    var id: String { bundleIdentifier }
}

struct AppWindowInfo: Identifiable, Hashable {
    var title: String
    var id: String { title }
}

/// Lists apps/windows and activates only user-selected targets (no global ⌘Tab).
enum AppSwitching {
    private static var ourBundleIDs: Set<String> {
        var ids: Set<String> = ["com.moveit.MoveIt", "com.moveit.MoveIt.dev"]
        if let id = Bundle.main.bundleIdentifier {
            ids.insert(id)
        }
        return ids
    }

    static func runningApps() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular,
                      let bid = app.bundleIdentifier,
                      !ourBundleIDs.contains(bid),
                      app.localizedName != nil
                else { return false }
                return true
            }
            .map { app in
                RunningAppInfo(
                    bundleIdentifier: app.bundleIdentifier ?? "",
                    displayName: app.localizedName ?? app.bundleIdentifier ?? "App",
                    icon: app.icon
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func openWindows(forBundleID bundleID: String) -> [AppWindowInfo] {
        onMain {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            else { return [] }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            ) == .success,
            let windows = windowsRef as? [AXUIElement]
            else { return [] }

            var titles: [String] = []
            for window in windows {
                var titleRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    window,
                    kAXTitleAttribute as CFString,
                    &titleRef
                ) == .success,
                let title = titleRef as? String,
                !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                if !titles.contains(title) {
                    titles.append(title)
                }
            }
            return titles.map { AppWindowInfo(title: $0) }
        }
    }

    /// Activate a selected target on the main thread (required for AX / activation).
    @discardableResult
    static func activate(_ target: SwitchAppTarget) -> String? {
        onMain {
            activateOnMain(target)
        }
    }

    private static func activateOnMain(_ target: SwitchAppTarget) -> String? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier)
        guard let app = apps.first else {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier)
            else { return nil }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
            return "Open \(target.displayName)"
        }

        // Activate the app first — window raise alone often does nothing if app isn't frontmost.
        activateApp(app)

        if target.restrictsWindows {
            let wanted = Set(target.selectedWindowTitles)
            if let title = focusWindow(pid: app.processIdentifier, matching: wanted) {
                activateApp(app)
                return "Focus \(target.displayName) — \(title)"
            }
            // Fall through to any-window / activate if titled window wasn't found.
        }

        if let title = focusRandomWindow(pid: app.processIdentifier, excludingFront: true) {
            activateApp(app)
            return "Window in \(target.displayName) — \(title)"
        }

        activateApp(app)
        return "Switch to \(target.displayName)"
    }

    private static func activateApp(_ app: NSRunningApplication) {
        // Menu-bar / accessory apps often get a no-op from bare activate().
        // AX frontmost + ignoringOtherApps is what actually steals focus.
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

        // Prefer the classic option — still available and more reliable for
        // background agents than the macOS 14 parameterless activate().
        _ = app.activate(options: [.activateIgnoringOtherApps])
        if #available(macOS 14.0, *) {
            // Second pass for newer WindowServer paths.
            app.activate()
        }

        // Yield so WindowServer applies activation before AX window raise.
        Thread.sleep(forTimeInterval: 0.08)
    }

    /// If frontmost app is an allow-listed browser, return true so caller can ⌃Tab.
    static func frontmostIsBrowser(in targets: [SwitchAppTarget]) -> Bool {
        onMain {
            guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
            let browserIDs: Set<String> = [
                "com.google.Chrome",
                "com.google.Chrome.beta",
                "com.google.Chrome.canary",
                "company.thebrowser.Browser",
                "com.brave.Browser",
                "com.microsoft.edgemac",
                "org.mozilla.firefox",
                "com.apple.Safari"
            ]
            return targets.contains { $0.bundleIdentifier == front } && browserIDs.contains(front)
        }
    }

    static func loadTargets() -> [SwitchAppTarget] {
        guard let data = UserDefaults.standard.data(forKey: Keys.targets),
              let decoded = try? JSONDecoder().decode([SwitchAppTarget].self, from: data)
        else { return [] }
        return decoded
    }

    static func saveTargets(_ targets: [SwitchAppTarget]) {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: Keys.targets)
        }
    }

    private enum Keys {
        static let targets = "moveit.switchTargets"
    }

    private static func focusRandomWindow(pid: pid_t, excludingFront: Bool) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success,
        let windows = windowsRef as? [AXUIElement],
        !windows.isEmpty
        else { return nil }

        var candidates = windows
        if excludingFront, windows.count > 1 {
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &focusedRef
            ) == .success,
            let focused = focusedRef {
                candidates = windows.filter { !CFEqual($0, focused) }
                if candidates.isEmpty { candidates = windows }
            }
        }

        guard let window = candidates.randomElement() else { return nil }
        let title = windowTitle(window) ?? "Window"
        guard raise(window) else { return nil }
        return title
    }

    private static func focusWindow(pid: pid_t, matching titles: Set<String>) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success,
        let windows = windowsRef as? [AXUIElement]
        else { return nil }

        var matches: [(AXUIElement, String)] = []
        for window in windows {
            guard let title = windowTitle(window), titles.contains(title) else { continue }
            matches.append((window, title))
        }
        guard let pick = matches.randomElement() else { return nil }
        guard raise(pick.0) else { return nil }
        return pick.1
    }

    private static func windowTitle(_ window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &titleRef
        ) == .success else { return nil }
        return titleRef as? String
    }

    @discardableResult
    private static func raise(_ window: AXUIElement) -> Bool {
        // Prefer standard raise action; then force main/focused.
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        // Also ask the window's owning app to come forward when we only have the window ref.
        var pid: pid_t = 0
        if AXUIElementGetPid(window, &pid) == .success, pid != 0 {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if let app = NSRunningApplication(processIdentifier: pid) {
                _ = app.activate(options: [.activateIgnoringOtherApps])
            }
        }
        return raised
    }

    private static func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }
}
