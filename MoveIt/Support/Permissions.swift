import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

enum Permissions {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Screen Recording — needed so CGWindowList returns window titles (incl. fullscreen / other Spaces).
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

    /// True when Screen Recording was just granted but this process still can’t read titles.
    static var screenRecordingNeedsRelaunch: Bool {
        hasScreenRecording && !screenRecordingAtLaunch
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

    /// Triggers the Screen Recording TCC prompt (macOS 11+). May require relaunch after grant.
    @discardableResult
    static func ensureScreenRecording(prompt: Bool = true) -> Bool {
        if hasScreenRecording { return true }
        guard prompt else { return false }
        if #available(macOS 11.0, *) {
            return CGRequestScreenCaptureAccess()
        }
        return true
    }

    static func openAccessibilitySettings() {
        openPrivacySettings(paths: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Accessibility"
        ])
    }

    static func openScreenRecordingSettings() {
        openPrivacySettings(paths: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ])
    }

    /// Quit and relaunch so a freshly granted Screen Recording permission takes effect.
    static func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
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
