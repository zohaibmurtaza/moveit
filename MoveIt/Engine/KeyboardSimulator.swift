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

    func play(
        sequence: [(key: SafeHIDKey, holdMs: UInt64, gap: TimeInterval)],
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
            device.tap(event.key, holdMilliseconds: event.holdMs)
            if event.gap > 0 {
                Thread.sleep(forTimeInterval: event.gap)
            }
        }
        device.releaseAllKeys()
    }

    func playChord(_ chord: KeyChord, isCancelled: () -> Bool) {
        if isCancelled() {
            device.releaseAllKeys()
            return
        }
        device.tapChord(
            modifiers: chord.modifiers,
            key: chord.key,
            holdMilliseconds: chord.holdMs
        )
        if chord.gap > 0 {
            Thread.sleep(forTimeInterval: chord.gap)
        }
        device.releaseAllKeys()
    }
}
