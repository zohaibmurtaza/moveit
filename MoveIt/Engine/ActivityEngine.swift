import Foundation
import Combine

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
    @Published var profile: ActivityProfile = .office {
        didSet {
            UserDefaults.standard.set(profile.rawValue, forKey: Keys.profile)
            state.profile = profile
        }
    }
    @Published var intensity: Double = 0.65 {
        didSet {
            UserDefaults.standard.set(intensity, forKey: Keys.intensity)
            state.intensity = intensity
        }
    }
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
        static let idleDebounce = "moveit.idleDebounce"
    }

    init() {
        mouse = MouseSimulator(device: device)
        keyboard = KeyboardSimulator(device: device)

        if let raw = UserDefaults.standard.string(forKey: Keys.profile),
           let saved = ActivityProfile(rawValue: raw) {
            profile = saved
        } else {
            profile = .office
        }
        let savedIntensity = UserDefaults.standard.object(forKey: Keys.intensity) as? Double
        intensity = savedIntensity ?? 0.65
        let savedDebounce = UserDefaults.standard.object(forKey: Keys.idleDebounce) as? Double
        idleDebounceSeconds = savedDebounce ?? 20
        state.profile = profile
        state.intensity = intensity
        state.idleDebounceSeconds = idleDebounceSeconds
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
    }

    func publishSettingsToState() {
        state.profile = profile
        state.intensity = intensity
        state.idleDebounceSeconds = idleDebounceSeconds
    }

    private func startUITicker() {
        uiTicker?.invalidate()
        uiTicker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.isRunning else { return }
                self.publishSettingsToState()
                self.userIdleSeconds = Int(self.idleMonitor.secondsSinceUserActivity)
                if self.phase == .simulating {
                    self.secondsSinceLastAction = Int(Date().timeIntervalSince(self.lastActionDate))
                }
            }
        }
    }

    private func runLoop() {
        var human = Humanization()

        while !state.cancelFlag {
            let settings = state.snapshot()

            setPhase(.waitingForIdle)
            notify(action: "Waiting for \(Int(settings.idleDebounceSeconds))s idle…")

            if waitForUserIdle(seconds: settings.idleDebounceSeconds) { break }
            if state.cancelFlag { break }

            setPhase(.simulating)
            let burstCount = human.burstLength(profile: settings.profile)
            for _ in 0..<burstCount {
                if state.cancelFlag { break }
                // User touched input again — yield and re-arm debounce.
                if idleMonitor.secondsSinceUserActivity < 0.35 {
                    break
                }

                let roll = Double.random(in: 0...1)
                if roll < 0.55 {
                    let distance = human.travelDistance(profile: settings.profile)
                        * (0.6 + settings.intensity * 0.8)
                    let path = human.mousePath(distanceHint: distance, profile: settings.profile)
                    notify(action: "Mouse travel (\(path.count) pts)")
                    playIgnoring { [weak self] in
                        guard let self else { return }
                        self.mouse.play(path: path, isCancelled: { [state = self.state] in state.cancelFlag })
                    }
                } else if roll < 0.75 {
                    let path = human.localJitterPath(profile: settings.profile)
                    notify(action: "Mouse jitter")
                    playIgnoring { [weak self] in
                        guard let self else { return }
                        self.mouse.play(path: path, isCancelled: { [state = self.state] in state.cancelFlag })
                    }
                } else if roll < 0.75 + settings.profile.scrollProbability * 0.35 {
                    let ticks = human.scrollTicks(profile: settings.profile)
                    notify(action: "Scroll")
                    playIgnoring { [weak self] in
                        guard let self else { return }
                        self.mouse.playScroll(ticks: ticks, isCancelled: { [state = self.state] in state.cancelFlag })
                    }
                }

                if Double.random(in: 0...1)
                    < settings.profile.keyboardProbability * (0.5 + settings.intensity * 0.5)
                {
                    let sequence = human.keySequence(profile: settings.profile)
                    notify(action: "Key taps ×\(sequence.count)")
                    playIgnoring { [weak self] in
                        guard let self else { return }
                        self.keyboard.play(sequence: sequence, isCancelled: { [state = self.state] in state.cancelFlag })
                    }
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

    private func notify(action: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastActionDescription = action
            self?.lastActionDate = Date()
            self?.secondsSinceLastAction = 0
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

    func snapshot() -> (profile: ActivityProfile, intensity: Double, idleDebounceSeconds: Double) {
        lock.withLock { (_profile, _intensity, _idleDebounceSeconds) }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
