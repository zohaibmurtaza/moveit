import SwiftUI
import AppKit

struct AppSwitchPickerView: View {
    @Binding var targets: [SwitchAppTarget]

    @State private var running: [RunningAppInfo] = []
    @State private var expandedBundleID: String?
    @State private var windowsByBundle: [String: [AppWindowInfo]] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Only switch among apps (and windows) you select below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Refresh") { reload() }
                    .controlSize(.small)
            }

            if running.isEmpty {
                Text("No regular apps are running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(running) { app in
                        appRow(app)
                        if expandedBundleID == app.bundleIdentifier {
                            windowPicker(for: app.bundleIdentifier)
                        }
                        Divider()
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            if !targets.isEmpty {
                Text("Selected: \(targets.map(\.displayName).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: reload)
    }

    private func appRow(_ app: RunningAppInfo) -> some View {
        let selected = targets.contains { $0.bundleIdentifier == app.bundleIdentifier }
        return HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { selected },
                set: { on in toggleApp(app, on: on) }
            )) {
                HStack(spacing: 8) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text(app.displayName)
                        .lineLimit(1)
                }
            }
            .toggleStyle(.checkbox)

            Spacer()

            if selected {
                Button(expandedBundleID == app.bundleIdentifier ? "Hide windows" : "Windows") {
                    if expandedBundleID == app.bundleIdentifier {
                        expandedBundleID = nil
                    } else {
                        ensureScreenRecordingForWindows()
                        expandedBundleID = app.bundleIdentifier
                        loadWindows(for: app.bundleIdentifier)
                    }
                }
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func windowPicker(for bundleID: String) -> some View {
        let windows = windowsByBundle[bundleID] ?? []
        let targetIndex = targets.firstIndex { $0.bundleIdentifier == bundleID }
        let needsRelaunch = Permissions.screenRecordingNeedsRelaunch
        return VStack(alignment: .leading, spacing: 4) {
            if needsRelaunch {
                screenRecordingBanner(
                    text: "Screen Recording is on — relaunch \(BuildIdentity.displayName) to list fullscreen windows.",
                    primary: "Relaunch Now",
                    action: Permissions.relaunchApp
                )
            } else if !Permissions.hasScreenRecording {
                screenRecordingBanner(
                    text: "Screen Recording is required to list fullscreen windows on other Spaces.",
                    primary: "Request Permission",
                    action: {
                        ensureScreenRecordingForWindows()
                        loadWindows(for: bundleID)
                    }
                )
            } else {
                Text(windows.isEmpty
                     ? "No titled windows found for this app."
                     : "Limit to these windows (none checked = any window):")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }

            // Always list what we have (AX and/or CG). Banner above explains
            // missing fullscreen titles when Screen Recording is off.
            ForEach(windows) { window in
                let checked = targetIndex.flatMap { idx in
                    targets[idx].selectedWindowTitles.contains(window.title)
                } ?? false
                Toggle(isOn: Binding(
                    get: { checked },
                    set: { on in toggleWindow(bundleID: bundleID, title: window.title, on: on) }
                )) {
                    Text(window.title)
                        .font(.caption)
                        .lineLimit(1)
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 28)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 8)
    }

    private func screenRecordingBanner(text: String, primary: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(primary, action: action)
                    .controlSize(.mini)
                Button("Open Settings") {
                    Permissions.openScreenRecordingSettings()
                }
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 4)
    }

    private func ensureScreenRecordingForWindows() {
        guard !Permissions.hasScreenRecording else { return }
        _ = Permissions.ensureScreenRecording(prompt: true)
    }

    private func reload() {
        running = AppSwitching.runningApps()
        // Drop targets for apps that disappeared? Keep them so user can re-launch later.
        if let expanded = expandedBundleID {
            loadWindows(for: expanded)
        }
    }

    private func loadWindows(for bundleID: String) {
        windowsByBundle[bundleID] = AppSwitching.openWindows(forBundleID: bundleID)
    }

    private func toggleApp(_ app: RunningAppInfo, on: Bool) {
        if on {
            if !targets.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                targets.append(
                    SwitchAppTarget(
                        bundleIdentifier: app.bundleIdentifier,
                        displayName: app.displayName,
                        selectedWindowTitles: []
                    )
                )
            }
        } else {
            targets.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
            if expandedBundleID == app.bundleIdentifier {
                expandedBundleID = nil
            }
        }
    }

    private func toggleWindow(bundleID: String, title: String, on: Bool) {
        guard let idx = targets.firstIndex(where: { $0.bundleIdentifier == bundleID }) else { return }
        var titles = targets[idx].selectedWindowTitles
        if on {
            if !titles.contains(title) { titles.append(title) }
        } else {
            titles.removeAll { $0 == title }
        }
        targets[idx].selectedWindowTitles = titles
    }
}
