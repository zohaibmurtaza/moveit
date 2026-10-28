import Foundation

/// Distinguishes Debug vs Release without touching Release bundle ID / prefs.
enum BuildIdentity {
    static var isDev: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static let disguiseKey = "moveit.disguiseName"

    /// The real app name before any disguise.
    static var realName: String {
        isDev ? "MoveIt Dev" : "MoveIt"
    }

    /// Shown in UI, window title, Accessibility list. Returns disguise name if set.
    static var displayName: String {
        if let custom = UserDefaults.standard.string(forKey: disguiseKey),
           !custom.isEmpty {
            return custom
        }
        return realName
    }

    /// Whether the app is currently using a disguised process name.
    static var isDisguised: Bool {
        guard let custom = UserDefaults.standard.string(forKey: disguiseKey) else { return false }
        return !custom.isEmpty
    }

    /// The currently stored disguise name, or nil if not set.
    static var disguiseName: String? {
        get {
            let val = UserDefaults.standard.string(forKey: disguiseKey)
            return (val?.isEmpty ?? true) ? nil : val
        }
        set {
            if let name = newValue, !name.isEmpty {
                UserDefaults.standard.set(name, forKey: disguiseKey)
                ProcessInfo.processInfo.processName = name
            } else {
                UserDefaults.standard.removeObject(forKey: disguiseKey)
                ProcessInfo.processInfo.processName = realName
            }
        }
    }

    /// Apply disguise on launch if previously set.
    static func applyDisguiseIfNeeded() {
        if let custom = UserDefaults.standard.string(forKey: disguiseKey),
           !custom.isEmpty {
            ProcessInfo.processInfo.processName = custom
        }
    }
}
