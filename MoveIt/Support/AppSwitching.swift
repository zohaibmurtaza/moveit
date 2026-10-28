import AppKit
import ApplicationServices
import CoreGraphics

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

    static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.apple.Safari"
    ]

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
            // AX often omits fullscreen windows on other Spaces. Always merge with
            // CGWindowList (optionAll) so those titles show up in the picker.
            let merged = mergeTitles(
                axWindowTitles(bundleID: bundleID),
                cgWindowTitles(bundleID: bundleID)
            )
            return merged.map { AppWindowInfo(title: $0) }
        }
    }

    private static func mergeTitles(_ lists: [String]...) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for list in lists {
            for raw in list {
                let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, !seen.contains(title) else { continue }
                seen.insert(title)
                out.append(title)
            }
        }
        return out
    }

    /// Activate a selected target on the main thread (required for AX / activation).
    @discardableResult
    static func activate(_ target: SwitchAppTarget) -> String? {
        let label = onMain {
            activateOnMain(target)
        }
        // Yield on the caller (worker) thread — never sleep on main, or Stop deadlocks
        // against activity-stream main.sync calls.
        Thread.sleep(forTimeInterval: 0.12)
        return label
    }

    private static func activateOnMain(_ target: SwitchAppTarget) -> String? {
        let apps = preferredApps(forBundleID: target.bundleIdentifier)
        guard let app = apps.first else {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier)
            else { return nil }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
            return "Open \(target.displayName)"
        }

        // Unhide + activate first — this is what brings a fullscreen Space forward.
        if app.isHidden {
            app.unhide()
        }
        activateApp(app)

        if target.restrictsWindows {
            let wanted = Set(target.selectedWindowTitles)
            // Try every PID for this bundle (Chrome can have multiple processes).
            for candidate in apps {
                if let title = focusWindow(pid: candidate.processIdentifier, matching: wanted) {
                    activateApp(candidate)
                    return "Focus \(target.displayName) — \(title)"
                }
            }
            if let title = focusWindowViaAppleScript(bundleID: target.bundleIdentifier, matching: wanted) {
                activateApp(app)
                return "Focus \(target.displayName) — \(title)"
            }
            // Restricted title not found via AX/script — still activate the app
            // (fullscreen window may only appear after Space switch).
            return "Switch to \(target.displayName)"
        }

        // Raise a non-front window when possible; fullscreen apps often have no
        // raisable AX window — activation alone is enough to switch Spaces.
        for candidate in apps {
            if let title = focusRandomWindow(pid: candidate.processIdentifier, excludingFront: true) {
                activateApp(candidate)
                return "Window in \(target.displayName) — \(title)"
            }
        }

        // Last resort: reopen via Workspace (more reliable across Spaces / fullscreen).
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        }
        activateApp(app)
        return "Switch to \(target.displayName)"
    }

    /// Prefer regular (Dock) processes over helpers sharing a bundle id.
    private static func preferredApps(forBundleID bundleID: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .sorted { a, b in
                let aScore = a.activationPolicy == .regular ? 0 : 1
                let bScore = b.activationPolicy == .regular ? 0 : 1
                if aScore != bScore { return aScore < bScore }
                return a.processIdentifier < b.processIdentifier
            }
    }

    private static func activateApp(_ app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

        _ = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        if #available(macOS 14.0, *) {
            app.activate()
        }
    }

    /// True when a known browser is frontmost. `targets` is unused for the check —
    /// tab chords stay inside the current browser and don’t require it to be in the switch list.
    static func frontmostIsBrowser(in targets: [SwitchAppTarget] = []) -> Bool {
        onMain {
            _ = targets
            guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
            return browserBundleIDs.contains(front)
        }
    }

    static func frontmostBrowserName() -> String? {
        onMain {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  let bid = app.bundleIdentifier,
                  browserBundleIDs.contains(bid)
            else { return nil }
            return app.localizedName ?? "Browser"
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

    private static func axWindowTitles(bundleID: String) -> [String] {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !apps.isEmpty else { return [] }

        var titles: [String] = []
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            ) == .success,
            let windows = windowsRef as? [AXUIElement]
            else { continue }

            for window in windows {
                guard let title = windowTitle(window),
                      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                if !titles.contains(title) {
                    titles.append(title)
                }
            }
        }
        return titles
    }

    private static func cgWindowTitles(bundleID: String) -> [String] {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let pids = Set(apps.map(\.processIdentifier))
        guard !pids.isEmpty else { return [] }

        // optionAll includes windows on other Spaces / fullscreen desktops.
        guard let info = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]
        else { return [] }

        var titles: [String] = []
        for entry in info {
            let pidValue = entry[kCGWindowOwnerPID as String]
            let pid: pid_t?
            if let v = pidValue as? pid_t {
                pid = v
            } else if let v = pidValue as? Int {
                pid = pid_t(v)
            } else if let v = pidValue as? Int32 {
                pid = pid_t(v)
            } else {
                pid = nil
            }
            guard let pid, pids.contains(pid) else { continue }

            // Skip menus, overlays, tooltips (non-zero layer).
            let layer = (entry[kCGWindowLayer as String] as? Int)
                ?? (entry[kCGWindowLayer as String] as? Int32).map(Int.init)
                ?? 0
            guard layer == 0 else { continue }

            if let bounds = entry[kCGWindowBounds as String] as? [String: Any] {
                let width = cgNumber(bounds["Width"]) ?? 0
                let height = cgNumber(bounds["Height"]) ?? 0
                // Drop tiny helper surfaces; keep real windows (incl. fullscreen).
                if width < 120 || height < 120 { continue }
            }

            guard let title = entry[kCGWindowName as String] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            if !titles.contains(title) {
                titles.append(title)
            }
        }
        return titles
    }

    private static func cgNumber(_ value: Any?) -> CGFloat? {
        if let n = value as? CGFloat { return n }
        if let n = value as? Double { return CGFloat(n) }
        if let n = value as? Int { return CGFloat(n) }
        if let n = value as? NSNumber { return CGFloat(truncating: n) }
        return nil
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
        // AXRaise often fails for fullscreen windows; activation still helps.
        _ = raise(window)
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
            guard let title = windowTitle(window), titleMatches(title, in: titles) else { continue }
            matches.append((window, title))
        }
        guard let pick = matches.randomElement() else { return nil }
        _ = raise(pick.0)
        return pick.1
    }

    /// Exact match, or safe prefix when both sides are long enough (avoids "G" matching everything).
    private static func titleMatches(_ title: String, in wanted: Set<String>) -> Bool {
        if wanted.contains(title) { return true }
        for w in wanted where w.count >= 8 && title.count >= 8 {
            if title.hasPrefix(w) || w.hasPrefix(title) { return true }
        }
        return false
    }

    /// Scriptable apps (Chrome, Safari, etc.) can raise windows AX can't see across Spaces.
    private static func focusWindowViaAppleScript(bundleID: String, matching titles: Set<String>) -> String? {
        guard let title = titles.randomElement() else { return nil }
        let escaped = appleScriptEscape(title)

        let source: String
        if browserBundleIDs.contains(bundleID) {
            // Chrome / Safari expose windows by name across Spaces.
            source = """
            tell application id "\(bundleID)"
              activate
              try
                set index of window "\(escaped)" to 1
                return "\(escaped)"
              on error
                repeat with w in windows
                  set t to name of w as text
                  if t is "\(escaped)" or t starts with "\(escaped)" then
                    set index of w to 1
                    return t
                  end if
                end repeat
              end try
            end tell
            """
        } else {
            source = """
            tell application id "\(bundleID)" to activate
            tell application "System Events"
              tell (first process whose bundle identifier is "\(bundleID)")
                set frontmost to true
                try
                  perform action "AXRaise" of (first window whose title is "\(escaped)")
                  return "\(escaped)"
                end try
              end tell
            end tell
            """
        }

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        let returned = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (returned?.isEmpty == false) ? returned : title
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
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
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        var pid: pid_t = 0
        if AXUIElementGetPid(window, &pid) == .success, pid != 0 {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if let app = NSRunningApplication(processIdentifier: pid) {
                _ = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }
        }
        return raised
    }

    private static func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }
}
