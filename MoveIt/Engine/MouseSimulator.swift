import Foundation

final class MouseSimulator {
    private let device: VirtualHIDDevice

    init(device: VirtualHIDDevice) {
        self.device = device
    }

    func play(
        path: [(dx: Int, dy: Int, delay: TimeInterval)],
        isCancelled: () -> Bool
    ) {
        for step in path {
            if isCancelled() { return }
            if step.dx != 0 || step.dy != 0 {
                device.moveBy(dx: step.dx, dy: step.dy)
            }
            sleep(step.delay)
        }
    }

    func playScroll(
        ticks: [(dy: Int, delay: TimeInterval)],
        isCancelled: () -> Bool
    ) {
        for tick in ticks {
            if isCancelled() { return }
            device.scroll(dy: tick.dy)
            sleep(tick.delay)
        }
    }

    private func sleep(_ interval: TimeInterval) {
        if interval <= 0 { return }
        Thread.sleep(forTimeInterval: interval)
    }
}
