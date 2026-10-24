import Foundation
import ServiceManagement

enum LaunchAtLogin {
    private static let configuredKey = "moveit.launchAtLoginConfigured"

    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            guard #available(macOS 13.0, *) else { return }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                UserDefaults.standard.set(true, forKey: configuredKey)
            } catch {
                NSLog("LaunchAtLogin error: \(error.localizedDescription)")
            }
        }
    }

    /// First run: turn on Open at Login by default (user can still disable later).
    static func enableByDefaultIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        isEnabled = true
    }
}
