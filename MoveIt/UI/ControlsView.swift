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

    var subtitle: String {
        switch self {
        case .activity:
            return "Arms after idle, then simulates human-like activity."
        case .keyboard:
            return "Silent keys by default; characters are optional."
        case .switching:
            return "Apps, fullscreen Spaces, and browser tabs."
        case .appearance:
            return "Menu bar icon for this Mac."
        case .status:
            return "Live stream of past, current, and upcoming actions."
        }
    }

    /// Settings-style sidebar groups.
    static let simulationPanes: [ControlsWindowPane] = [.activity, .keyboard, .switching]
    static let appPanes: [ControlsWindowPane] = [.appearance, .status]
}

/// Sidebar destination: a settings page, or one supported app under Apps.
private enum SidebarSelection: Hashable {
    case pane(ControlsWindowPane)
    case app(SpecificApp)

    var title: String {
        switch self {
        case .pane(let pane): return pane.title
        case .app(let app): return app.title
        }
    }

    var subtitle: String {
        switch self {
        case .pane(let pane): return pane.subtitle
        case .app(let app): return app.summary
        }
    }
}

/// Apps that have their own activity, separate from the general simulation.
/// Add a case here when another app gets dedicated controls.
private enum SpecificApp: String, CaseIterable, Identifiable {
    case cursor
    case slack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "Cursor"
        case .slack: return "Slack"
        }
    }

    var summary: String {
        switch self {
        case .cursor: return "Explorer, editor lines, terminals, and chats."
        case .slack: return "Channels, search, threads, and workspaces."
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .cursor: return "chevron.left.forwardslash.chevron.right"
        case .slack: return "number"
        }
    }

    var bundleID: String {
        switch self {
        case .cursor: return CursorActivity.bundleID
        case .slack: return SlackActivity.bundleID
        }
    }

    var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var isRunning: Bool {
        switch self {
        case .cursor: return CursorActivity.isRunning
        case .slack: return SlackActivity.isRunning
        }
    }

    func isEnabled(_ engine: ActivityEngine) -> Bool {
        switch self {
        case .cursor: return engine.cursorModeEnabled
        case .slack: return engine.slackModeEnabled
        }
    }
}

/// Shared controls used by the main window and the menu bar panel.
struct ControlsView: View {
    @ObservedObject var engine: ActivityEngine
    var compact: Bool = false

    @State private var accessibilityTrusted = Permissions.hasAccessibility
    @State private var screenRecordingReady = Permissions.canReadWindowTitles
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var sidebarSelection: SidebarSelection = .pane(.activity)
    @State private var appsExpanded = true
    @State private var disguiseName: String = BuildIdentity.disguiseName ?? ""
    @State private var disguiseEnabled: Bool = BuildIdentity.isDisguised
    @AppStorage(MenuBarIconOption.storageKey) private var menuBarIconRaw = MenuBarIconOption.moveit.rawValue

    private var needsPermissions: Bool {
        !accessibilityTrusted || !screenRecordingReady
    }

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

            if needsPermissions {
                Divider()
                PermissionsView(isTrusted: $accessibilityTrusted)
                    .padding(.vertical, 12)
                    .onChange(of: accessibilityTrusted) { _ in refreshPermissions() }
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

    static let windowWidth: CGFloat = 840
    static let windowHeight: CGFloat = 700

    private var windowBody: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section("Simulation") {
                    ForEach(ControlsWindowPane.simulationPanes) { pane in
                        Label(pane.title, systemImage: pane.systemImage)
                            .tag(SidebarSelection.pane(pane))
                    }
                    DisclosureGroup(isExpanded: $appsExpanded) {
                        ForEach(SpecificApp.allCases) { app in
                            sidebarAppRow(app)
                                .tag(SidebarSelection.app(app))
                        }
                    } label: {
                        Label("Apps", systemImage: "square.grid.2x2")
                    }
                }
                Section("App") {
                    ForEach(ControlsWindowPane.appPanes) { pane in
                        Label(pane.title, systemImage: pane.systemImage)
                            .tag(SidebarSelection.pane(pane))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 176, ideal: 200, max: 240)
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
            .navigationTitle(sidebarSelection.title)
            #if os(macOS)
            .navigationSubtitle(sidebarSelection.subtitle)
            #endif
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: Self.windowWidth, height: Self.windowHeight)
    }

    @ViewBuilder
    private var windowPaneContent: some View {
        switch sidebarSelection {
        case .pane(let pane):
            paneContent(pane)
        case .app(let app):
            appControls(app)
        }
    }

