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
    /// Minimum seconds between app/window switches.
    @Published var switchIntervalMinSeconds: Double = 45 {
        didSet {
            let clamped = min(switchIntervalMaxSeconds, max(10, switchIntervalMinSeconds))
            if clamped != switchIntervalMinSeconds {
                switchIntervalMinSeconds = clamped
                return
            }
            UserDefaults.standard.set(switchIntervalMinSeconds, forKey: Keys.switchIntervalMin)
            state.switchIntervalMinSeconds = switchIntervalMinSeconds
        }
    }
    /// Maximum seconds between app/window switches.
    @Published var switchIntervalMaxSeconds: Double = 180 {
        didSet {
            let clamped = max(switchIntervalMinSeconds, min(900, switchIntervalMaxSeconds))
            if clamped != switchIntervalMaxSeconds {
                switchIntervalMaxSeconds = clamped
                return
            }
            UserDefaults.standard.set(switchIntervalMaxSeconds, forKey: Keys.switchIntervalMax)
            state.switchIntervalMaxSeconds = switchIntervalMaxSeconds
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
        state.profile = profile
        state.intensity = effectiveIntensity
        state.idleDebounceSeconds = idleDebounceSeconds
        state.includeKeyboard = includeKeyboard
        state.allowCharacterKeys = allowCharacterKeys
        state.allowAppNavigation = allowAppNavigation
        state.switchTargets = switchTargets
        state.switchIntervalMinSeconds = switchIntervalMinSeconds
        state.switchIntervalMaxSeconds = switchIntervalMaxSeconds
        state.scheduleNextSwitch()
    }

    func start() {
        guard !isRunning else { return }
        state.cancelFlag = false
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
        publishSettingsToState()

        let thread = Thread { [weak self] in
            self?.runLoop()
        }
        thread.name = "MoveIt.ActivityEngine"
        thread.qualityOfService = .userInitiated
        worker = thread
        thread.start()
    }

    func stop() {
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
    }

    private func startUITicker() {
        uiTicker?.invalidate()
        uiTicker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.isRunning else { return }
                self.resampleEffectiveIntensityIfNeeded()
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

        while !state.cancelFlag {
            // Worker-side period check (UI ticker also updates on main).
            if Date().timeIntervalSince(intensityPeriodStartedAt) >= intensityPeriodSeconds {
                DispatchQueue.main.sync { [weak self] in
                    self?.resampleEffectiveIntensity(force: true)
                }
            }

            let settings = state.snapshot()

            setPhase(.waitingForIdle)
            beginEvent(.waiting, "Waiting \(Int(settings.idleDebounceSeconds))s idle…")
            refillUpcoming(settings: settings, human: &human)

            if waitForUserIdle(seconds: settings.idleDebounceSeconds) { break }
            if state.cancelFlag { break }

            setPhase(.simulating)
            let burstCount = human.burstLength(profile: settings.profile, intensity: settings.intensity)
            for _ in 0..<burstCount {
                if state.cancelFlag { break }
                // User touched input again — yield and re-arm debounce.
                if idleMonitor.secondsSinceUserActivity < 0.35 {
                    break
                }

                refillUpcoming(settings: settings, human: &human)
                let next = popUpcoming() ?? planEvent(settings: settings, human: &human)

                switch next.kind {
                case .appSwitch:
                    beginEvent(next)
                    performRestrictedNavigation(settings: settings, human: &human)
                    state.scheduleNextSwitch()
                case .mouse:
                    beginEvent(next)
                    let distance = human.travelDistance(profile: settings.profile)
                        * (0.6 + settings.intensity * 0.8)
                    let path = human.mousePath(distanceHint: distance, profile: settings.profile)
                    playIgnoring { [weak self] in
                        guard let self else { return }
                        self.mouse.play(path: path, isCancelled: { [state = self.state] in state.cancelFlag })
                    }
                case .scroll:
                    beginEvent(next)
                    let ticks = human.scrollTicks(profile: settings.profile)
                    playIgnoring { [weak self] in
                        guard let self else { return }
                        self.mouse.playScroll(ticks: ticks, isCancelled: { [state = self.state] in state.cancelFlag })
                    }
                case .keyboard, .silentKeys:
                    beginEvent(next)
                    let editing = FocusSafety.isEditingText
                    let useCharacters = next.kind == .keyboard && !editing
                    if next.kind == .keyboard && editing {
                        beginEvent(.skipped, "Skipped characters (text focused)")
                        let sequence = human.keySequence(profile: settings.profile, allowCharacters: false)
                        playIgnoring { [weak self] in
                            guard let self else { return }
                            self.keyboard.play(
                                sequence: sequence,
                                abortCharactersIfEditing: true,
                                isCancelled: { [state = self.state] in state.cancelFlag }
                            )
                        }
                    } else {
                        let sequence = human.keySequence(
                            profile: settings.profile,
                            allowCharacters: useCharacters
                        )
                        playIgnoring { [weak self] in
                            guard let self else { return }
                            self.keyboard.play(
                                sequence: sequence,
                                abortCharactersIfEditing: useCharacters,
                                isCancelled: { [state = self.state] in state.cancelFlag }
                            )
                        }
                    }
                case .waiting, .skipped:
                    beginEvent(next)
                }

                if sleepCancellable(Double.random(in: 0.08...0.45)) { break }
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

    /// Activate only user-selected apps/windows; ⌃Tab only inside allow-listed browsers.
    private func performRestrictedNavigation(
        settings: (
            profile: ActivityProfile,
            intensity: Double,
            idleDebounceSeconds: Double,
            includeKeyboard: Bool,
            allowCharacterKeys: Bool,
            allowAppNavigation: Bool,
            switchTargets: [SwitchAppTarget],
            switchIntervalMinSeconds: Double,
            switchIntervalMaxSeconds: Double
        ),
        human: inout Humanization
    ) {
        let targets = settings.switchTargets
        // Prefer browser tab chords when already in an allow-listed browser.
        if settings.includeKeyboard,
           AppSwitching.frontmostIsBrowser(in: targets),
           Double.random(in: 0...1) < 0.45
        {
            let reverse = Bool.random()
            let label = reverse ? "⌃⇧Tab (prev tab)" : "⌃Tab (next tab)"
            let chord = KeyChord(
                modifiers: reverse ? [.leftControl, .leftShift] : [.leftControl],
                key: .tab,
                holdMs: UInt64.random(in: 35...70),
                gap: Double.random(in: 0.12...0.35),
                label: label
            )
            updateCurrentTitle(label)
            playIgnoring { [weak self] in
                guard let self else { return }
                self.keyboard.playChord(chord, isCancelled: { [state = self.state] in state.cancelFlag })
            }
            return
        }

        // Otherwise activate a different selected app/window (not global ⌘Tab).
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        var pool = targets
        if targets.count > 1, let frontID {
            let others = targets.filter { $0.bundleIdentifier != frontID }
            if !others.isEmpty { pool = others }
        }
        guard let target = pool.randomElement() else { return }

        var label = "Switch to \(target.displayName)"
        // Activation must run on main (AppSwitching does); don't wrap in playIgnoring's
        // ignore-activity alone — call activate directly so WindowServer sees it.
        label = AppSwitching.activate(target) ?? label
        updateCurrentTitle(label)
        _ = human
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

    private func refillUpcoming(
        settings: (
            profile: ActivityProfile,
            intensity: Double,
            idleDebounceSeconds: Double,
            includeKeyboard: Bool,
            allowCharacterKeys: Bool,
            allowAppNavigation: Bool,
            switchTargets: [SwitchAppTarget],
            switchIntervalMinSeconds: Double,
            switchIntervalMaxSeconds: Double
        ),
        human: inout Humanization
    ) {
        let need = DispatchQueue.main.sync { max(0, 4 - upcomingEvents.count) }
        guard need > 0 else { return }
        var planned: [ActivityEvent] = []
        planned.reserveCapacity(need)
        for _ in 0..<need {
            planned.append(planEvent(settings: settings, human: &human))
        }
        DispatchQueue.main.sync {
            upcomingEvents.append(contentsOf: planned)
        }
    }

    private func planEvent(
        settings: (
            profile: ActivityProfile,
            intensity: Double,
            idleDebounceSeconds: Double,
            includeKeyboard: Bool,
            allowCharacterKeys: Bool,
            allowAppNavigation: Bool,
            switchTargets: [SwitchAppTarget],
            switchIntervalMinSeconds: Double,
            switchIntervalMaxSeconds: Double
        ),
        human: inout Humanization
    ) -> ActivityEvent {
        let switchDue = settings.allowAppNavigation
            && !settings.switchTargets.isEmpty
            && state.isSwitchDue()
        let roll = Double.random(in: 0...1)

        if switchDue, roll < 0.55 {
            let name = settings.switchTargets.randomElement()?.displayName ?? "app"
            return ActivityEvent(kind: .appSwitch, title: "Switch → \(name)")
        }
        if roll < 0.55 {
            return ActivityEvent(kind: .mouse, title: "Mouse move")
        }
        if roll < 0.72 {
            return ActivityEvent(kind: .mouse, title: "Mouse jitter")
        }
        if roll < 0.72 + settings.profile.scrollProbability * 0.35 {
            return ActivityEvent(kind: .scroll, title: "Scroll")
        }
        if settings.includeKeyboard,
           Double.random(in: 0...1) < settings.profile.keyboardProbability * (0.5 + settings.intensity * 0.5)
        {
            if settings.allowCharacterKeys {
                return ActivityEvent(kind: .keyboard, title: "Key taps")
            }
            return ActivityEvent(kind: .silentKeys, title: "Silent keys")
        }
        // Fallback so the stream never stalls.
        _ = human
        return ActivityEvent(kind: .mouse, title: "Mouse move")
    }

    /// Returns true if cancelled.
    private func waitForUserIdle(seconds: TimeInterval) -> Bool {
        while !state.cancelFlag {
            let idle = idleMonitor.secondsSinceUserActivity
            if idle >= seconds {
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

    private func sleepCancellable(_ interval: TimeInterval) -> Bool {
        let slices = max(1, Int(interval / 0.05))
        let slice = interval / Double(slices)
        for _ in 0..<slices {
            if state.cancelFlag { return true }
            Thread.sleep(forTimeInterval: slice)
        }
        return state.cancelFlag
    }
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
    private var _nextSwitchDate = Date()

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

    func isSwitchDue() -> Bool {
        lock.withLock { Date() >= _nextSwitchDate }
    }

    func scheduleNextSwitch() {
        lock.lock()
        defer { lock.unlock() }
        let lo = min(_switchIntervalMinSeconds, _switchIntervalMaxSeconds)
        let hi = max(_switchIntervalMinSeconds, _switchIntervalMaxSeconds)
        let wait = Double.random(in: lo...max(lo, hi))
        _nextSwitchDate = Date().addingTimeInterval(wait)
    }

    func snapshot() -> (
        profile: ActivityProfile,
        intensity: Double,
        idleDebounceSeconds: Double,
        includeKeyboard: Bool,
        allowCharacterKeys: Bool,
        allowAppNavigation: Bool,
        switchTargets: [SwitchAppTarget],
        switchIntervalMinSeconds: Double,
        switchIntervalMaxSeconds: Double
    ) {
        lock.withLock {
            (
                _profile,
                _intensity,
                _idleDebounceSeconds,
                _includeKeyboard,
                _allowCharacterKeys,
                _allowAppNavigation,
                _switchTargets,
                _switchIntervalMinSeconds,
                _switchIntervalMaxSeconds
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
