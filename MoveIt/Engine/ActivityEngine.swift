import Foundation
import Combine
import AppKit

enum EnginePhase: String {
    case stopped = "Stopped"
    case waitingForIdle = "Waiting for idle"
    case simulating = "Simulating"
}

final class ActivityEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var phase: EnginePhase = .stopped
    @Published private(set) var backend: InputBackend = .unavailable
    @Published private(set) var lastActionDescription = "Idle"
    @Published private(set) var secondsSinceLastAction: Int = 0
    @Published private(set) var userIdleSeconds: Int = 0
    @Published private(set) var actionsCompleted: Int = 0
    /// Past (oldest → newest), current focus, and planned upcoming actions.
    @Published private(set) var pastEvents: [ActivityEvent] = []
    @Published private(set) var currentEvent: ActivityEvent?
    @Published private(set) var upcomingEvents: [ActivityEvent] = []
    @Published var profile: ActivityProfile = .office {
        didSet {
            UserDefaults.standard.set(profile.rawValue, forKey: Keys.profile)
            state.profile = profile
            // Profiles own a preset busy range; user can still fine-tune after.
            if !isApplyingProfilePreset {
                isApplyingProfilePreset = true
                applyPresetRange(for: profile)
                isApplyingProfilePreset = false
            }
        }
    }
    /// Lower bound of the busy range (0.2…1.0). Effective intensity is sampled inside this.
    @Published var intensityMin: Double = 0.5 {
        didSet {
            let clamped = min(1.0, max(0.2, intensityMin))
            if clamped != intensityMin {
                intensityMin = clamped
                return
            }
            if intensityMin > intensityMax {
                intensityMax = intensityMin
            }
            UserDefaults.standard.set(intensityMin, forKey: Keys.intensityMin)
            clampEffectiveToRange()
        }
    }
    /// Upper bound of the busy range (0.2…1.0).
    @Published var intensityMax: Double = 0.8 {
        didSet {
            let clamped = min(1.0, max(0.2, intensityMax))
            if clamped != intensityMax {
                intensityMax = clamped
                return
            }
            if intensityMax < intensityMin {
                intensityMin = intensityMax
            }
            UserDefaults.standard.set(intensityMax, forKey: Keys.intensityMax)
            clampEffectiveToRange()
        }
    }
    /// Currently applied intensity for this ~10-minute period.
    @Published private(set) var effectiveIntensity: Double = 0.65 {
        didSet {
            state.intensity = effectiveIntensity
        }
    }
    /// Legacy single-value binding for any remaining call sites; maps to range midpoint.
    var intensity: Double {
        get { (intensityMin + intensityMax) / 2 }
        set {
            let spread = max(0.12, (intensityMax - intensityMin) / 2)
            intensityMin = min(1.0, max(0.2, newValue - spread))
            intensityMax = min(1.0, max(0.2, newValue + spread))
        }
    }
    private var isApplyingProfilePreset = false
    private var intensityPeriodStartedAt = Date.distantPast
    private let intensityPeriodSeconds: TimeInterval = 600
    /// Seconds of real user idle required before simulation begins / resumes.
    @Published var idleDebounceSeconds: Double = 20 {
        didSet {
            let clamped = min(300, max(3, idleDebounceSeconds))
            if clamped != idleDebounceSeconds {
                idleDebounceSeconds = clamped
                return
            }
            UserDefaults.standard.set(idleDebounceSeconds, forKey: Keys.idleDebounce)
            state.idleDebounceSeconds = idleDebounceSeconds
        }
    }
    /// Silent modifier taps by default (does not type into fields).
    @Published var includeKeyboard: Bool = true {
        didSet {
            UserDefaults.standard.set(includeKeyboard, forKey: Keys.includeKeyboard)
            state.includeKeyboard = includeKeyboard
        }
    }
    /// Letters / numbers / arrows — off by default; can disturb focused apps.
    @Published var allowCharacterKeys: Bool = false {
        didSet {
            UserDefaults.standard.set(allowCharacterKeys, forKey: Keys.allowCharacterKeys)
            state.allowCharacterKeys = allowCharacterKeys
        }
    }
    /// Switch among user-selected apps/windows (and browser tabs when applicable).
    @Published var allowAppNavigation: Bool = true {
        didSet {
            UserDefaults.standard.set(allowAppNavigation, forKey: Keys.allowAppNavigation)
            state.allowAppNavigation = allowAppNavigation
        }
    }
    /// Apps (and optional windows) MoveIt may activate — never global ⌘Tab.
    @Published var switchTargets: [SwitchAppTarget] = [] {
        didSet {
            AppSwitching.saveTargets(switchTargets)
            state.switchTargets = switchTargets
        }
    }
    private var isAdjustingSwitchInterval = false
    /// Minimum seconds between app/window switches.
    @Published var switchIntervalMinSeconds: Double = 45 {
        didSet {
            let clamped = min(900, max(10, switchIntervalMinSeconds))
            if clamped != switchIntervalMinSeconds {
                switchIntervalMinSeconds = clamped
                return
            }
            if !isAdjustingSwitchInterval, switchIntervalMinSeconds > switchIntervalMaxSeconds {
                isAdjustingSwitchInterval = true
                switchIntervalMaxSeconds = switchIntervalMinSeconds
                isAdjustingSwitchInterval = false
            }
            UserDefaults.standard.set(switchIntervalMinSeconds, forKey: Keys.switchIntervalMin)
            state.switchIntervalMinSeconds = switchIntervalMinSeconds
        }
    }
    /// Maximum seconds between app/window switches.
    @Published var switchIntervalMaxSeconds: Double = 180 {
        didSet {
            let clamped = min(900, max(10, switchIntervalMaxSeconds))
            if clamped != switchIntervalMaxSeconds {
                switchIntervalMaxSeconds = clamped
                return
            }
            if !isAdjustingSwitchInterval, switchIntervalMaxSeconds < switchIntervalMinSeconds {
                isAdjustingSwitchInterval = true
                switchIntervalMinSeconds = switchIntervalMaxSeconds
                isAdjustingSwitchInterval = false
            }
            UserDefaults.standard.set(switchIntervalMaxSeconds, forKey: Keys.switchIntervalMax)
            state.switchIntervalMaxSeconds = switchIntervalMaxSeconds
        }
    }
    /// Minimum seconds between tab switches (browser tabs, Cursor file opens, Claude panel clicks).
    @Published var tabSwitchIntervalMinSeconds: Double = 40 {
        didSet {
            let clamped = min(180, max(10, tabSwitchIntervalMinSeconds))
            if clamped != tabSwitchIntervalMinSeconds {
                tabSwitchIntervalMinSeconds = clamped
                return
            }
            UserDefaults.standard.set(tabSwitchIntervalMinSeconds, forKey: Keys.tabSwitchIntervalMin)
            state.tabSwitchIntervalMinSeconds = tabSwitchIntervalMinSeconds
        }
    }
    /// Reading-scroll strength (tick count / magnitude).
    @Published var scrollIntensity: Double = 0.35 {
        didSet {
            let clamped = min(1.0, max(0.15, scrollIntensity))
            if clamped != scrollIntensity {
                scrollIntensity = clamped
                return
            }
            UserDefaults.standard.set(scrollIntensity, forKey: Keys.scrollIntensity)
            state.scrollIntensity = scrollIntensity
        }
    }
    /// Vertical, horizontal, or both.
    @Published var scrollAxes: ScrollAxisMode = .both {
        didSet {
            UserDefaults.standard.set(scrollAxes.rawValue, forKey: Keys.scrollAxes)
            state.scrollAxes = scrollAxes
        }
    }
    /// Switch browser tabs with ⌘1–9 / ⌃Tab / ⌘⌥←→ when a browser is frontmost.
    @Published var allowTabSwitching: Bool = true {
        didSet {
            UserDefaults.standard.set(allowTabSwitching, forKey: Keys.allowTabSwitching)
            state.allowTabSwitching = allowTabSwitching
        }
    }
    /// Where tab chords are sent: only to browsers, or to any frontmost app.
    @Published var tabSwitchScope: TabSwitchScope = .browsersOnly {
        didSet {
            UserDefaults.standard.set(tabSwitchScope.rawValue, forKey: Keys.tabSwitchScope)
            state.tabSwitchScope = tabSwitchScope
        }
    }
    /// Random pauses (30–120s) that mimic natural coffee/stretch breaks.
    @Published var microBreaksEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(microBreaksEnabled, forKey: Keys.microBreaksEnabled)
            state.microBreaksEnabled = microBreaksEnabled
        }
    }
    /// How often micro-breaks occur.
    @Published var microBreakFrequency: MicroBreakFrequency = .standard {
        didSet {
            UserDefaults.standard.set(microBreakFrequency.rawValue, forKey: Keys.microBreakFrequency)
            state.microBreakFrequency = microBreakFrequency
        }
    }
    /// Phase-based activity shifts (typing, reading, navigation, mixed, quiet).
    @Published var adaptiveRhythmsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(adaptiveRhythmsEnabled, forKey: Keys.adaptiveRhythms)
            state.adaptiveRhythmsEnabled = adaptiveRhythmsEnabled
        }
    }
    /// Current work rhythm — read-only published for UI display.
    @Published private(set) var currentRhythm: WorkRhythm = .mixed
    /// Keyboard speed in words per minute.
    @Published var keyboardWPM: Double = 40 {
        didSet {
            let clamped = min(120, max(10, keyboardWPM))
            if clamped != keyboardWPM {
                keyboardWPM = clamped
                return
            }
            UserDefaults.standard.set(keyboardWPM, forKey: Keys.keyboardWPM)
            state.keyboardWPM = keyboardWPM
        }
    }
    /// Natural character typing with occasional typos + backspace corrections.
    @Published var naturalTypingEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(naturalTypingEnabled, forKey: Keys.naturalTyping)
            state.naturalTypingEnabled = naturalTypingEnabled
        }
    }
    /// Constrain mouse activity to the primary display only.
    @Published var primaryDisplayOnly: Bool = false {
        didSet {
            UserDefaults.standard.set(primaryDisplayOnly, forKey: Keys.primaryDisplayOnly)
            state.primaryDisplayOnly = primaryDisplayOnly
        }
    }
    /// Prefer Cursor and work inside it (files, terminal, chats).
    @Published var cursorModeEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(cursorModeEnabled, forKey: Keys.cursorModeEnabled)
            state.cursorModeEnabled = cursorModeEnabled
        }
    }
    /// Share of app-switches that stay in, or return to, Cursor. 0.4…0.9.
    @Published var cursorTimeShare: Double = 0.7 {
        didSet {
            let clamped = min(0.9, max(0.4, cursorTimeShare))
            if clamped != cursorTimeShare {
                cursorTimeShare = clamped
                return
            }
            UserDefaults.standard.set(cursorTimeShare, forKey: Keys.cursorTimeShare)
            state.cursorTimeShare = cursorTimeShare
        }
    }
    /// Cycle editor tabs and read in the file area.
    @Published var cursorEditorTabs: Bool = true {
        didSet {
            UserDefaults.standard.set(cursorEditorTabs, forKey: Keys.cursorEditorTabs)
            state.cursorEditorTabs = cursorEditorTabs
        }
    }
    /// Cycle terminal tabs and scroll the terminal.
    @Published var cursorTerminalTabs: Bool = true {
        didSet {
            UserDefaults.standard.set(cursorTerminalTabs, forKey: Keys.cursorTerminalTabs)
            state.cursorTerminalTabs = cursorTerminalTabs
        }
    }
    /// Cycle Cursor conversation tabs and scroll the chat.
    @Published var cursorChatTabs: Bool = true {
        didSet {
            UserDefaults.standard.set(cursorChatTabs, forKey: Keys.cursorChatTabs)
            state.cursorChatTabs = cursorChatTabs
        }
    }
    /// Scroll Cursor's Agents sidebar (separate from Chat). Never clicks or sends chords.
    @Published var cursorAgentMode: Bool = true {
        didSet {
            UserDefaults.standard.set(cursorAgentMode, forKey: Keys.cursorAgentMode)
            state.cursorAgentMode = cursorAgentMode
        }
    }
    /// Prefer Slack and move through channels, threads, and search.
    @Published var slackModeEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(slackModeEnabled, forKey: Keys.slackModeEnabled)
            state.slackModeEnabled = slackModeEnabled
        }
    }
    /// Share of switches that stay in Slack. 0.4…0.9.
    @Published var slackTimeShare: Double = 0.7 {
        didSet {
            let clamped = min(0.9, max(0.4, slackTimeShare))
            if clamped != slackTimeShare {
                slackTimeShare = clamped
                return
            }
            UserDefaults.standard.set(slackTimeShare, forKey: Keys.slackTimeShare)
            state.slackTimeShare = slackTimeShare
        }
    }
    @Published var slackSwitchChats: Bool = true {
        didSet {
            UserDefaults.standard.set(slackSwitchChats, forKey: Keys.slackSwitchChats)
            state.slackSwitchChats = slackSwitchChats
        }
    }
    @Published var slackSearch: Bool = true {
        didSet {
            UserDefaults.standard.set(slackSearch, forKey: Keys.slackSearch)
            state.slackSearch = slackSearch
        }
    }
    @Published var slackScroll: Bool = true {
        didSet {
            UserDefaults.standard.set(slackScroll, forKey: Keys.slackScroll)
            state.slackScroll = slackScroll
        }
    }
    @Published var slackThreads: Bool = true {
        didSet {
            UserDefaults.standard.set(slackThreads, forKey: Keys.slackThreads)
            state.slackThreads = slackThreads
        }
    }
    /// Cycle Slack workspaces. Off unless you turn it on.
    @Published var slackOrganizations: Bool = false {
        didSet {
            UserDefaults.standard.set(slackOrganizations, forKey: Keys.slackOrganizations)
            state.slackOrganizations = slackOrganizations
        }
    }
    /// Prefer Claude desktop and move through its chat, terminal, files, and changes panels.
    @Published var claudeModeEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(claudeModeEnabled, forKey: Keys.claudeModeEnabled)
            state.claudeModeEnabled = claudeModeEnabled
        }
    }
    /// Share of switches that stay in Claude. 0.4…0.9.
    @Published var claudeTimeShare: Double = 0.7 {
        didSet {
            let clamped = min(0.9, max(0.4, claudeTimeShare))
            if clamped != claudeTimeShare {
                claudeTimeShare = clamped
                return
            }
            UserDefaults.standard.set(claudeTimeShare, forKey: Keys.claudeTimeShare)
            state.claudeTimeShare = claudeTimeShare
        }
    }
    @Published var claudeChat: Bool = true {
        didSet {
            UserDefaults.standard.set(claudeChat, forKey: Keys.claudeChat)
            state.claudeChat = claudeChat
        }
    }
    @Published var claudeTerminal: Bool = true {
        didSet {
            UserDefaults.standard.set(claudeTerminal, forKey: Keys.claudeTerminal)
            state.claudeTerminal = claudeTerminal
        }
    }
    @Published var claudeFiles: Bool = true {
        didSet {
            UserDefaults.standard.set(claudeFiles, forKey: Keys.claudeFiles)
            state.claudeFiles = claudeFiles
        }
    }
    @Published var claudeChanges: Bool = true {
        didSet {
            UserDefaults.standard.set(claudeChanges, forKey: Keys.claudeChanges)
            state.claudeChanges = claudeChanges
        }
    }

    private let device = VirtualHIDDevice()
    private let mouse: MouseSimulator
    private let keyboard: KeyboardSimulator
    private let idleMonitor = IdleMonitor()
    private var worker: Thread?
    private let state = EngineState()
    private var uiTicker: Timer?
    private var lastActionDate = Date()
    private var globalHotkeyMonitor: Any?

    private enum Keys {
        static let profile = "moveit.profile"
        static let intensity = "moveit.intensity"
        static let intensityMin = "moveit.intensityMin"
        static let intensityMax = "moveit.intensityMax"
        static let idleDebounce = "moveit.idleDebounce"
        static let includeKeyboard = "moveit.includeKeyboard"
        static let allowCharacterKeys = "moveit.allowCharacterKeys"
        static let allowAppNavigation = "moveit.allowAppNavigation"
        static let switchIntervalMin = "moveit.switchIntervalMin"
        static let switchIntervalMax = "moveit.switchIntervalMax"
        static let tabSwitchIntervalMin = "moveit.tabSwitchIntervalMin"
        static let scrollIntensity = "moveit.scrollIntensity"
        static let scrollAxes = "moveit.scrollAxes"
        static let allowTabSwitching = "moveit.allowTabSwitching"
        static let tabSwitchScope = "moveit.tabSwitchScope"
        static let microBreaksEnabled = "moveit.microBreaksEnabled"
        static let microBreakFrequency = "moveit.microBreakFrequency"
        static let adaptiveRhythms = "moveit.adaptiveRhythms"
        static let keyboardWPM = "moveit.keyboardWPM"
        static let naturalTyping = "moveit.naturalTyping"
        static let primaryDisplayOnly = "moveit.primaryDisplayOnly"
        static let cursorModeEnabled = "moveit.cursorModeEnabled"
        static let cursorTimeShare = "moveit.cursorTimeShare"
        static let cursorEditorTabs = "moveit.cursorEditorTabs"
        static let cursorTerminalTabs = "moveit.cursorTerminalTabs"
        static let cursorChatTabs = "moveit.cursorChatTabs"
        static let cursorAgentMode = "moveit.cursorAgentMode"
        static let slackModeEnabled = "moveit.slackModeEnabled"
        static let slackTimeShare = "moveit.slackTimeShare"
        static let slackSwitchChats = "moveit.slackSwitchChats"
        static let slackSearch = "moveit.slackSearch"
        static let slackScroll = "moveit.slackScroll"
        static let slackThreads = "moveit.slackThreads"
        static let slackOrganizations = "moveit.slackOrganizations"
        static let claudeModeEnabled = "moveit.claudeModeEnabled"
        static let claudeTimeShare = "moveit.claudeTimeShare"
        static let claudeChat = "moveit.claudeChat"
        static let claudeTerminal = "moveit.claudeTerminal"
        static let claudeFiles = "moveit.claudeFiles"
        static let claudeChanges = "moveit.claudeChanges"
    }

    init() {
        mouse = MouseSimulator(device: device)
        keyboard = KeyboardSimulator(device: device)

        // Load profile without triggering preset overwrite until intensity range is restored.
        isApplyingProfilePreset = true
        if let raw = UserDefaults.standard.string(forKey: Keys.profile),
           let saved = ActivityProfile(rawValue: raw) {
            profile = saved
        } else {
            profile = .office
        }

        if let savedMin = UserDefaults.standard.object(forKey: Keys.intensityMin) as? Double,
           let savedMax = UserDefaults.standard.object(forKey: Keys.intensityMax) as? Double
        {
            intensityMin = min(savedMin, savedMax)
            intensityMax = max(savedMin, savedMax)
        } else if let legacy = UserDefaults.standard.object(forKey: Keys.intensity) as? Double {
            intensityMin = min(1.0, max(0.2, legacy - 0.12))
            intensityMax = min(1.0, max(0.2, legacy + 0.12))
        } else {
            applyPresetRange(for: profile)
        }
        resampleEffectiveIntensity(force: true)
        isApplyingProfilePreset = false

        let savedDebounce = UserDefaults.standard.object(forKey: Keys.idleDebounce) as? Double
        idleDebounceSeconds = savedDebounce ?? 20
        // Silent keyboard on by default; character keys stay off unless opted in.
        includeKeyboard = UserDefaults.standard.object(forKey: Keys.includeKeyboard) as? Bool ?? true
        allowCharacterKeys = UserDefaults.standard.object(forKey: Keys.allowCharacterKeys) as? Bool ?? false
        allowAppNavigation = UserDefaults.standard.object(forKey: Keys.allowAppNavigation) as? Bool ?? true
        switchTargets = AppSwitching.loadTargets()
        let savedMin = UserDefaults.standard.object(forKey: Keys.switchIntervalMin) as? Double
        let savedMax = UserDefaults.standard.object(forKey: Keys.switchIntervalMax) as? Double
        switchIntervalMinSeconds = savedMin ?? 45
        switchIntervalMaxSeconds = savedMax ?? 180
        tabSwitchIntervalMinSeconds = UserDefaults.standard.object(forKey: Keys.tabSwitchIntervalMin) as? Double ?? 40
        // One-time migrate: prior default 0.55 felt too fast with the old tick timing.
        if !UserDefaults.standard.bool(forKey: "moveit.scrollIntensity.v2") {
            UserDefaults.standard.set(true, forKey: "moveit.scrollIntensity.v2")
            if UserDefaults.standard.object(forKey: Keys.scrollIntensity) == nil
                || (UserDefaults.standard.object(forKey: Keys.scrollIntensity) as? Double) == 0.55
            {
                UserDefaults.standard.set(0.35, forKey: Keys.scrollIntensity)
            }
        }
        scrollIntensity = UserDefaults.standard.object(forKey: Keys.scrollIntensity) as? Double ?? 0.35
        if let axesRaw = UserDefaults.standard.string(forKey: Keys.scrollAxes),
           let axes = ScrollAxisMode(rawValue: axesRaw) {
            scrollAxes = axes
        } else {
            scrollAxes = .both
        }
        allowTabSwitching = UserDefaults.standard.object(forKey: Keys.allowTabSwitching) as? Bool ?? true
        if let scopeRaw = UserDefaults.standard.string(forKey: Keys.tabSwitchScope),
           let scope = TabSwitchScope(rawValue: scopeRaw) {
            tabSwitchScope = scope
        }
        microBreaksEnabled = UserDefaults.standard.object(forKey: Keys.microBreaksEnabled) as? Bool ?? true
        if let freqRaw = UserDefaults.standard.string(forKey: Keys.microBreakFrequency),
           let freq = MicroBreakFrequency(rawValue: freqRaw) {
            microBreakFrequency = freq
        }
        adaptiveRhythmsEnabled = UserDefaults.standard.object(forKey: Keys.adaptiveRhythms) as? Bool ?? true
        keyboardWPM = UserDefaults.standard.object(forKey: Keys.keyboardWPM) as? Double ?? 40
        naturalTypingEnabled = UserDefaults.standard.object(forKey: Keys.naturalTyping) as? Bool ?? true
        primaryDisplayOnly = UserDefaults.standard.object(forKey: Keys.primaryDisplayOnly) as? Bool ?? false
        cursorModeEnabled = UserDefaults.standard.object(forKey: Keys.cursorModeEnabled) as? Bool ?? true
        cursorTimeShare = UserDefaults.standard.object(forKey: Keys.cursorTimeShare) as? Double ?? 0.7
        cursorEditorTabs = UserDefaults.standard.object(forKey: Keys.cursorEditorTabs) as? Bool ?? true
        cursorTerminalTabs = UserDefaults.standard.object(forKey: Keys.cursorTerminalTabs) as? Bool ?? true
        cursorChatTabs = UserDefaults.standard.object(forKey: Keys.cursorChatTabs) as? Bool ?? true
        cursorAgentMode = UserDefaults.standard.object(forKey: Keys.cursorAgentMode) as? Bool ?? true
        slackModeEnabled = UserDefaults.standard.object(forKey: Keys.slackModeEnabled) as? Bool ?? true
        slackTimeShare = UserDefaults.standard.object(forKey: Keys.slackTimeShare) as? Double ?? 0.7
        slackSwitchChats = UserDefaults.standard.object(forKey: Keys.slackSwitchChats) as? Bool ?? true
        slackSearch = UserDefaults.standard.object(forKey: Keys.slackSearch) as? Bool ?? true
        slackScroll = UserDefaults.standard.object(forKey: Keys.slackScroll) as? Bool ?? true
        slackThreads = UserDefaults.standard.object(forKey: Keys.slackThreads) as? Bool ?? true
        slackOrganizations = UserDefaults.standard.object(forKey: Keys.slackOrganizations) as? Bool ?? false
        claudeModeEnabled = UserDefaults.standard.object(forKey: Keys.claudeModeEnabled) as? Bool ?? true
        claudeTimeShare = UserDefaults.standard.object(forKey: Keys.claudeTimeShare) as? Double ?? 0.7
        claudeChat = UserDefaults.standard.object(forKey: Keys.claudeChat) as? Bool ?? true
        claudeTerminal = UserDefaults.standard.object(forKey: Keys.claudeTerminal) as? Bool ?? true
        claudeFiles = UserDefaults.standard.object(forKey: Keys.claudeFiles) as? Bool ?? true
        claudeChanges = UserDefaults.standard.object(forKey: Keys.claudeChanges) as? Bool ?? true

        publishSettingsToState()
        state.scheduleNextSwitch()
        state.scheduleNextTabSwitch()
        installGlobalHotkeys()
    }

    func start() {
        guard !isRunning else { return }
        state.cancelFlag = false
        // Settings freeze at Start: publish once, then the worker keeps its own snapshot.
        publishSettingsToState()
        state.scheduleNextSwitch()
        state.scheduleNextTabSwitch()
        let startedBackend = device.start()
        backend = startedBackend
        guard device.isReady else {
            lastActionDescription = "Input backend failed"
            phase = .stopped
            return
        }

        idleMonitor.start()
        idleMonitor.markUserActive()

        isRunning = true
        phase = .waitingForIdle
        lastActionDate = Date()
        secondsSinceLastAction = 0
        userIdleSeconds = 0
        lastActionDescription = "Armed — waiting \(Int(idleDebounceSeconds))s idle (\(startedBackend.rawValue))"
        pastEvents = []
        currentEvent = nil
        upcomingEvents = []
        resampleEffectiveIntensity(force: true)
        startUITicker()

        let thread = Thread { [weak self] in
            self?.runLoop()
        }
        thread.name = "MoveIt.ActivityEngine"
        thread.qualityOfService = .userInitiated
        worker = thread
        thread.start()
    }

    func stop() {
        // Signal first so in-flight mouse/scroll/keys abort before tearing down HID.
        // Do NOT sleep on the main thread here — the worker uses main.sync for the
        // activity stream and would deadlock if main were blocked.
        state.cancelFlag = true
        worker?.cancel()
        worker = nil
        device.releaseAllKeys()
        device.stop()
        idleMonitor.stop()
        uiTicker?.invalidate()
        uiTicker = nil
        isRunning = false
        phase = .stopped
        backend = .unavailable
        userIdleSeconds = 0
        lastActionDescription = "Stopped"
        DispatchQueue.main.async { [weak self] in
            self?.currentEvent = nil
            self?.upcomingEvents = []
        }
    }

    func publishSettingsToState() {
        state.profile = profile
        state.intensity = effectiveIntensity
        state.idleDebounceSeconds = idleDebounceSeconds
        state.includeKeyboard = includeKeyboard
        state.allowCharacterKeys = allowCharacterKeys
        state.allowAppNavigation = allowAppNavigation
        state.switchTargets = switchTargets
        state.switchIntervalMinSeconds = switchIntervalMinSeconds
        state.switchIntervalMaxSeconds = switchIntervalMaxSeconds
        state.tabSwitchIntervalMinSeconds = tabSwitchIntervalMinSeconds
        state.scrollIntensity = scrollIntensity
        state.scrollAxes = scrollAxes
        state.allowTabSwitching = allowTabSwitching
        state.tabSwitchScope = tabSwitchScope
        state.microBreaksEnabled = microBreaksEnabled
        state.microBreakFrequency = microBreakFrequency
        state.adaptiveRhythmsEnabled = adaptiveRhythmsEnabled
        state.keyboardWPM = keyboardWPM
        state.naturalTypingEnabled = naturalTypingEnabled
        state.primaryDisplayOnly = primaryDisplayOnly
        state.cursorModeEnabled = cursorModeEnabled
        state.cursorTimeShare = cursorTimeShare
        state.cursorEditorTabs = cursorEditorTabs
        state.cursorTerminalTabs = cursorTerminalTabs
        state.cursorChatTabs = cursorChatTabs
        state.cursorAgentMode = cursorAgentMode
        state.slackModeEnabled = slackModeEnabled
        state.slackTimeShare = slackTimeShare
        state.slackSwitchChats = slackSwitchChats
        state.slackSearch = slackSearch
        state.slackScroll = slackScroll
        state.slackThreads = slackThreads
        state.slackOrganizations = slackOrganizations
        state.claudeModeEnabled = claudeModeEnabled
        state.claudeTimeShare = claudeTimeShare
        state.claudeChat = claudeChat
        state.claudeTerminal = claudeTerminal
        state.claudeFiles = claudeFiles
        state.claudeChanges = claudeChanges
    }

    private func startUITicker() {
        uiTicker?.invalidate()
        uiTicker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.isRunning else { return }
                self.resampleEffectiveIntensityIfNeeded()
                // Keep worker settings live so slider changes (idle wait, etc.) apply without Stop/Start.
                self.publishSettingsToState()
                self.userIdleSeconds = Int(self.idleMonitor.secondsSinceUserActivity)
                if self.phase == .simulating {
                    self.secondsSinceLastAction = Int(Date().timeIntervalSince(self.lastActionDate))
                }
            }
        }
    }

    private func applyPresetRange(for profile: ActivityProfile) {
        let center = profile.presetIntensity
        intensityMin = min(1.0, max(0.2, center - 0.15))
        intensityMax = min(1.0, max(0.2, center + 0.15))
        resampleEffectiveIntensity(force: true)
    }

    private func clampEffectiveToRange() {
        let lo = min(intensityMin, intensityMax)
        let hi = max(intensityMin, intensityMax)
        if effectiveIntensity < lo || effectiveIntensity > hi {
            effectiveIntensity = min(hi, max(lo, effectiveIntensity))
        }
        state.intensity = effectiveIntensity
    }

    private func resampleEffectiveIntensityIfNeeded() {
        guard Date().timeIntervalSince(intensityPeriodStartedAt) >= intensityPeriodSeconds else { return }
        resampleEffectiveIntensity(force: true)
    }

    /// Pick a new level inside the user range so successive 10-minute windows differ.
    private func resampleEffectiveIntensity(force: Bool) {
        if !force, Date().timeIntervalSince(intensityPeriodStartedAt) < intensityPeriodSeconds {
            return
        }
        let lo = min(intensityMin, intensityMax)
        let hi = max(intensityMin, intensityMax)
        let span = hi - lo
        let previous = effectiveIntensity
        var next: Double
        if span < 0.04 {
            next = (lo + hi) / 2
        } else {
            let minDelta = min(0.1, span * 0.4)
            next = Double.random(in: lo...hi)
            for _ in 0..<6 where abs(next - previous) < minDelta {
                next = Double.random(in: lo...hi)
            }
        }
        effectiveIntensity = next
        intensityPeriodStartedAt = Date()
        state.intensity = next
        UserDefaults.standard.set(next, forKey: Keys.intensity)
    }

    private func runLoop() {
        var human = Humanization()
        var settings = state.snapshot()
        var currentPhase: WorkRhythm = human.nextWorkRhythm(current: nil)
        var phaseStartedAt = Date()
        var phaseDuration = human.rhythmPhaseDuration()
        var nextMicroBreak = Date().addingTimeInterval(
            human.nextMicroBreakDelay(frequency: settings.microBreakFrequency)
        )

        DispatchQueue.main.async { [weak self] in
            self?.currentRhythm = currentPhase
        }

        while !state.cancelFlag {
            // Worker-side period check (UI ticker also updates on main).
            if Date().timeIntervalSince(intensityPeriodStartedAt) >= intensityPeriodSeconds {
                DispatchQueue.main.sync { [weak self] in
                    self?.resampleEffectiveIntensity(force: true)
                }
            }
            // Re-read settings every cycle so UI changes apply live (no Stop/Start needed).
            settings = state.snapshot()

            // Shift work rhythm phase when its duration expires.
            if settings.adaptiveRhythmsEnabled,
               Date().timeIntervalSince(phaseStartedAt) >= phaseDuration
            {
                currentPhase = human.nextWorkRhythm(current: currentPhase)
                phaseStartedAt = Date()
                phaseDuration = human.rhythmPhaseDuration()
                DispatchQueue.main.async { [weak self] in
                    self?.currentRhythm = currentPhase
                }
            }

            // Drop any planned events from a previous cycle so we never fire a
            // switch that was claimed while still waiting for idle.
            clearUpcoming()

            setPhase(.waitingForIdle)
            beginEvent(.waiting, "Waiting \(Int(settings.idleDebounceSeconds))s idle…")

            if waitForUserIdle() { break }
            if state.cancelFlag { break }

            // Fresh settings after idle — user may have changed intensity / scroll / targets.
            settings = state.snapshot()

            // ─── Micro-break ───
            if settings.microBreaksEnabled, Date() >= nextMicroBreak {
                let breakDuration = human.microBreakDuration()
                let secs = Int(breakDuration)
                beginEvent(.microBreak, "Micro-break (\(secs)s)")
                setPhase(.simulating)
                if sleepWhileUserStillIdle(breakDuration) {
                    nextMicroBreak = Date().addingTimeInterval(
                        human.nextMicroBreakDelay(frequency: settings.microBreakFrequency)
                    )
                    continue
                }
                nextMicroBreak = Date().addingTimeInterval(
                    human.nextMicroBreakDelay(frequency: settings.microBreakFrequency)
                )
                markActionCompleted()
                continue
            }

            let rhythm: WorkRhythm = settings.adaptiveRhythmsEnabled ? currentPhase : .mixed
            setPhase(.simulating)
            refillUpcoming(settings: settings, rhythm: rhythm, human: &human)

            let burstCount = human.burstLength(profile: settings.profile, intensity: settings.intensity)
            for _ in 0..<burstCount {
                if shouldAbortPlayback() { break }

                settings = state.snapshot()
                refillUpcoming(settings: settings, rhythm: rhythm, human: &human)
                let next = popUpcoming() ?? planEvent(settings: settings, rhythm: rhythm, human: &human)
                // App / tab / Cursor / Claude switches are followed by a longer settle gap.
                var switched = false

                switch next.kind {
                case .appSwitch:
                    beginEvent(next)
                    if next.title == CursorActivity.focusEventTitle {
                        performActivateCursor()
                    } else if next.title == SlackActivity.focusEventTitle {
                        performActivateSlack()
                    } else if next.title == ClaudeActivity.focusEventTitle {
                        performActivateClaude()
                    } else {
                        performRestrictedNavigation(settings: settings, human: &human)
                    }
                    clearUpcoming()
                    switched = true
                case .tabSwitch:
                    if settings.slackModeEnabled, SlackActivity.isFrontmost() {
                        beginEvent(.slack, SlackMove.channel.eventTitle(switching: true))
                        performSlack(move: .channel, switching: true, settings: settings, human: &human)
                        switched = true
                    } else if settings.cursorModeEnabled, CursorActivity.isFrontmost() {
                        let layout = CursorActivity.layout()
                        let surface: CursorSurface = layout.has(.editor) ? .editor : (layout.has(.chat) ? .chat : .terminal)
                        beginEvent(.cursor, surface.eventTitle(switching: true))
                        switched = performCursor(
                            surface: surface,
                            switchTabs: true,
                            settings: settings,
                            human: &human
                        )
                    } else if settings.claudeModeEnabled, ClaudeActivity.isFrontmost() {
                        let layout = ClaudeActivity.layout()
                        let surface: ClaudeSurface = layout.has(.files) ? .files : (layout.has(.chat) ? .chat : .terminal)
                        beginEvent(.claude, surface.eventTitle(switching: true))
                        switched = performClaude(
                            surface: surface,
                            switching: true,
                            settings: settings,
                            human: &human
                        )
                    } else {
                        let canSend: Bool
                        if settings.tabSwitchScope == .browsersOnly {
                            canSend = AppSwitching.frontmostIsBrowser(in: settings.switchTargets)
                        } else {
                            canSend = true
                        }
                        if canSend {
                            beginEvent(next)
                            performTabSwitch(settings: settings, human: &human)
                            switched = true
                        } else {
                            beginEvent(.skipped, "Skipped tab (no browser front)")
                        }
                    }
                case .cursor:
                    if let parsed = CursorSurface.parse(eventTitle: next.title) {
                        beginEvent(next)
                        switched = performCursor(
                            surface: parsed.surface,
                            switchTabs: parsed.switchTabs,
                            settings: settings,
                            human: &human
                        )
                    } else {
                        beginEvent(.skipped, "Skipped Cursor action")
                    }
                case .claude:
                    if let parsed = ClaudeSurface.parse(eventTitle: next.title) {
                        beginEvent(next)
                        switched = performClaude(
                            surface: parsed.surface,
                            switching: parsed.switching,
                            settings: settings,
                            human: &human
                        )
                    } else {
                        beginEvent(.skipped, "Skipped Claude action")
                    }
                case .slack:
                    if let parsed = SlackMove.parse(eventTitle: next.title) {
                        beginEvent(next)
                        performSlack(
                            move: parsed.0,
                            switching: parsed.1,
                            settings: settings,
                            human: &human
                        )
                    } else {
                        beginEvent(.skipped, "Skipped Slack action")
                    }
                case .mouse:
                    beginEvent(next)
                    let distance = human.travelDistance(profile: settings.profile)
                        * (0.6 + settings.intensity * 0.8)
                    let cursorWindow: CGRect? = {
                        if settings.slackModeEnabled, SlackActivity.isFrontmost() {
                            return SlackActivity.layout()?.messages
                        }
                        if settings.claudeModeEnabled, ClaudeActivity.isFrontmost() {
                            let layout = ClaudeActivity.layout()
                            return layout.interactionRect(for: .chat)
                                ?? ClaudeSurface.allCases.lazy.compactMap { layout.interactionRect(for: $0) }.first
                                ?? layout.window?.insetBy(dx: 36, dy: 28)
                        }
                        guard settings.cursorModeEnabled, CursorActivity.isFrontmost() else { return nil }
                        let layout = CursorActivity.layout()
                        return layout.interactionRect(for: .editor)
                            ?? layout.interactionRect(for: .chat)
                            ?? layout.interactionRect(for: .agent)
                            ?? layout.interactionRect(for: .terminal)
                            ?? layout.window?.insetBy(dx: 36, dy: 28)
                    }()
                    let path = human.mousePath(
                        distanceHint: distance,
                        profile: settings.profile,
                        primaryDisplayOnly: settings.primaryDisplayOnly,
                        within: cursorWindow
                    )
                    mouse.play(
                        path: path,
                        inject: makeInject(),
                        isCancelled: makeCancel()
                    )
                case .scroll:
                    beginEvent(next)
                    let ticks = human.readingScrollTicks(
                        profile: settings.profile,
                        intensity: settings.scrollIntensity,
                        axes: settings.scrollAxes
                    )
                    mouse.playScroll(
                        ticks: ticks,
                        inject: makeInject(),
                        isCancelled: makeCancel()
                    )
                case .keyboard, .silentKeys:
                    if settings.slackModeEnabled, SlackActivity.isFrontmost() {
                        beginEvent(.slack, SlackMove.messages.eventTitle(switching: false))
                        performSlack(move: .messages, switching: false, settings: settings, human: &human)
                        break
                    }
                    if settings.claudeModeEnabled, ClaudeActivity.isFrontmost() {
                        let layout = ClaudeActivity.layout()
                        let surface: ClaudeSurface = layout.has(.chat) ? .chat : (ClaudeSurface.allCases.first { layout.has($0) } ?? .chat)
                        beginEvent(.claude, surface.eventTitle(switching: false))
                        performClaude(
                            surface: surface,
                            switching: false,
                            settings: settings,
                            human: &human
                        )
                        break
                    }
                    if settings.cursorModeEnabled, CursorActivity.isFrontmost() {
                        let layout = CursorActivity.layout()
                        let surface: CursorSurface = layout.has(.editor) ? .editor : (layout.has(.chat) ? .chat : .terminal)
                        beginEvent(.cursor, surface.eventTitle(switching: false))
                        performCursor(
                            surface: surface,
                            switchTabs: false,
                            settings: settings,
                            human: &human
                        )
                        break
                    }
                    beginEvent(next)
                    // Never type characters into Cursor, Slack, or Claude — even when
                    // their mode toggles are off or Accessibility cannot see the field.
                    let dedicatedFront = CursorActivity.isFrontmost()
                        || SlackActivity.isFrontmost()
                        || ClaudeActivity.isFrontmost()
                    let editing = FocusSafety.isEditingText || dedicatedFront
                    let useCharacters = next.kind == .keyboard && !editing
                    if next.kind == .keyboard && editing {
                        beginEvent(.skipped, "Skipped characters (text focused)")
                        let sequence = human.keySequence(
                            profile: settings.profile,
                            allowCharacters: false,
                            wpm: settings.keyboardWPM
                        )
                        keyboard.play(
                            sequence: sequence,
                            inject: makeInject(),
                            abortCharactersIfEditing: true,
                            isCancelled: makeCancel()
                        )
                    } else if useCharacters, settings.naturalTypingEnabled {
                        let sequence = human.naturalTypingSequence(
                            profile: settings.profile,
                            wpm: settings.keyboardWPM
                        )
                        keyboard.play(
                            sequence: sequence,
                            inject: makeInject(),
                            abortCharactersIfEditing: true,
                            isCancelled: makeCancel()
                        )
                    } else {
                        let sequence = human.keySequence(
                            profile: settings.profile,
                            allowCharacters: useCharacters,
                            wpm: settings.keyboardWPM
                        )
                        keyboard.play(
                            sequence: sequence,
                            inject: makeInject(),
                            abortCharactersIfEditing: useCharacters,
                            isCancelled: makeCancel()
                        )
                    }
                case .microBreak:
                    beginEvent(next)
                case .waiting, .skipped:
                    beginEvent(next)
                }

                // Between actions: cancel OR real user input aborts the burst.
                // Switches get a longer settle gap so windows / panes can catch up.
                let betweenActions = switched
                    ? Double.random(in: 1.2...3.5)
                    : Double.random(in: 0.08...0.45)
                if sleepWhileUserStillIdle(betweenActions) { break }
            }

            markActionCompleted()

            // Natural gap between bursts, but abort early if the user returns.
            let gap = human.nextIdleGap(profile: settings.profile, intensity: settings.intensity)
            _ = sleepWhileUserStillIdle(gap)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isRunning {
                self.stop()
            }
        }
    }

    private func playIgnoring(_ body: () -> Void) {
        idleMonitor.performIgnoringActivity(body)
    }

    /// Stop button, cancel flag, or real user input mid-playback.
    private func shouldAbortPlayback() -> Bool {
        state.cancelFlag || idleMonitor.secondsSinceUserActivity < 0.35
    }

    private func performActivateCursor() {
        let target = SwitchAppTarget(
            bundleIdentifier: CursorActivity.runningBundleID ?? CursorActivity.bundleID,
            displayName: "Cursor",
            selectedWindowTitles: []
        )
        let label = AppSwitching.activate(target) ?? "Focus Cursor"
        updateCurrentTitle(label)
        _ = sleepWhileUserStillIdle(0.28)
    }

    private func performActivateSlack() {
        let target = SwitchAppTarget(
            bundleIdentifier: SlackActivity.runningBundleID ?? SlackActivity.bundleID,
            displayName: "Slack",
            selectedWindowTitles: []
        )
        let label = AppSwitching.activate(target) ?? "Focus Slack"
        updateCurrentTitle(label)
        _ = sleepWhileUserStillIdle(0.28)
    }

    private func performActivateClaude() {
        let target = SwitchAppTarget(
            bundleIdentifier: ClaudeActivity.runningBundleID ?? ClaudeActivity.bundleID,
            displayName: "Claude",
            selectedWindowTitles: []
        )
        let label = AppSwitching.activate(target) ?? "Focus Claude"
        updateCurrentTitle(label)
        _ = sleepWhileUserStillIdle(0.28)
    }

    /// Move around Slack. Never types into the composer and never presses Return.
    private func performSlack(
        move: SlackMove,
        switching: Bool,
        settings: EngineSnapshot,
        human: inout Humanization
    ) {
        guard settings.slackModeEnabled, SlackActivity.isFrontmost() else { return }
        let layout = SlackActivity.layout()
        switch move {
        case .channel:
            if switching, settings.slackSwitchChats {
                if Bool.random(), let point = layout?.channelPoint() {
                    _ = moveAndClick(point, settings: settings, human: &human)
                } else {
                    let down = Bool.random()
                    keyboard.playChord(
                        KeyChord(
                            modifiers: [.leftOption],
                            key: down ? .downArrow : .upArrow,
                            holdMs: 40,
                            gap: 0.22,
                            label: down ? "⌥↓ (next chat)" : "⌥↑ (previous chat)"
                        ),
                        inject: makeInject(),
                        isCancelled: makeCancel()
                    )
                }
                if shouldAbortPlayback() { return }
            }
            if settings.slackScroll, let point = layout?.channelPoint() {
                scrollSlack(at: point, settings: settings, human: &human)
            }
        case .messages:
            if let point = layout?.messagePoint() {
                scrollSlack(at: point, settings: settings, human: &human)
            }
        case .thread:
            if let point = layout?.messagePoint() {
                _ = moveAndClick(point, settings: settings, human: &human)
                if shouldAbortPlayback() { return }
                if sleepWhileUserStillIdle(0.28) { return }
            }
            keyboard.playChord(
                KeyChord(modifiers: [], key: .rightArrow, holdMs: 40, gap: 0.2, label: "→ (open thread)"),
                inject: makeInject(),
                isCancelled: makeCancel()
            )
            if shouldAbortPlayback() { return }
            if sleepWhileUserStillIdle(0.35) { return }
            if settings.slackScroll, let point = layout?.threadPoint() {
                scrollSlack(at: point, settings: settings, human: &human)
            }
        case .closeThread:
            keyboard.playChord(
                KeyChord(
                    modifiers: [.leftCommand],
                    key: .period,
                    holdMs: 45,
                    gap: 0.2,
                    label: "⌘. (close thread)"
                ),
                inject: makeInject(),
                isCancelled: makeCancel()
            )
        case .search:
            keyboard.playChord(
                KeyChord(
                    modifiers: [.leftCommand],
                    key: .g,
                    holdMs: 45,
                    gap: 0.25,
                    label: "⌘G (search)"
                ),
                inject: makeInject(),
                isCancelled: makeCancel()
            )
            if shouldAbortPlayback() { return }
            if sleepWhileUserStillIdle(0.85) { return }
            keyboard.play(
                sequence: [(key: .escape, holdMs: 35, gap: 0.16)],
                inject: makeInject(),
                abortCharactersIfEditing: false,
                isCancelled: makeCancel()
            )
        case .workspace:
            guard settings.slackOrganizations else { return }
            keyboard.playChord(
                KeyChord(
                    modifiers: [.leftControl],
                    key: .tab,
                    holdMs: 50,
                    gap: 0.28,
                    label: "⌃Tab (next organization)"
                ),
                inject: makeInject(),
                isCancelled: makeCancel()
            )
        }
    }

    private func scrollSlack(
        at point: CGPoint,
        settings: EngineSnapshot,
        human: inout Humanization
    ) {
        let path = human.mousePath(to: point, profile: settings.profile)
        let arrived = path.isEmpty
            ? true
            : mouse.play(path: path, inject: makeInject(), isCancelled: makeCancel())
        if shouldAbortPlayback() || !arrived { return }
        let ticks = human.readingScrollTicks(
            profile: settings.profile,
            intensity: settings.scrollIntensity,
            axes: settings.scrollAxes
        )
        mouse.playScroll(ticks: ticks, inject: makeInject(), isCancelled: makeCancel())
    }

    /// Work inside Cursor. Never types, never presses Return/Tab, never accepts an edit,
    /// and never sends panel/chat chords (⌘⇧[ ⌘⇧] ⌥⌘← ⌥⌘→ cycle panel tabs or fork/pin chats).
    /// Returns true when a tab-level switch (file open / terminal focus) actually happened.
    @discardableResult
    private func performCursor(
        surface: CursorSurface,
        switchTabs: Bool,
        settings: EngineSnapshot,
        human: inout Humanization
    ) -> Bool {
        guard settings.cursorModeEnabled, CursorActivity.isFrontmost() else { return false }
        func isAllowed(_ candidate: CursorSurface) -> Bool {
            switch candidate {
            case .editor: return settings.cursorEditorTabs
            case .terminal: return settings.cursorTerminalTabs
            case .chat: return settings.cursorChatTabs
            case .agent: return settings.cursorAgentMode
            }
        }
        guard isAllowed(surface) else { return false }

        var surface = surface
        var switchTabs = switchTabs
        let layout = CursorActivity.layout()
        if !layout.has(surface) {
            let fallback = [CursorSurface.agent, .chat, .terminal, .editor].first { candidate in
                layout.has(candidate) && isAllowed(candidate)
            }
            guard let fallback else { return false }
            surface = fallback
            updateCurrentTitle(surface.eventTitle(switching: switchTabs))
        }
        let region = layout.interactionRect(for: surface)

        // Chat and Agent are scroll-only. Files / Terminal "switching" is rate-limited
        // by the tab-switch timer; when it is not due, just click a line / scroll.
        if switchTabs {
            switch surface {
            case .editor, .terminal:
                if !state.claimTabSwitchIfDue() {
                    switchTabs = false
                    updateCurrentTitle(surface.eventTitle(switching: false))
                }
            case .chat, .agent:
                switchTabs = false
            }
        }
        let didSwitch = switchTabs

        if surface == .editor {
            if switchTabs {
                updateCurrentTitle("Cursor · Files · open")
                revealAndOpenExplorerFile(settings: settings, human: &human)
                if shouldAbortPlayback() { return didSwitch }
            } else {
                updateCurrentTitle("Cursor · Files · line")
            }
            let clickedLine = clickEditorLine(settings: settings, human: &human)
            if shouldAbortPlayback() || !clickedLine { return didSwitch }
            guard region != nil else { return didSwitch }
            let ticks = human.readingScrollTicks(
                profile: settings.profile,
                intensity: settings.scrollIntensity,
                axes: settings.scrollAxes
            )
            mouse.playScroll(ticks: ticks, inject: makeInject(), isCancelled: makeCancel())
            return didSwitch
        }

        guard let region else { return didSwitch }

        // Terminal: click deep in the body (below the Problems / Debug / Terminal tab strip).
        if surface == .terminal, switchTabs {
            let point = CGPoint(
                x: region.minX + region.width * CGFloat.random(in: 0.2...0.8),
                y: region.minY + region.height * CGFloat.random(in: 0.45...0.9)
            )
            let clicked = moveAndClick(point, settings: settings, human: &human)
            if shouldAbortPlayback() || !clicked { return didSwitch }
            if sleepWhileUserStillIdle(0.25) { return didSwitch }
        }

        let path = human.mousePath(into: region, profile: settings.profile)
        let arrived = path.isEmpty
            ? CursorActivity.cursorIsInside(region)
            : mouse.play(path: path, inject: makeInject(), isCancelled: makeCancel())
        if shouldAbortPlayback() || !arrived { return didSwitch }
        let ticks = human.readingScrollTicks(
            profile: settings.profile,
            intensity: settings.scrollIntensity,
            axes: settings.scrollAxes
        )
        mouse.playScroll(ticks: ticks, inject: makeInject(), isCancelled: makeCancel())
        return didSwitch
    }

    /// Move around Claude desktop. Panels are located by label wherever they are.
    /// Never types, never presses Return, never sends. Chat is scroll-only; Terminal,
    /// Files, and Changes may take one body click when the tab-switch timer allows it.
    /// Returns true when a click-level switch actually happened.
    @discardableResult
    private func performClaude(
        surface: ClaudeSurface,
        switching: Bool,
        settings: EngineSnapshot,
        human: inout Humanization
    ) -> Bool {
        guard settings.claudeModeEnabled, ClaudeActivity.isFrontmost() else { return false }
        func isAllowed(_ candidate: ClaudeSurface) -> Bool {
            switch candidate {
            case .chat: return settings.claudeChat
            case .terminal: return settings.claudeTerminal
            case .files: return settings.claudeFiles
            case .changes: return settings.claudeChanges
            }
        }
        guard isAllowed(surface) else { return false }

        var surface = surface
        var switching = switching
        let layout = ClaudeActivity.layout()
        if !layout.has(surface) {
            let fallback = ClaudeSurface.allCases.first { layout.has($0) && isAllowed($0) }
            guard let fallback else { return false }
            surface = fallback
            updateCurrentTitle(surface.eventTitle(switching: switching))
        }
        if switching {
            if surface == .chat || !state.claimTabSwitchIfDue() {
                switching = false
                updateCurrentTitle(surface.eventTitle(switching: false))
            }
        }
        guard let region = layout.interactionRect(for: surface) else { return false }

        if switching, let point = layout.clickPoint(for: surface) {
            let clicked = moveAndClick(point, settings: settings, human: &human)
            if shouldAbortPlayback() || !clicked { return switching }
            if sleepWhileUserStillIdle(0.3) { return switching }
        }

        let path = human.mousePath(into: region, profile: settings.profile)
        let arrived = path.isEmpty
            ? ClaudeActivity.cursorIsInside(region)
            : mouse.play(path: path, inject: makeInject(), isCancelled: makeCancel())
        if shouldAbortPlayback() || !arrived { return switching }
        let ticks = human.readingScrollTicks(
            profile: settings.profile,
            intensity: settings.scrollIntensity,
            axes: settings.scrollAxes
        )
        mouse.playScroll(ticks: ticks, inject: makeInject(), isCancelled: makeCancel())
        return switching
    }

    /// Show the Explorer if it is hidden, then single-click a file so it opens.
    private func revealAndOpenExplorerFile(
        settings: EngineSnapshot,
        human: inout Humanization
    ) {
        var point = CursorActivity.explorerFilePoint()
        if point == nil {
            keyboard.playChord(
                KeyChord(
                    modifiers: [.leftShift, .leftCommand],
                    key: .e,
                    holdMs: 48,
                    gap: 0.16,
                    label: "⇧⌘E (Explorer)"
                ),
                inject: makeInject(),
                isCancelled: makeCancel()
            )
            if shouldAbortPlayback() { return }
            if sleepWhileUserStillIdle(0.4) { return }
            CursorActivity.invalidateLayout()
            point = CursorActivity.explorerFilePoint()
        }
        guard let point else { return }
        _ = moveAndClick(point, settings: settings, human: &human)
        _ = sleepWhileUserStillIdle(0.45)
    }

    /// One click on a line in the open file. Does not type.
    private func clickEditorLine(
        settings: EngineSnapshot,
        human: inout Humanization
    ) -> Bool {
        guard let point = CursorActivity.editorLinePoint() else { return false }
        return moveAndClick(point, settings: settings, human: &human)
    }

    private func moveAndClick(
        _ point: CGPoint,
        settings: EngineSnapshot,
        human: inout Humanization
    ) -> Bool {
        let path = human.mousePath(to: point, profile: settings.profile)
        let slop = CGRect(x: point.x - 22, y: point.y - 16, width: 44, height: 32)
        let arrived = path.isEmpty
            ? CursorActivity.cursorIsInside(slop)
            : mouse.play(path: path, inject: makeInject(), isCancelled: makeCancel())
        guard arrived, !shouldAbortPlayback() else { return false }
        mouse.click(inject: makeInject())
        return !shouldAbortPlayback()
    }

    /// Activate only user-selected apps/windows (fullscreen / other Spaces included).
    private func performRestrictedNavigation(
        settings: EngineSnapshot,
        human: inout Humanization
    ) {
        let targets = settings.switchTargets
        guard !targets.isEmpty else { return }

        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        var pool = targets
        if targets.count > 1, let frontID {
            let others = targets.filter { $0.bundleIdentifier != frontID }
            if !others.isEmpty { pool = others }
        }
        guard let target = pool.randomElement() else { return }

        var label = "Switch to \(target.displayName)"
        label = AppSwitching.activate(target) ?? label
        updateCurrentTitle(label)
        _ = human
    }

    private func performTabSwitch(
        settings: EngineSnapshot,
        human: inout Humanization
    ) {
        let chord = human.browserTabChord()
        updateCurrentTitle(chord.label)
        keyboard.playChord(
            chord,
            inject: makeInject(),
            isCancelled: makeCancel()
        )
        _ = settings
    }

    /// Idle-ignore for synthetic input; always runs `body` even if engine is tearing down.
    private func makeInject() -> ( () -> Void ) -> Void {
        { [weak self] body in
            if let self {
                self.playIgnoring(body)
            } else {
                body()
            }
        }
    }

    private func makeCancel() -> () -> Bool {
        { [weak self] in self?.shouldAbortPlayback() ?? true }
    }

    // MARK: - Activity stream

    private func beginEvent(_ kind: ActivityKind, _ title: String) {
        beginEvent(ActivityEvent(kind: kind, title: title))
    }

    private func beginEvent(_ event: ActivityEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let current = self.currentEvent {
                self.pastEvents.append(current)
                if self.pastEvents.count > 12 {
                    self.pastEvents.removeFirst(self.pastEvents.count - 12)
                }
            }
            self.currentEvent = event
            self.lastActionDescription = event.title
            self.lastActionDate = Date()
            self.secondsSinceLastAction = 0
        }
    }

    private func updateCurrentTitle(_ title: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let current = self.currentEvent {
                self.currentEvent = ActivityEvent(id: current.id, kind: current.kind, title: title, createdAt: current.createdAt)
            }
            self.lastActionDescription = title
            self.lastActionDate = Date()
            self.secondsSinceLastAction = 0
        }
    }

    private func popUpcoming() -> ActivityEvent? {
        DispatchQueue.main.sync {
            guard !upcomingEvents.isEmpty else { return nil }
            return upcomingEvents.removeFirst()
        }
    }

    private func clearUpcoming() {
        DispatchQueue.main.sync {
            upcomingEvents = []
        }
    }

    private func refillUpcoming(
        settings: EngineSnapshot,
        rhythm: WorkRhythm,
        human: inout Humanization
    ) {
        let need = DispatchQueue.main.sync { max(0, 4 - upcomingEvents.count) }
        guard need > 0 else { return }
        var planned: [ActivityEvent] = []
        planned.reserveCapacity(need)
        for _ in 0..<need {
            planned.append(planEvent(settings: settings, rhythm: rhythm, human: &human))
        }
        DispatchQueue.main.sync {
            upcomingEvents.append(contentsOf: planned)
        }
    }

    private enum DedicatedApp {
        case cursor, slack, claude

        var focusTitle: String {
            switch self {
            case .cursor: return CursorActivity.focusEventTitle
            case .slack: return SlackActivity.focusEventTitle
            case .claude: return ClaudeActivity.focusEventTitle
            }
        }
    }

    private func planEvent(
        settings: EngineSnapshot,
        rhythm: WorkRhythm,
        human: inout Humanization
    ) -> ActivityEvent {
        let cursorRunning = settings.cursorModeEnabled && CursorActivity.isRunning
        let slackRunning = settings.slackModeEnabled && SlackActivity.isRunning
        let claudeRunning = settings.claudeModeEnabled && ClaudeActivity.isRunning
        let cursorFront = cursorRunning && CursorActivity.isFrontmost()
        let slackFront = slackRunning && SlackActivity.isFrontmost()
        let claudeFront = claudeRunning && ClaudeActivity.isFrontmost()
        let cursorBundle = CursorActivity.runningBundleID ?? CursorActivity.bundleID
        let slackBundle = SlackActivity.runningBundleID ?? SlackActivity.bundleID
        let claudeBundle = ClaudeActivity.runningBundleID ?? ClaudeActivity.bundleID
        let otherTargets = settings.switchTargets.filter {
            $0.bundleIdentifier != cursorBundle
                && $0.bundleIdentifier != CursorActivity.bundleID
                && $0.bundleIdentifier != slackBundle
                && $0.bundleIdentifier != SlackActivity.bundleID
                && $0.bundleIdentifier != claudeBundle
                && $0.bundleIdentifier != ClaudeActivity.bundleID
        }
        let dedicatedFront = cursorFront || slackFront || claudeFront
        // While a dedicated app is in front, only the switch timer leaves it.
        let allowKeys = settings.includeKeyboard && !dedicatedFront
        var consumedSwitch = false

        var runningApps: [DedicatedApp] = []
        if cursorRunning { runningApps.append(.cursor) }
        if slackRunning { runningApps.append(.slack) }
        if claudeRunning { runningApps.append(.claude) }
        func share(of app: DedicatedApp) -> Double {
            switch app {
            case .cursor: return settings.cursorTimeShare
            case .slack: return settings.slackTimeShare
            case .claude: return settings.claudeTimeShare
            }
        }
        let frontApp: DedicatedApp? = cursorFront ? .cursor : (slackFront ? .slack : (claudeFront ? .claude : nil))

        // App switches happen ONLY when the scheduled switch timer is due.
        // Time share controls how often we *return* to Cursor/Slack/Claude when elsewhere —
        // it must NOT keep us parked in Claude past min/max switch interval.
        if !runningApps.isEmpty, state.isSwitchDue() {
            if let frontApp {
                // Timer fired while in a dedicated app → leave if there is anywhere to go.
                let otherDedicated = runningApps.filter { $0 != frontApp }
                let canLeave = settings.allowAppNavigation
                    && (!otherDedicated.isEmpty || !otherTargets.isEmpty)
                if canLeave, state.claimSwitchIfDue() {
                    consumedSwitch = true
                    if let other = otherDedicated.randomElement() {
                        return ActivityEvent(kind: .appSwitch, title: other.focusTitle)
                    }
                    if let name = otherTargets.randomElement()?.displayName {
                        return ActivityEvent(kind: .appSwitch, title: "Switch → \(name)")
                    }
                }
            } else if state.claimSwitchIfDue() {
                consumedSwitch = true
                let bestShare = runningApps.map(share(of:)).max() ?? 0.7
                let goDedicated = otherTargets.isEmpty
                    || !settings.allowAppNavigation
                    || Double.random(in: 0...1) < bestShare
                if goDedicated, let app = runningApps.randomElement() {
                    return ActivityEvent(kind: .appSwitch, title: app.focusTitle)
                }
                if let name = otherTargets.randomElement()?.displayName {
                    return ActivityEvent(kind: .appSwitch, title: "Switch → \(name)")
                }
            }
        }

        if slackFront {
            var enabled: [SlackMove] = []
            if settings.slackSwitchChats { enabled.append(.channel) }
            if settings.slackScroll {
                enabled.append(.messages)
                if !settings.slackSwitchChats { enabled.append(.channel) }
            }
            if settings.slackThreads {
                enabled.append(.thread)
                enabled.append(.closeThread)
            }
            if settings.slackSearch { enabled.append(.search) }
            if settings.slackOrganizations { enabled.append(.workspace) }
            if Double.random(in: 0...1) < 0.9, let plan = human.planSlackMove(enabled: enabled) {
                return ActivityEvent(
                    kind: .slack,
                    title: plan.move.eventTitle(switching: plan.switching)
                )
            }
        }

        if claudeFront {
            let panes = ClaudeActivity.layout()
            var enabled: [ClaudeSurface] = []
            if settings.claudeChat, panes.has(.chat) { enabled.append(.chat) }
            if settings.claudeTerminal, panes.has(.terminal) { enabled.append(.terminal) }
            if settings.claudeFiles, panes.has(.files) { enabled.append(.files) }
            if settings.claudeChanges, panes.has(.changes) { enabled.append(.changes) }
            if Double.random(in: 0...1) < 0.86, let plan = human.planClaudeAction(enabled: enabled) {
                return ActivityEvent(
                    kind: .claude,
                    title: plan.surface.eventTitle(switching: plan.switching)
                )
            }
        }

        if cursorFront {
            let panes = CursorActivity.layout()
            var enabled: [CursorSurface] = []
            if settings.cursorEditorTabs, panes.has(.editor) { enabled.append(.editor) }
            if settings.cursorTerminalTabs, panes.has(.terminal) { enabled.append(.terminal) }
            if settings.cursorChatTabs, panes.has(.chat) { enabled.append(.chat) }
            if settings.cursorAgentMode, panes.has(.agent) { enabled.append(.agent) }
            if Double.random(in: 0...1) < 0.86, let plan = human.planCursorAction(enabled: enabled) {
                return ActivityEvent(
                    kind: .cursor,
                    title: plan.surface.eventTitle(switching: plan.switchTabs)
                )
            }
        }

        if !consumedSwitch,
           settings.allowAppNavigation,
           !settings.switchTargets.isEmpty,
           state.claimSwitchIfDue()
        {
            let name = settings.switchTargets.randomElement()?.displayName ?? "app"
            return ActivityEvent(kind: .appSwitch, title: "Switch → \(name)")
        }

        // Browser chords stay out of Cursor, Slack, and Claude. ⌘1–9 there focuses editor groups.
        // Tab switches are rate-limited by the tab-switch timer; not due means skip the event.
        if !dedicatedFront, settings.allowTabSwitching {
            let tabChance: Double
            if settings.adaptiveRhythmsEnabled {
                tabChance = rhythm.weights.tabSwitch * (0.6 + settings.intensity * 0.6)
            } else {
                tabChance = 0.18 + settings.intensity * 0.12
            }
            if Double.random(in: 0...1) < tabChance, state.claimTabSwitchIfDue() {
                return ActivityEvent(kind: .tabSwitch, title: "Browser tab")
            }
        }

        if settings.adaptiveRhythmsEnabled {
            let w = rhythm.weights
            let roll = Double.random(in: 0...1)
            let mouseThreshold = w.mouse
            let scrollThreshold = mouseThreshold + w.scroll
            let keyboardThreshold = scrollThreshold + w.keyboard

            if roll < mouseThreshold {
                return ActivityEvent(kind: .mouse, title: "Mouse move")
            }
            if roll < scrollThreshold {
                return ActivityEvent(kind: .scroll, title: "Scroll")
            }
            if roll < keyboardThreshold, allowKeys {
                if settings.allowCharacterKeys {
                    return ActivityEvent(kind: .keyboard, title: settings.naturalTypingEnabled ? "Typing" : "Key taps")
                }
                return ActivityEvent(kind: .silentKeys, title: "Silent keys")
            }
            return ActivityEvent(kind: .mouse, title: "Mouse move")
        }

        let roll = Double.random(in: 0...1)

        if roll < 0.48 {
            return ActivityEvent(kind: .mouse, title: "Mouse move")
        }
        if roll < 0.62 {
            return ActivityEvent(kind: .mouse, title: "Mouse jitter")
        }
        if roll < 0.62 + settings.profile.scrollProbability * 0.45 {
            return ActivityEvent(kind: .scroll, title: "Scroll")
        }
        if allowKeys,
           Double.random(in: 0...1) < settings.profile.keyboardProbability * (0.5 + settings.intensity * 0.5)
        {
            if settings.allowCharacterKeys {
                return ActivityEvent(kind: .keyboard, title: settings.naturalTypingEnabled ? "Typing" : "Key taps")
            }
            return ActivityEvent(kind: .silentKeys, title: "Silent keys")
        }
        _ = human
        return ActivityEvent(kind: .mouse, title: "Mouse move")
    }

    /// Wait until the user has been idle for the current debounce setting.
    /// Re-reads `idleDebounceSeconds` live so slider changes apply without Stop/Start.
    /// Returns true if cancelled.
    private func waitForUserIdle() -> Bool {
        var lastAnnounced = -1
        while !state.cancelFlag {
            let required = Int(state.idleDebounceSeconds)
            if required != lastAnnounced {
                lastAnnounced = required
                beginEvent(.waiting, "Waiting \(required)s idle…")
            }
            let idle = idleMonitor.secondsSinceUserActivity
            if idle >= state.idleDebounceSeconds {
                return false
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }

    /// Sleep up to `interval`, returning early if the user becomes active or cancel is set.
    @discardableResult
    private func sleepWhileUserStillIdle(_ interval: TimeInterval) -> Bool {
        let slices = max(1, Int(interval / 0.05))
        let slice = interval / Double(slices)
        for _ in 0..<slices {
            if state.cancelFlag { return true }
            if idleMonitor.secondsSinceUserActivity < 0.35 { return true }
            Thread.sleep(forTimeInterval: slice)
        }
        return state.cancelFlag
    }

    private func setPhase(_ phase: EnginePhase) {
        DispatchQueue.main.async { [weak self] in
            self?.phase = phase
        }
    }

    private func markActionCompleted() {
        DispatchQueue.main.async { [weak self] in
            self?.actionsCompleted += 1
        }
    }

    // MARK: - Global hotkeys

    /// Install system-wide hotkey monitor: Control-Shift-U Start, Control-Shift-K Stop, Control-Shift-0 Emergency Stop.
    private func installGlobalHotkeys() {
        guard globalHotkeyMonitor == nil else { return }
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCtrlShift = flags == [.control, .shift]
            guard isCtrlShift else { return }

            switch event.keyCode {
            case 32: // U
                DispatchQueue.main.async {
                    if !self.isRunning { self.start() }
                }
            case 40: // K
                DispatchQueue.main.async {
                    if self.isRunning { self.stop() }
                }
            case 29: // 0
                self.emergencyStop()
            default:
                break
            }
        }
    }

    /// Remove global hotkey monitor.
    private func removeGlobalHotkeys() {
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalHotkeyMonitor = nil
        }
    }

    /// Instantly kill all activity, release keys, and quit the app.
    func emergencyStop() {
        state.cancelFlag = true
        worker?.cancel()
        worker = nil
        device.releaseAllKeys()
        device.stop()
        idleMonitor.stop()
        DispatchQueue.main.async {
            self.isRunning = false
            self.phase = .stopped
            self.removeGlobalHotkeys()
            AppAppearance.allowFullQuit = true
            NSApp.terminate(nil)
        }
    }

    deinit {
        removeGlobalHotkeys()
    }

}