    @ViewBuilder
    private func paneContent(_ windowPane: ControlsWindowPane) -> some View {
        switch windowPane {
        case .activity:
            activityPane
        case .keyboard:
            VStack(alignment: .leading, spacing: 18) {
                settingsCard(title: "Keyboard mode") {
                    keyboardSettings
                }

                if engine.includeKeyboard {
                    settingsCard(
                        title: "Typing speed",
                        trailing: "\(Int(engine.keyboardWPM)) WPM",
                        footer: "Controls how fast keys are pressed during keyboard activity."
                    ) {
                        labeledSlider(
                            title: "Words per minute",
                            valueLabel: "\(Int(engine.keyboardWPM))",
                            value: $engine.keyboardWPM,
                            range: 10...120,
                            step: 5
                        )
                    }

                    if engine.allowCharacterKeys {
                        settingsCard(
                            title: "Natural typing",
                            footer: engine.naturalTypingEnabled
                                ? "Types word-level bursts with occasional typos and backspace corrections for realistic patterns."
                                : "Individual random key taps without word structure."
                        ) {
                            Toggle("Type with corrections", isOn: $engine.naturalTypingEnabled)
                        }
                    }
                }
            }
        case .switching:
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Switch among selected apps", isOn: $engine.allowAppNavigation)
                Text(
                    engine.switchTargets.isEmpty
                        ? "Select at least two apps below. MoveIt will only switch among those — never the whole Dock via ⌘Tab."
                        : "Activates your selected apps/windows, including fullscreen ones on other Spaces."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if engine.allowAppNavigation {
                    switchIntervalSliders
                }

                Divider()

                Toggle("Browser tab switching", isOn: $engine.allowTabSwitching)
                if engine.allowTabSwitching {
                    Picker("Tab scope", selection: $engine.tabSwitchScope) {
                        ForEach(TabSwitchScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(engine.tabSwitchScope.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("When Chrome, Safari, or another browser is frontmost: ⌘1–9, ⌃Tab, and ⌘⌥←/→.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

                settingsCard(
                    title: "Global hotkeys",
                    footer: "Work system-wide, even when MoveIt is hidden in the menu bar."
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        hotkeyRow(keys: "⌃⇧U", action: "Start simulation")
                        hotkeyRow(keys: "⌃⇧K", action: "Stop simulation")
                        hotkeyRow(keys: "⌃⇧0", action: "Emergency stop (quit)")
                    }
                }

                settingsCard(
                    title: "Disguise",
                    footer: disguiseEnabled
                        ? "Process name shown in Activity Monitor and `ps`. Relaunch for full effect."
                        : "Show an innocuous process name instead of MoveIt."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Custom process name", isOn: $disguiseEnabled)
                            .onChange(of: disguiseEnabled) { enabled in
                                if enabled {
                                    if disguiseName.isEmpty { disguiseName = "UserEventAgent" }
                                    BuildIdentity.disguiseName = disguiseName
                                } else {
                                    BuildIdentity.disguiseName = nil
                                    disguiseName = ""
                                }
                            }
                        if disguiseEnabled {
                            TextField("Process name", text: $disguiseName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    BuildIdentity.disguiseName = disguiseName.isEmpty ? nil : disguiseName
                                    if disguiseName.isEmpty { disguiseEnabled = false }
                                }
                                .onChange(of: disguiseName) { name in
                                    if !name.isEmpty {
                                        BuildIdentity.disguiseName = name
                                    }
                                }
                            Text("Suggestions: UserEventAgent, WindowServer, CoreServicesUIAgent")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
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
            if needsPermissions {
                settingsCard(title: "Permissions") {
                    PermissionsView(isTrusted: $accessibilityTrusted)
                        .onChange(of: accessibilityTrusted) { _ in refreshPermissions() }
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

            settingsCard(
                title: "Scrolling",
                trailing: "\(Int(engine.scrollIntensity * 100))%",
                footer: engine.scrollAxes.detail
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    labeledSlider(
                        title: "Intensity",
                        valueLabel: "\(Int(engine.scrollIntensity * 100))%",
                        value: $engine.scrollIntensity,
                        range: 0.15...1.0,
                        step: 0.05
                    )
                    Picker("Direction", selection: $engine.scrollAxes) {
                        ForEach(ScrollAxisMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            settingsCard(
                title: "Micro-breaks",
                footer: engine.microBreaksEnabled ? engine.microBreakFrequency.detail : "Off — continuous simulation without pauses."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable micro-breaks", isOn: $engine.microBreaksEnabled)
                    if engine.microBreaksEnabled {
                        Picker("Frequency", selection: $engine.microBreakFrequency) {
                            ForEach(MicroBreakFrequency.allCases) { freq in
                                Text(freq.rawValue).tag(freq)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }

            settingsCard(
                title: "Work rhythms",
                trailing: engine.adaptiveRhythmsEnabled ? engine.currentRhythm.label : "Off",
                footer: engine.adaptiveRhythmsEnabled
                    ? "Activity shifts between typing, reading, navigation, mixed, and quiet phases every 2–6 minutes."
                    : "Off — actions are picked uniformly at random."
            ) {
                Toggle("Adaptive work rhythms", isOn: $engine.adaptiveRhythmsEnabled)
            }

            settingsCard(
                title: "Display",
                footer: engine.primaryDisplayOnly
                    ? "Mouse movement stays on your primary display."
                    : "Mouse can move across all connected displays."
            ) {
                Toggle("Primary display only", isOn: $engine.primaryDisplayOnly)
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

    private func sidebarAppRow(_ app: SpecificApp) -> some View {
        HStack(spacing: 6) {
            if let image = app.icon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: app.fallbackSymbol)
                    .frame(width: 16, height: 16)
            }
            Text(app.title)
        }
        .accessibilityLabel(app.title)
    }

    @ViewBuilder
    private func appControls(_ app: SpecificApp) -> some View {
        switch app {
        case .cursor:
            cursorControls
        case .slack:
            slackControls
        }
    }

    private var cursorControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(
                title: "Cursor",
                trailing: engine.cursorModeEnabled ? "\(Int(engine.cursorTimeShare * 100))%" : "Off",
                footer: "After you go idle, MoveIt comes back to Cursor within a few seconds and stays there for most of the session. It does not type into files, press Return, or accept an AI edit."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use Cursor behavior", isOn: $engine.cursorModeEnabled)
                    if engine.cursorModeEnabled {
                        labeledSlider(
                            title: "Time in Cursor",
                            valueLabel: "\(Int(engine.cursorTimeShare * 100))%",
                            value: $engine.cursorTimeShare,
                            range: 0.4...0.9,
                            step: 0.05
                        )
                    }
                }
            }

            if engine.cursorModeEnabled {
                settingsCard(
                    title: "Inside Cursor",
                    footer: "Follows the panels that are actually open. Widening chats or closing the editor moves the pointer with them, and the activity name matches that pane."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Files", isOn: $engine.cursorEditorTabs)
                        Text("Click a file in the left Explorer, then click different lines in the open file.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Toggle("Terminal tabs", isOn: $engine.cursorTerminalTabs)
                        Text("Click the terminal body, then Command-Shift [ or ].")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Toggle("Chat tabs", isOn: $engine.cursorChatTabs)
                        Text("Click the conversation, then Option-Command Left/Right.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var slackControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(
                title: "Slack",
                trailing: engine.slackModeEnabled ? "\(Int(engine.slackTimeShare * 100))%" : "Off",
                footer: "After you go idle, MoveIt spends time in Slack. It does not type a message or press Return."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use Slack behavior", isOn: $engine.slackModeEnabled)
                    if engine.slackModeEnabled {
                        labeledSlider(
                            title: "Time in Slack",
                            valueLabel: "\(Int(engine.slackTimeShare * 100))%",
                            value: $engine.slackTimeShare,
                            range: 0.4...0.9,
                            step: 0.05
                        )
                    }
                }
            }

            if engine.slackModeEnabled {
                settingsCard(
                    title: "Inside Slack",
                    footer: "Moves through the sidebar and the conversation. Threads open from a message, then close again."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Switch chats", isOn: $engine.slackSwitchChats)
                        Text("Option-Up/Down, or a click in the channel list.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Toggle("Search", isOn: $engine.slackSearch)
                        Text("Opens the search bar with Command-G, then closes it.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Toggle("Scroll chats and channels", isOn: $engine.slackScroll)
                        Text("Scrolls the channel list and the open conversation.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Toggle("Threads", isOn: $engine.slackThreads)
                        Text("Opens a thread while reading, scrolls it, then closes it.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Toggle("Switch organizations", isOn: $engine.slackOrganizations)
                        Text("Control-Tab moves to the next workspace. Leave this off if you stay in one.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
                if engine.adaptiveRhythmsEnabled {
                    labeled("Rhythm", engine.currentRhythm.label)
                }
                if engine.cursorModeEnabled {
                    labeled("Cursor", CursorActivity.isFrontmost() ? "Front" : "Away")
                }
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

    private func hotkeyRow(keys: String, action: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func refreshPermissions() {
        accessibilityTrusted = Permissions.hasAccessibility
        screenRecordingReady = Permissions.canReadWindowTitles
    }
}
