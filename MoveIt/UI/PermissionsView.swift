import SwiftUI

struct PermissionsView: View {
    @Binding var isTrusted: Bool

    @State private var hasScreenRecording = Permissions.hasScreenRecording
    @State private var needsRelaunch = Permissions.screenRecordingNeedsRelaunch
    @State private var accessibilityAttempts = 0
    @State private var screenAttempts = 0
    @State private var pollTimer: Timer?

    private var accessibilityOK: Bool { isTrusted }
    private var screenOK: Bool { hasScreenRecording && !needsRelaunch }
    private var allOK: Bool { accessibilityOK && screenOK }

    var body: some View {
        Group {
            if !allOK {
                VStack(alignment: .leading, spacing: 14) {
                    if !accessibilityOK {
                        permissionBlock(
                            icon: "exclamationmark.shield.fill",
                            title: "Accessibility required",
                            detail: "Grant Accessibility so \(BuildIdentity.displayName) can inject test input. Enable it in System Settings — status updates automatically."
                        ) {
                            Button("Request Permission", action: requestAccessibility)
                                .controlSize(.small)
                            if accessibilityAttempts >= 2 {
                                Button("Open Settings", action: Permissions.openAccessibilitySettings)
                                    .controlSize(.small)
                            }
                        }
                    }

                    if !screenOK {
                        permissionBlock(
                            icon: "rectangle.dashed.badge.record",
                            title: needsRelaunch ? "Relaunch to finish Screen Recording" : "Screen Recording required",
                            detail: needsRelaunch
                                ? "Permission is on, but macOS only applies it after a restart. Relaunch to list fullscreen windows on other Spaces."
                                : "Needed to list window titles — including fullscreen windows on other Spaces. \(BuildIdentity.displayName) does not capture or save your screen."
                        ) {
                            if needsRelaunch {
                                Button("Relaunch Now", action: Permissions.relaunchApp)
                                    .controlSize(.small)
                            } else {
                                Button("Request Permission", action: requestScreenRecording)
                                    .controlSize(.small)
                                if screenAttempts >= 2 {
                                    Button("Open Settings", action: Permissions.openScreenRecordingSettings)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            refresh()
            if !allOK {
                startPolling()
            }
        }
        .onDisappear {
            stopPolling()
        }
        .onChange(of: isTrusted) { _ in updatePolling() }
        .onChange(of: hasScreenRecording) { _ in updatePolling() }
        .onChange(of: needsRelaunch) { _ in updatePolling() }
    }

    private func permissionBlock<Actions: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.callout.weight(.semibold))
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                actions()
            }
        }
    }

    private func requestAccessibility() {
        accessibilityAttempts += 1
        if accessibilityAttempts == 1 {
            _ = Permissions.ensureAccessibility(prompt: true)
        } else {
            Permissions.openAccessibilitySettings()
        }
        refresh()
        startPolling()
    }

    private func requestScreenRecording() {
        screenAttempts += 1
        if screenAttempts == 1 {
            _ = Permissions.ensureScreenRecording(prompt: true)
        } else {
            Permissions.openScreenRecordingSettings()
        }
        refresh()
        startPolling()
    }

    private func refresh() {
        isTrusted = Permissions.hasAccessibility
        hasScreenRecording = Permissions.hasScreenRecording
        needsRelaunch = Permissions.screenRecordingNeedsRelaunch
        updatePolling()
    }

    private func updatePolling() {
        if allOK {
            stopPolling()
        } else {
            startPolling()
        }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            let ax = Permissions.hasAccessibility
            let screen = Permissions.hasScreenRecording
            let relaunch = Permissions.screenRecordingNeedsRelaunch
            DispatchQueue.main.async {
                if ax != isTrusted { isTrusted = ax }
                if screen != hasScreenRecording { hasScreenRecording = screen }
                if relaunch != needsRelaunch { needsRelaunch = relaunch }
                if ax && screen && !relaunch {
                    stopPolling()
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
