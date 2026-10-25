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

    /// Shown in UI, window title, Accessibility list (must match Info.plist / .app name).
    static var displayName: String {
        isDev ? "MoveIt Dev" : "MoveIt"
    }
}