/// Frozen copy of the settings the worker plans and performs with.
/// Captured when the engine starts — changes apply on the next Start.
struct EngineSnapshot {
    var profile: ActivityProfile
    var intensity: Double
    var idleDebounceSeconds: Double
    var includeKeyboard: Bool
    var allowCharacterKeys: Bool
    var allowAppNavigation: Bool
    var switchTargets: [SwitchAppTarget]
    var switchIntervalMinSeconds: Double
    var switchIntervalMaxSeconds: Double
    var tabSwitchIntervalMinSeconds: Double
    var scrollIntensity: Double
    var scrollAxes: ScrollAxisMode
    var allowTabSwitching: Bool
    var tabSwitchScope: TabSwitchScope
    var microBreaksEnabled: Bool
    var microBreakFrequency: MicroBreakFrequency
    var adaptiveRhythmsEnabled: Bool
    var keyboardWPM: Double
    var naturalTypingEnabled: Bool
    var primaryDisplayOnly: Bool
    var cursorModeEnabled: Bool
    var cursorTimeShare: Double
    var cursorEditorTabs: Bool
    var cursorTerminalTabs: Bool
    var cursorChatTabs: Bool
    var cursorAgentMode: Bool
    var slackModeEnabled: Bool
    var slackTimeShare: Double
    var slackSwitchChats: Bool
    var slackSearch: Bool
    var slackScroll: Bool
    var slackThreads: Bool
    var slackOrganizations: Bool
    var claudeModeEnabled: Bool
    var claudeTimeShare: Double
    var claudeChat: Bool
    var claudeTerminal: Bool
    var claudeFiles: Bool
    var claudeChanges: Bool
}

