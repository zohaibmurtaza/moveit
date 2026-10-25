import SwiftUI
import AppKit

private enum ControlsWindowPane: String, CaseIterable, Identifiable, Hashable {
    case activity
    case keyboard
    case switching
    case appearance
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "Activity"
        case .keyboard: return "Keyboard"
        case .switching: return "Switching"
        case .appearance: return "Appearance"
        case .status: return "Status"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: return "play.circle"
        case .keyboard: return "keyboard"
        case .switching: return "arrow.left.arrow.right"
        case .appearance: return "menubar.rectangle"
        case .status: return "waveform.path.ecg"
        }
    }

    /// Settings-style sidebar groups.
    static let simulationPanes: [ControlsWindowPane] = [.activity, .keyboard, .switching]
    static let appPanes: [ControlsWindowPane] = [.appearance, .status]
}

/// Shared controls used by the main window and the menu bar panel.
struct ControlsView: View {
    @ObservedObject var engine: ActivityEngine
    var compact: Bool = false

    @State private var accessibilityTrusted = Permissions.hasAccessibility
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var windowPane: ControlsWindowPane = .activity
    @AppStorage(MenuBarIconOption.storageKey) private var menuBarIconRaw = MenuBarIconOption.moveit.rawValue

    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                windowBody
            }
        }
        .onAppear {
            refreshPermissions()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    // MARK: - Menu bar dropdown (essentials only)

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: true)
                .padding(.bottom, 12)

            if !accessibilityTrusted {
                Divider()
                PermissionsView(isTrusted: $accessibilityTrusted)
                    .padding(.vertical, 12)
            }

            Divider()

            idleWaitSlider
                .padding(.vertical, 14)

            Divider()

            profilePicker
                .padding(.vertical, 14)

            Divider()

            intensitySlider
                .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Switch apps & windows", isOn: $engine.allowAppNavigation)
                if engine.allowAppNavigation && engine.switchTargets.isEmpty {
                    Text("Pick apps in the Switching tab of the main window.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 14)

            if engine.isRunning {
                Divider()
                statusBlock
                    .padding(.vertical, 12)
            }

            Divider()

            compactActionRow
                .padding(.top, 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Main window

    private static let windowWidth: CGFloat = 720
    private static let windowHeight: CGFloat = 580

    private var windowBody: some View {
        NavigationSplitView {
            List(selection: $windowPane) {
                Section("Simulation") {
                    ForEach(ControlsWindowPane.simulationPanes) { pane in
                        Label(pane.title, systemImage: pane.systemImage)
                            .tag(pane)
                    }
                }
                Section("App") {
                    ForEach(ControlsWindowPane.appPanes) { pane in
                        Label(pane.title, systemImage: pane.systemImage)
                            .tag(pane)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    windowPaneContent
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Divider()

                windowActionRow
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .navigationTitle(windowPane.title)
            #if os(macOS)
            .navigationSubtitle(detailSubtitle)
            #endif
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: Self.windowWidth, height: Self.windowHeight)
    }

    private var detailSubtitle: String {
        switch windowPane {
        case .activity:
            return "Arms after idle, then simulates human-like activity."
        case .keyboard:
            return "Silent keys by default; characters are optional."
        case .switching:
            return "Only switch among apps and windows you select."
        case .appearance:
            return "Menu bar icon for this Mac."
        case .status:
            return "Live stream of past, current, and upcoming actions."
        }
    }

    @ViewBuilder
    private var windowPaneContent: some View {
        switch windowPane {
        case .activity:
            activityPane
        case .keyboard:
            VStack(alignment: .leading, spacing: 16) {
                keyboardSettings
            }
        case .switching:
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Switch among selected apps", isOn: $engine.allowAppNavigation)
                Text(
                    engine.switchTargets.isEmpty
                        ? "Select at least two apps below. MoveIt will only switch among those — never the whole Dock via ⌘Tab."
                        : "Activates your selected apps/windows. Browser tab chords (⌃Tab) only while one of those browsers is frontmost."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if engine.allowAppNavigation {
                    switchIntervalSliders
                }

                Divider()

                AppSwitchPickerView(targets: $engine.switchTargets)
                    .disabled(!engine.allowAppNavigation)
                    .opacity(engine.allowAppNavigation ? 1 : 0.45)
            }
        case .appearance:
            VStack(alignment: .leading, spacing: 18) {
                settingsCard(
                    title: "Updates",
                    footer: AppUpdater.shared.canCheckForUpdates
                        ? "Checks GitHub Releases daily and installs updates automatically when available."
                        : "Automatic updates apply to Release builds of MoveIt (not MoveIt Dev)."
                ) {
                    if AppUpdater.shared.canCheckForUpdates {
                        Button("Check for Updates…") {
                            AppUpdater.shared.checkForUpdates()
                        }
                    } else {
                        Text("You’re running \(BuildIdentity.displayName). Install the Release build from GitHub to receive updates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsCard(
                    title: "Menu bar icon",
                    footer: "Your choice is saved on this Mac."
                ) {
                    menuBarIconPicker
                }
            }
        case .status:
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Live activity")
                ActivityStreamView(
                    past: engine.pastEvents,
                    current: engine.currentEvent,
                    upcoming: engine.upcomingEvents
                )

                Divider()

                sectionTitle("Details")
                statusBlock
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    /// Activity tab: grouped cards so style / busy / idle / login don’t run together.
    private var activityPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !accessibilityTrusted {
                settingsCard(title: "Permissions") {
                    PermissionsView(isTrusted: $accessibilityTrusted)
                }
            }

            settingsCard(
                title: "Idle wait",
                trailing: "\(Int(engine.idleDebounceSeconds))s",
                footer: "Starts only after you’ve stopped using the Mac for this long."
            ) {
                Slider(value: $engine.idleDebounceSeconds, in: 3...120, step: 1)
            }

            settingsCard(title: "Activity style", footer: engine.profile.detail) {
                Picker("Activity style", selection: $engine.profile) {
                    ForEach(ActivityProfile.allCases) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(engine.isRunning)
                .labelsHidden()
            }

            settingsCard(
                title: "How busy",
                trailing: "\(Int(engine.intensityMin * 100))–\(Int(engine.intensityMax * 100))%",
                footer: "New level every 10 minutes inside this range. Changing Activity style resets it."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    labeledSlider(
                        title: "Quietest",
                        valueLabel: "\(Int(engine.intensityMin * 100))%",
                        value: $engine.intensityMin,
                        range: 0.2...1.0,
                        step: 0.05
                    )
                    labeledSlider(
                        title: "Busiest",
                        valueLabel: "\(Int(engine.intensityMax * 100))%",
                        value: $engine.intensityMax,
                        range: 0.2...1.0,
                        step: 0.05
                    )

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                        Text("This period")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(engine.effectiveIntensity * 100))%")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                        Spacer(minLength: 8)
                        Text("every 10 min")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.75))
                    }
                    .padding(.top, 2)
                }
            }

            settingsCard(title: "Startup") {
                launchAtLoginToggle
            }
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        trailing: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            content()

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeGlassCard(cornerRadius: 12)
    }

    private func labeledSlider(
        title: String,
        valueLabel: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    // MARK: - Shared pieces

    private func header(compact: Bool) -> some View {
        HStack(alignment: .center) {
            Text(BuildIdentity.displayName)
                .font(compact ? .headline : .title2.weight(.semibold))
            Spacer()
            phaseStatusLabel
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(phaseColor.opacity(0.15)))
        }
    }

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activity style")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Activity style", selection: $engine.profile) {
                ForEach(ActivityProfile.allCases) { profile in
                    Text(profile.rawValue).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            .disabled(engine.isRunning)
            .labelsHidden()

            Text(engine.profile.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var intensitySlider: some View {
        // Compact menu-bar panel: single stack without cards.
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("How busy")
                Spacer()
                Text("\(Int(engine.intensityMin * 100))–\(Int(engine.intensityMax * 100))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            labeledSlider(
                title: "Quietest",
                valueLabel: "\(Int(engine.intensityMin * 100))%",
                value: $engine.intensityMin,
                range: 0.2...1.0,
                step: 0.05
            )
            labeledSlider(
                title: "Busiest",
                valueLabel: "\(Int(engine.intensityMax * 100))%",
                value: $engine.intensityMax,
                range: 0.2...1.0,
                step: 0.05
            )
            Text("This period \(Int(engine.effectiveIntensity * 100))% · every 10 min")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var idleWaitSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Wait after you go idle")
                Spacer()
                Text("\(Int(engine.idleDebounceSeconds))s")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $engine.idleDebounceSeconds, in: 3...120, step: 1)
        }
    }

    private var switchIntervalSliders: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Min time between switches")
                    Spacer()
                    Text("\(Int(engine.switchIntervalMinSeconds))s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $engine.switchIntervalMinSeconds,
                    in: 10...max(10, engine.switchIntervalMaxSeconds),
                    step: 5
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max time between switches")
                    Spacer()
                    Text("\(Int(engine.switchIntervalMaxSeconds))s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $engine.switchIntervalMaxSeconds,
                    in: max(10, engine.switchIntervalMinSeconds)...900,
                    step: 5
                )
            }
            Text("After each switch, MoveIt waits a random time between min and max before switching again.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var launchAtLoginToggle: some View {
        Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { newValue in
                LaunchAtLogin.isEnabled = newValue
            }
    }

    private var keyboardSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Keyboard activity", isOn: $engine.includeKeyboard)
            Text(
                engine.includeKeyboard
                    ? "Silent modifiers by default (Shift/Control/Option)."
                    : "Off — mouse & scroll only."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if engine.includeKeyboard {
                Toggle("Character & number keys", isOn: $engine.allowCharacterKeys)
                Text(
                    engine.allowCharacterKeys
                        ? "Letters, digits, and arrows — skipped automatically while a text field, editor, or terminal is focused."
                        : "Off — avoid typing into apps and single-key shortcuts."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var compactActionRow: some View {
        HStack(spacing: 10) {
            startStopButton(fillWidth: true)
            quitButton
        }
    }

    private var windowActionRow: some View {
        HStack(spacing: 10) {
            startStopButton(fillWidth: false)
            quitButton
            Spacer(minLength: 8)
            phaseStatusLabel
        }
    }

    @ViewBuilder
    private func startStopButton(fillWidth: Bool) -> some View {
        if engine.isRunning {
            Button {
                engine.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: fillWidth ? .infinity : nil)
                    .padding(.horizontal, fillWidth ? 0 : 8)
            }
            .keyboardShortcut(".", modifiers: [.command])
            .nativeGlassButton()
            .tint(.red)
            .foregroundStyle(.red)
            .controlSize(.large)
        } else {
            Button {
                refreshPermissions()
                if !accessibilityTrusted {
                    _ = Permissions.ensureAccessibility(prompt: true)
                    refreshPermissions()
                    guard accessibilityTrusted else { return }
                }
                engine.start()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: fillWidth ? .infinity : nil)
                    .padding(.horizontal, fillWidth ? 0 : 8)
            }
            .keyboardShortcut("s", modifiers: [.command])
            .nativeGlassProminentButton()
            .controlSize(.large)
        }
    }

    private var quitButton: some View {
        Button {
            engine.stop()
            AppAppearance.quitCompletely()
        } label: {
            Label("Quit", systemImage: "power")
                .padding(.horizontal, 4)
        }
        .nativeGlassButton()
        .controlSize(.large)
        .help("Quit \(BuildIdentity.displayName) completely")
    }

    private var menuBarIconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 30), spacing: 8)],
                spacing: 10
            ) {
                ForEach(MenuBarIconOption.allCases) { option in
                    let selected = menuBarIconRaw == option.rawValue
                    Button {
                        menuBarIconRaw = option.rawValue
                    } label: {
                        option.labelImage(size: option.pickerImageSize())
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        selected ? Color.accentColor : Color.primary.opacity(0.08),
                                        lineWidth: selected ? 1.5 : 1
                                    )
                            )
                            .overlay(alignment: .topTrailing) {
                                if option.isDefault {
                                    Text("Default")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Capsule(style: .continuous).fill(Color.accentColor))
                                        .offset(x: 6, y: -6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(option.isDefault ? "\(option.title) (Default)" : option.title)
                    .accessibilityLabel(option.isDefault ? "\(option.title), Default" : option.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
    }

    /// Dot + label only — never a glass/capsule wrapper (toolbar adds its own unless hidden).
    private var phaseStatusLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phaseColor)
                .frame(width: 8, height: 8)
            Text(engine.phase.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(engine.phase.rawValue)
    }

    private var phaseColor: Color {
        switch engine.phase {
        case .stopped: return .secondary
        case .waitingForIdle: return .orange
        case .simulating: return .green
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            labeled("Backend", engine.isRunning ? engine.backend.rawValue : "—")
            labeled("Last action", engine.lastActionDescription)
            if engine.isRunning {
                labeled(
                    "Your idle",
                    "\(engine.userIdleSeconds)s / \(Int(engine.idleDebounceSeconds))s"
                )
            }
            labeled("Bursts", "\(engine.actionsCompleted)")
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeGlassCard(cornerRadius: 10)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func refreshPermissions() {
        accessibilityTrusted = Permissions.hasAccessibility
    }
}
