import Foundation
import Sparkle

/// Sparkle-based updates from the GitHub Releases appcast.
/// Only active for Release `com.moveit.MoveIt` — Dev builds skip to avoid
/// replacing MoveIt Dev with the Release app.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    /// Retained for the app lifetime; Sparkle requires a strong reference.
    private var controller: SPUStandardUpdaterController?

    var canCheckForUpdates: Bool {
        isReleaseBundle && controller != nil
    }

    private var isReleaseBundle: Bool {
        Bundle.main.bundleIdentifier == "com.moveit.MoveIt"
    }

    func start() {
        guard isReleaseBundle else { return }
        guard controller == nil else { return }

        // startingUpdater: true begins periodic checks (see SUEnableAutomaticChecks).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }
}