/// Thread-safe settings/cancel flag shared with the worker thread.
final class EngineState: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelFlag = false
    private var _profile: ActivityProfile = .office
    private var _intensity: Double = 0.65
    private var _idleDebounceSeconds: Double = 20
    private var _includeKeyboard = true
    private var _allowCharacterKeys = false
    private var _allowAppNavigation = true
    private var _switchTargets: [SwitchAppTarget] = []
    private var _switchIntervalMinSeconds: Double = 45
    private var _switchIntervalMaxSeconds: Double = 180
    private var _tabSwitchIntervalMinSeconds: Double = 40
    private var _scrollIntensity: Double = 0.35
    private var _scrollAxes: ScrollAxisMode = .both
    private var _allowTabSwitching = true
    private var _tabSwitchScope: TabSwitchScope = .browsersOnly
    private var _microBreaksEnabled = true
    private var _microBreakFrequency: MicroBreakFrequency = .standard
    private var _adaptiveRhythmsEnabled = true
    private var _keyboardWPM: Double = 40
    private var _naturalTypingEnabled = true
    private var _primaryDisplayOnly = false
    private var _cursorModeEnabled = true
    private var _cursorTimeShare: Double = 0.7
    private var _cursorEditorTabs = true
    private var _cursorTerminalTabs = true
    private var _cursorChatTabs = true
    private var _cursorAgentMode = true
    private var _slackModeEnabled = true
    private var _slackTimeShare: Double = 0.7
    private var _slackSwitchChats = true
    private var _slackSearch = true
    private var _slackScroll = true
    private var _slackThreads = true
    private var _slackOrganizations = false
    private var _claudeModeEnabled = true
    private var _claudeTimeShare: Double = 0.7
    private var _claudeChat = true
    private var _claudeTerminal = true
    private var _claudeFiles = true
    private var _claudeChanges = true
    private var _nextSwitchDate = Date()
    private var _nextTabSwitchDate = Date()

    var cancelFlag: Bool {
        get { lock.withLock { _cancelFlag } }
        set { lock.withLock { _cancelFlag = newValue } }
    }

    var profile: ActivityProfile {
        get { lock.withLock { _profile } }
        set { lock.withLock { _profile = newValue } }
    }

    var intensity: Double {
        get { lock.withLock { _intensity } }
        set { lock.withLock { _intensity = newValue } }
    }

    var idleDebounceSeconds: Double {
        get { lock.withLock { _idleDebounceSeconds } }
        set { lock.withLock { _idleDebounceSeconds = newValue } }
    }

    var includeKeyboard: Bool {
        get { lock.withLock { _includeKeyboard } }
        set { lock.withLock { _includeKeyboard = newValue } }
    }

    var allowCharacterKeys: Bool {
        get { lock.withLock { _allowCharacterKeys } }
        set { lock.withLock { _allowCharacterKeys = newValue } }
    }

    var allowAppNavigation: Bool {
        get { lock.withLock { _allowAppNavigation } }
        set { lock.withLock { _allowAppNavigation = newValue } }
    }

    var switchTargets: [SwitchAppTarget] {
        get { lock.withLock { _switchTargets } }
        set { lock.withLock { _switchTargets = newValue } }
    }

    var switchIntervalMinSeconds: Double {
        get { lock.withLock { _switchIntervalMinSeconds } }
        set { lock.withLock { _switchIntervalMinSeconds = newValue } }
    }

    var switchIntervalMaxSeconds: Double {
        get { lock.withLock { _switchIntervalMaxSeconds } }
        set { lock.withLock { _switchIntervalMaxSeconds = newValue } }
    }

    var tabSwitchIntervalMinSeconds: Double {
        get { lock.withLock { _tabSwitchIntervalMinSeconds } }
        set { lock.withLock { _tabSwitchIntervalMinSeconds = newValue } }
    }

    var scrollIntensity: Double {
        get { lock.withLock { _scrollIntensity } }
        set { lock.withLock { _scrollIntensity = newValue } }
    }

    var scrollAxes: ScrollAxisMode {
        get { lock.withLock { _scrollAxes } }
        set { lock.withLock { _scrollAxes = newValue } }
    }

    var allowTabSwitching: Bool {
        get { lock.withLock { _allowTabSwitching } }
        set { lock.withLock { _allowTabSwitching = newValue } }
    }

    var tabSwitchScope: TabSwitchScope {
        get { lock.withLock { _tabSwitchScope } }
        set { lock.withLock { _tabSwitchScope = newValue } }
    }

    var microBreaksEnabled: Bool {
        get { lock.withLock { _microBreaksEnabled } }
        set { lock.withLock { _microBreaksEnabled = newValue } }
    }

    var microBreakFrequency: MicroBreakFrequency {
        get { lock.withLock { _microBreakFrequency } }
        set { lock.withLock { _microBreakFrequency = newValue } }
    }

    var adaptiveRhythmsEnabled: Bool {
        get { lock.withLock { _adaptiveRhythmsEnabled } }
        set { lock.withLock { _adaptiveRhythmsEnabled = newValue } }
    }

    var keyboardWPM: Double {
        get { lock.withLock { _keyboardWPM } }
        set { lock.withLock { _keyboardWPM = newValue } }
    }

    var naturalTypingEnabled: Bool {
        get { lock.withLock { _naturalTypingEnabled } }
        set { lock.withLock { _naturalTypingEnabled = newValue } }
    }

    var primaryDisplayOnly: Bool {
        get { lock.withLock { _primaryDisplayOnly } }
        set { lock.withLock { _primaryDisplayOnly = newValue } }
    }

    var cursorModeEnabled: Bool {
        get { lock.withLock { _cursorModeEnabled } }
        set { lock.withLock { _cursorModeEnabled = newValue } }
    }

    var cursorTimeShare: Double {
        get { lock.withLock { _cursorTimeShare } }
        set { lock.withLock { _cursorTimeShare = newValue } }
    }

    var cursorEditorTabs: Bool {
        get { lock.withLock { _cursorEditorTabs } }
        set { lock.withLock { _cursorEditorTabs = newValue } }
    }

    var cursorTerminalTabs: Bool {
        get { lock.withLock { _cursorTerminalTabs } }
        set { lock.withLock { _cursorTerminalTabs = newValue } }
    }

    var cursorChatTabs: Bool {
        get { lock.withLock { _cursorChatTabs } }
        set { lock.withLock { _cursorChatTabs = newValue } }
    }

    var cursorAgentMode: Bool {
        get { lock.withLock { _cursorAgentMode } }
        set { lock.withLock { _cursorAgentMode = newValue } }
    }

    var slackModeEnabled: Bool {
        get { lock.withLock { _slackModeEnabled } }
        set { lock.withLock { _slackModeEnabled = newValue } }
    }

    var slackTimeShare: Double {
        get { lock.withLock { _slackTimeShare } }
        set { lock.withLock { _slackTimeShare = newValue } }
    }

    var slackSwitchChats: Bool {
        get { lock.withLock { _slackSwitchChats } }
        set { lock.withLock { _slackSwitchChats = newValue } }
    }

    var slackSearch: Bool {
        get { lock.withLock { _slackSearch } }
        set { lock.withLock { _slackSearch = newValue } }
    }

    var slackScroll: Bool {
        get { lock.withLock { _slackScroll } }
        set { lock.withLock { _slackScroll = newValue } }
    }

    var slackThreads: Bool {
        get { lock.withLock { _slackThreads } }
        set { lock.withLock { _slackThreads = newValue } }
    }

    var slackOrganizations: Bool {
        get { lock.withLock { _slackOrganizations } }
        set { lock.withLock { _slackOrganizations = newValue } }
    }

    var claudeModeEnabled: Bool {
        get { lock.withLock { _claudeModeEnabled } }
        set { lock.withLock { _claudeModeEnabled = newValue } }
    }

    var claudeTimeShare: Double {
        get { lock.withLock { _claudeTimeShare } }
        set { lock.withLock { _claudeTimeShare = newValue } }
    }

    var claudeChat: Bool {
        get { lock.withLock { _claudeChat } }
        set { lock.withLock { _claudeChat = newValue } }
    }

    var claudeTerminal: Bool {
        get { lock.withLock { _claudeTerminal } }
        set { lock.withLock { _claudeTerminal = newValue } }
    }

    var claudeFiles: Bool {
        get { lock.withLock { _claudeFiles } }
        set { lock.withLock { _claudeFiles = newValue } }
    }

    var claudeChanges: Bool {
        get { lock.withLock { _claudeChanges } }
        set { lock.withLock { _claudeChanges = newValue } }
    }

    func isSwitchDue() -> Bool {
        lock.withLock { Date() >= _nextSwitchDate }
    }

    /// If a switch is due, schedule the next one immediately and return true.
    /// Prevents the upcoming queue from stacking multiple switches in one burst.
    @discardableResult
    func claimSwitchIfDue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard Date() >= _nextSwitchDate else { return false }
        scheduleNextSwitchLocked()
        return true
    }

    func scheduleNextSwitch() {
        lock.lock()
        defer { lock.unlock() }
        scheduleNextSwitchLocked()
    }

    private func scheduleNextSwitchLocked() {
        let lo = min(_switchIntervalMinSeconds, _switchIntervalMaxSeconds)
        let hi = max(_switchIntervalMinSeconds, _switchIntervalMaxSeconds)
        let wait = Double.random(in: lo...max(lo, hi))
        _nextSwitchDate = Date().addingTimeInterval(wait)
    }

    /// If a tab switch is due, schedule the next one and return true.
    /// Gates browser tabs, Cursor file opens, and Claude panel clicks.
    @discardableResult
    func claimTabSwitchIfDue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard Date() >= _nextTabSwitchDate else { return false }
        scheduleNextTabSwitchLocked()
        return true
    }

    func scheduleNextTabSwitch() {
        lock.lock()
        defer { lock.unlock() }
        scheduleNextTabSwitchLocked()
    }

    private func scheduleNextTabSwitchLocked() {
        let lo = max(1, _tabSwitchIntervalMinSeconds)
        let wait = Double.random(in: lo...(lo * 1.6))
        _nextTabSwitchDate = Date().addingTimeInterval(wait)
    }

    func snapshot() -> EngineSnapshot {
        lock.withLock {
            EngineSnapshot(
                profile: _profile,
                intensity: _intensity,
                idleDebounceSeconds: _idleDebounceSeconds,
                includeKeyboard: _includeKeyboard,
                allowCharacterKeys: _allowCharacterKeys,
                allowAppNavigation: _allowAppNavigation,
                switchTargets: _switchTargets,
                switchIntervalMinSeconds: _switchIntervalMinSeconds,
                switchIntervalMaxSeconds: _switchIntervalMaxSeconds,
                tabSwitchIntervalMinSeconds: _tabSwitchIntervalMinSeconds,
                scrollIntensity: _scrollIntensity,
                scrollAxes: _scrollAxes,
                allowTabSwitching: _allowTabSwitching,
                tabSwitchScope: _tabSwitchScope,
                microBreaksEnabled: _microBreaksEnabled,
                microBreakFrequency: _microBreakFrequency,
                adaptiveRhythmsEnabled: _adaptiveRhythmsEnabled,
                keyboardWPM: _keyboardWPM,
                naturalTypingEnabled: _naturalTypingEnabled,
                primaryDisplayOnly: _primaryDisplayOnly,
                cursorModeEnabled: _cursorModeEnabled,
                cursorTimeShare: _cursorTimeShare,
                cursorEditorTabs: _cursorEditorTabs,
                cursorTerminalTabs: _cursorTerminalTabs,
                cursorChatTabs: _cursorChatTabs,
                cursorAgentMode: _cursorAgentMode,
                slackModeEnabled: _slackModeEnabled,
                slackTimeShare: _slackTimeShare,
                slackSwitchChats: _slackSwitchChats,
                slackSearch: _slackSearch,
                slackScroll: _slackScroll,
                slackThreads: _slackThreads,
                slackOrganizations: _slackOrganizations,
                claudeModeEnabled: _claudeModeEnabled,
                claudeTimeShare: _claudeTimeShare,
                claudeChat: _claudeChat,
                claudeTerminal: _claudeTerminal,
                claudeFiles: _claudeFiles,
                claudeChanges: _claudeChanges
            )
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
