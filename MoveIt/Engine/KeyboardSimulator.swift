import Foundation

struct KeyChord {
    var modifiers: [SafeHIDKey]
    var key: SafeHIDKey
    var holdMs: UInt64
    var gap: TimeInterval
    var label: String
}

final class KeyboardSimulator {
    private let device: VirtualHIDDevice

    init(device: VirtualHIDDevice) {
        self.device = device
    }

    /// Plays key taps. Wrap only the HID/CG injection with `inject` so idle
    /// monitoring still sees real user input between keys.
    func play(
        sequence: [(key: SafeHIDKey, holdMs: UInt64, gap: TimeInterval)],
        inject: ( () -> Void ) -> Void = { $0() },
        abortCharactersIfEditing: Bool = false,
        isCancelled: () -> Bool
    ) {
        for event in sequence {
            if isCancelled() {
                device.releaseAllKeys()
                return
            }
            if abortCharactersIfEditing,
               !event.key.isModifier,
               FocusSafety.isEditingText
            {
                device.releaseAllKeys()
                return
            }
            inject {
                self.device.tap(event.key, holdMilliseconds: event.holdMs)
            }
            if sleepInterruptible(event.gap, isCancelled: isCancelled) {
                device.releaseAllKeys()
                return
            }
        }
        device.releaseAllKeys()
    }

    func playChord(
        _ chord: KeyChord,
        inject: ( () -> Void ) -> Void = { $0() },
        isCancelled: () -> Bool
    ) {
        if isCancelled() {
            device.releaseAllKeys()
            return
        }
        inject {
            self.device.tapChord(
                modifiers: chord.modifiers,
                key: chord.key,
                holdMilliseconds: chord.holdMs
            )
        }
        if sleepInterruptible(chord.gap, isCancelled: isCancelled) {
            device.releaseAllKeys()
            return
        }
        device.releaseAllKeys()
    }

    @discardableResult
    private func sleepInterruptible(_ interval: TimeInterval, isCancelled: () -> Bool) -> Bool {
        guard interval > 0 else { return isCancelled() }
        let slice: TimeInterval = 0.015
        var remaining = interval
        while remaining > 0 {
            if isCancelled() { return true }
            let step = min(slice, remaining)
            Thread.sleep(forTimeInterval: step)
            remaining -= step
        }
        return isCancelled()
    }
}
