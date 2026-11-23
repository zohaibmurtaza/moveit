import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

enum Permissions {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Screen Recording — needed so CGWindowList returns window titles (incl. fullscreen / other Spaces).
    ///
    /// Important: `CGPreflightScreenCaptureAccess()` caches its answer for the **process lifetime**.
    /// Once it returns `false`, it keeps returning `false` even after the user enables the toggle
    /// in System Settings. A relaunch is required for the new grant to be visible to this API
    /// (and for `CGWindowList` titles to populate).
    static var hasScreenRecording: Bool {
        if #available(macOS 11.0, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    /// Cached at first read so we can detect “granted this session → needs relaunch”.
    private static let screenRecordingAtLaunch: Bool = {
        if #available(macOS 11.0, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }()

    private static let relaunchPendingKey = "moveit.screenRecording.relaunchPending"

    /// Set when the user requests Screen Recording or opens its Settings while this process
    /// still sees a sticky-false preflight. Cleared on a launch where preflight is true,
    /// or after a relaunch that still reads false (stale Settings toggle / settle failed).
    private static var relaunchPending: Bool {
        get { UserDefaults.standard.bool(forKey: relaunchPendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: relaunchPendingKey) }
    }

    private static let bootstrapScreenRecordingState: Void = {
        guard #available(macOS 11.0, *) else { return }
        if CGPreflightScreenCaptureAccess() {
            UserDefaults.standard.set(false, forKey: relaunchPendingKey)
            return
        }
        // Relaunch already happened with pending set, but preflight is still false.
        // That is almost always a signature mismatch (old Settings toggle ≠ this binary),
        // not something another relaunch will fix — drop pending so UI asks to re-grant.
        if UserDefaults.standard.bool(forKey: relaunchPendingKey) {
            UserDefaults.standard.set(false, forKey: relaunchPendingKey)
        }
    }()

    /// True when Screen Recording was granted this session but this process still can’t use it.
    static var screenRecordingNeedsRelaunch: Bool {
        _ = bootstrapScreenRecordingState
        // Preflight flipped true mid-session (rare; some OS versions).
        if hasScreenRecording && !screenRecordingAtLaunch {
            return true
        }
        // In-session only: user just requested / opened Settings while preflight is sticky-false.
        if !hasScreenRecording && relaunchPending {
            return true
        }
        return false
    }

    /// Ready to list fullscreen / other-Space window titles in this process.
    static var canReadWindowTitles: Bool {
        hasScreenRecording && !screenRecordingNeedsRelaunch
    }

    /// Prompts the system dialog once when `prompt` is true.
    @discardableResult
    static func ensureAccessibility(prompt: Bool = true) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return false
    }

    /// Triggers the Screen Recording TCC prompt (macOS 11+). Always requires relaunch after grant
    /// for titles to work in this process (preflight does not update live).
    @discardableResult
    static func ensureScreenRecording(prompt: Bool = true) -> Bool {
        if canReadWindowTitles { return true }
        guard prompt else { return false }
        if #available(macOS 11.0, *) {
            let granted = CGRequestScreenCaptureAccess()
            // Whether the dialog appeared or TCC already had the app enabled, this process
            // still needs a relaunch before CGWindowList returns titles.
            markScreenRecordingRelaunchPending()
            return granted || hasScreenRecording
        }
        return true
    }

    /// Call after the user opens Screen Recording settings or confirms they enabled the toggle.
    static func markScreenRecordingRelaunchPending() {
        guard !canReadWindowTitles else { return }
        relaunchPending = true
    }

    static func openAccessibilitySettings() {
        openPrivacySettings(paths: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Accessibility"
        ])
    }

    static func openScreenRecordingSettings() {
        markScreenRecordingRelaunchPending()
        openPrivacySettings(paths: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ])
    }

    /// Quit and relaunch so a freshly granted Screen Recording permission takes effect.
    ///
    /// Must **hard-exit** the process. `NSApp.terminate` is intercepted by
    /// `applicationShouldTerminate` to keep the menu-bar app alive (Dock Quit → hide),
    /// which would leave this process running with a sticky-false Screen Recording preflight.
    static func relaunchApp() {
        relaunchPending = true
        AppAppearance.allowFullQuit = true

        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                NSLog("MoveIt relaunch open failed: \(error.localizedDescription)")
            }
            // Bypass AppKit terminate cancellation — kill this process for real.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                exit(EXIT_SUCCESS)
            }
        }
    }

    /// When false, system “Quit & Reopen” (Screen Recording) must be allowed to kill the process.
    static var allowsMenuBarQuitCancel: Bool {
        canReadWindowTitles
    }

    private static func openPrivacySettings(paths: [String]) {
        for string in paths {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
}
