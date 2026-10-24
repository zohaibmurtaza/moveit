import SwiftUI
import AppKit

private enum ControlsWindowPane: String, CaseIterable, Identifiable {
    case activity
    case appearance
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "Activity"
        case .appearance: return "Appearance"
        case .status: return "Status"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: return "play.circle"
        case .appearance: return "menubar.rectangle"
        case .status: return "waveform.path.ecg"
        }
    }
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

    // MARK: - Menu bar dropdown (single column)

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(compact: true)

            Divider()

            PermissionsView(isTrusted: $accessibilityTrusted)

            Divider()

            menuBarIconPicker

            Divider()

            profilePicker
            intensitySlider
            idleDebounceSlider

            statusBlock

            launchAtLoginToggle

            Divider()

            actionRow
        }
        .padding(14)
    }

    // MARK: - Main window (sidebar + content-sized)

    private var windowBody: some View {
        // Prefer intrinsic height; fall back to a scrolling middle when the
        // window is shorter than the content (e.g. user resized it down).
        ViewThatFits(in: .vertical) {
            windowChrome(scrollMiddle: false)
            windowChrome(scrollMiddle: true)
        }
        .frame(width: 680)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func windowChrome(scrollMiddle: Bool) -> some View {
        VStack(spacing: 0) {
            windowHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                windowSidebar
                    .frame(width: 168, alignment: .top)

                Divider()

                Group {
                    if scrollMiddle {
                        ScrollView {
                            windowPaneContent
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        windowPaneContent
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()

            actionRow
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private var windowHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("AppMark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("MoveIt")
                    .font(.title2.weight(.semibold))
                Text("Arms after you stop using the mouse/keyboard, then simulates human-like activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            phaseBadge
        }
    }

    private var windowSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ControlsWindowPane.allCases) { pane in
                let selected = windowPane == pane
                Button {
                    windowPane = pane
                } label: {
                    Label(pane.title, systemImage: pane.systemImage)
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var windowPaneContent: some View {
        switch windowPane {
        case .activity:
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Permissions")
                PermissionsView(isTrusted: $accessibilityTrusted)

                Divider()

                sectionTitle("Simulation")
                profilePicker
                intensitySlider
                idleDebounceSlider

                Divider()

                launchAtLoginToggle
            }
        case .appearance:
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Menu bar")
                Text("Choose the icon shown in the menu bar. Your choice is saved on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                menuBarIconPicker
            }
        case .status:
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Live status")
                statusBlock
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    // MARK: - Shared pieces

    private func header(compact: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MoveIt")
                    .font(compact ? .headline : .title2.weight(.semibold))
                Text("Activity simulator")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            phaseBadge
        }
    }

    private var profilePicker: some View {
        Picker("Profile", selection: $engine.profile) {
            ForEach(ActivityProfile.allCases) { profile in
                Text(profile.rawValue).tag(profile)
            }
        }
        .pickerStyle(.segmented)
        .disabled(engine.isRunning)
    }

    private var intensitySlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Intensity")
                Spacer()
                Text("\(Int(engine.intensity * 100))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $engine.intensity, in: 0.2...1.0, step: 0.05)
        }
    }

    private var idleDebounceSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Idle debounce")
                Spacer()
                Text("\(Int(engine.idleDebounceSeconds))s")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $engine.idleDebounceSeconds, in: 3...120, step: 1)
            Text("Start moving only after you’ve been idle this long.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var launchAtLoginToggle: some View {
        Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { newValue in
                LaunchAtLogin.isEnabled = newValue
            }
    }

    private var actionRow: some View {
        HStack {
            if engine.isRunning {
                Button("Stop") {
                    engine.stop()
                }
                .keyboardShortcut(".", modifiers: [.command])
            } else {
                Button("Start") {
                    refreshPermissions()
                    if !accessibilityTrusted {
                        _ = Permissions.ensureAccessibility(prompt: true)
                        refreshPermissions()
                        guard accessibilityTrusted else { return }
                    }
                    engine.start()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            Button("Quit") {
                engine.stop()
                AppAppearance.quitCompletely()
            }
        }
    }

    private var menuBarIconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                Text("Menu bar icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
            // Room for the Default badge so it isn’t clipped.
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
    }

    private var phaseBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phaseColor)
                .frame(width: 8, height: 8)
            Text(engine.phase.rawValue)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(phaseColor.opacity(0.15), in: Capsule())
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
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
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
