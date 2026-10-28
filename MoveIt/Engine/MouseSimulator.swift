import Foundation
import AppKit
import CoreGraphics

final class MouseSimulator {
    private let device: VirtualHIDDevice

    init(device: VirtualHIDDevice) {
        self.device = device
    }

    /// Plays a relative path. Aborts immediately on cancel, or if the real cursor
    /// drifts far from the expected position (user grabbed the mouse mid-move).
    /// Only the HID injection itself should be wrapped by `inject` (idle ignore);
    /// sleeps stay outside so real user input can interrupt.
    /// Returns false when playback stops early (cancel or the real cursor moved).
    @discardableResult
    func play(
        path: [(dx: Int, dy: Int, delay: TimeInterval)],
        inject: ( () -> Void ) -> Void = { $0() },
        isCancelled: () -> Bool
    ) -> Bool {
        if path.isEmpty { return !isCancelled() }
        var expected = cursorPoint()

        for step in path {
            if isCancelled() { return false }
            if cursorDrifted(from: expected, tolerance: 28) { return false }

            if step.dx != 0 || step.dy != 0 {
                inject {
                    self.device.moveBy(dx: step.dx, dy: step.dy)
                }
                // Quartz Y grows upward; NSEvent.mouseLocation matches that.
                expected.x += CGFloat(step.dx)
                expected.y -= CGFloat(step.dy)
            }

            if sleepInterruptible(step.delay, isCancelled: isCancelled) { return false }
            if cursorDrifted(from: expected, tolerance: 28) { return false }
        }
        return !isCancelled()
    }

    func click(inject: ( () -> Void ) -> Void = { $0() }) {
        inject {
            self.device.click()
        }
    }

    func playScroll(
        ticks: [(dx: Int, dy: Int, delay: TimeInterval)],
        inject: ( () -> Void ) -> Void = { $0() },
        isCancelled: () -> Bool
    ) {
        for tick in ticks {
            if isCancelled() { return }
            inject {
                self.device.scroll(dx: tick.dx, dy: tick.dy)
            }
            if sleepInterruptible(tick.delay, isCancelled: isCancelled) { return }
        }
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

    private func cursorPoint() -> CGPoint {
        NSEvent.mouseLocation
    }

    private func cursorDrifted(from expected: CGPoint, tolerance: CGFloat) -> Bool {
        let now = cursorPoint()
        let dx = now.x - expected.x
        let dy = now.y - expected.y
        return (dx * dx + dy * dy) > (tolerance * tolerance)
    }
}
