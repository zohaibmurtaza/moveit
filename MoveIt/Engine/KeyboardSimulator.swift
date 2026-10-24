import Foundation

final class KeyboardSimulator {
    private let device: VirtualHIDDevice

    init(device: VirtualHIDDevice) {
        self.device = device
    }

    func play(
        sequence: [(key: SafeHIDKey, holdMs: UInt64, gap: TimeInterval)],
        isCancelled: () -> Bool
    ) {
        for event in sequence {
            if isCancelled() {
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
}
