import Foundation
import CoreGraphics
import AppKit

enum ActivityProfile: String, CaseIterable, Identifiable {
    case subtle = "Subtle"
    case office = "Office"
    case intensive = "Intensive"

    var id: String { rawValue }

    /// Short explanation shown under the profile picker.
    var detail: String {
        switch self {
        case .subtle:
            return "Slow pace, shorter moves, longer pauses — looks lightly active."
        case .office:
            return "Typical desk rhythm — mixed moves, scrolls, and pauses."
        case .intensive:
            return "Busy pace — longer travels, shorter gaps, more frequent actions."
        }
    }

    /// Intensity preset applied when the user picks this profile.
    var presetIntensity: Double {
        switch self {
        case .subtle: return 0.35
        case .office: return 0.65
        case .intensive: return 0.90
        }
    }

    /// Relative activity density 0...1
    var density: Double {
        switch self {
        case .subtle: return 0.28
        case .office: return 0.55
        case .intensive: return 0.85
        }
    }

    /// Chance a burst includes keyboard activity (when keyboard mode is enabled)
    var keyboardProbability: Double {
        switch self {
        case .subtle: return 0.20
        case .office: return 0.30
        case .intensive: return 0.40
        }
    }

    /// Chance a burst includes scroll
    var scrollProbability: Double {
        switch self {
        case .subtle: return 0.20
        case .office: return 0.35
        case .intensive: return 0.40
        }
    }
}

struct Point2D: Equatable {
    var x: Double
    var y: Double

    static let zero = Point2D(x: 0, y: 0)

    func distance(to other: Point2D) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}

/// Generates human-like relative mouse deltas, idle gaps, and key rhythms.
struct Humanization {
    private var rng = SystemRandomNumberGenerator()

    mutating func nextIdleGap(profile: ActivityProfile, intensity: Double) -> TimeInterval {
        // Log-normal gaps: lots of short pauses, occasional long "thinking" pauses.
        let baseMean: Double
        let sigma: Double
        switch profile {
        case .subtle:
            baseMean = 4.5
            sigma = 0.85
        case .office:
            baseMean = 2.2
            sigma = 0.70
        case .intensive:
            baseMean = 1.1
            sigma = 0.55
        }

        let intensityFactor = max(0.25, 1.35 - intensity)
        let mean = baseMean * intensityFactor
        let sample = exp(logNormal(mu: log(mean), sigma: sigma))
        return min(max(sample, 0.15), 45.0)
    }

    mutating func burstLength(profile: ActivityProfile, intensity: Double = 0.65) -> Int {
        let weights: [Int]
        switch profile {
        case .subtle: weights = [1, 1, 2, 2, 3]
        case .office: weights = [2, 3, 3, 4, 5, 6]
        case .intensive: weights = [3, 4, 5, 6, 7, 8, 9]
        }
        let base = weights.randomElement(using: &rng) ?? 3
        // Intensity stretches burst size so 10-minute activity totals drift more.
        let scaled = Int((Double(base) * (0.45 + intensity * 1.05)).rounded())
        return max(1, scaled)
    }

    /// Screen-aware relative path: targets stay inside the visible frame so the
    /// cursor does not grind along a display edge.
    mutating func mousePath(
        distanceHint: Double,
        profile: ActivityProfile
    ) -> [(dx: Int, dy: Int, delay: TimeInterval)] {
        let current = cursorCGPoint()
        let inset = activeVisibleInset(margin: 56)
        let start = Point2D(x: current.x, y: current.y)

        // If already near/outside the safe inset, pull toward the center first.
        let center = Point2D(x: inset.midX, y: inset.midY)
        let distance = max(8, distanceHint * Double.random(in: 0.55...1.45, using: &rng))

        var end = pickTarget(from: start, distance: distance, inset: inset, center: center)

        // Occasional overshoot then correction — still clamped inside inset.
        var samples: [Point2D] = bezierSamples(from: start, to: end, profile: profile)
        if start.distance(to: end) > 40, Double.random(in: 0...1, using: &rng) < 0.35 {
            let overshoot = Point2D(
                x: end.x + (end.x - start.x) * Double.random(in: 0.04...0.12, using: &rng),
                y: end.y + (end.y - start.y) * Double.random(in: 0.04...0.12, using: &rng)
            )
            samples.append(clamp(overshoot, to: inset))
            samples.append(end)
        }

        return deltas(from: samples, profile: profile)
    }

    mutating func localJitterPath(profile: ActivityProfile) -> [(dx: Int, dy: Int, delay: TimeInterval)] {
        let current = cursorCGPoint()
        let inset = activeVisibleInset(margin: 40)
        let nearEdge = !inset.contains(current)

        let count = Int.random(in: 3...8, using: &rng)
        var events: [(dx: Int, dy: Int, delay: TimeInterval)] = []
        for _ in 0..<count {
            var dx = Int.random(in: -3...3, using: &rng)
            var dy = Int.random(in: -3...3, using: &rng)
            if nearEdge {
                // Bias jitter toward the center when parked on an edge.
                let center = CGPoint(x: inset.midX, y: inset.midY)
                if current.x < inset.minX + 8 { dx = abs(dx) + 2 }
                if current.x > inset.maxX - 8 { dx = -abs(dx) - 2 }
                if current.y < inset.minY + 8 { dy = abs(dy) + 2 }
                if current.y > inset.maxY - 8 { dy = -abs(dy) - 2 }
                _ = center
            }
            guard dx != 0 || dy != 0 else { continue }
            let delay = Double.random(in: 0.012...0.055, using: &rng)
            events.append((dx, dy, delay))
        }
        if profile == .subtle, events.count > 4 {
            events = Array(events.prefix(4))
        }
        return events
    }

    mutating func scrollTicks(profile: ActivityProfile) -> [(dy: Int, delay: TimeInterval)] {
        let count = Int.random(in: 1...3, using: &rng)
        let direction = Bool.random(using: &rng) ? 1 : -1
        return (0..<count).map { _ in
            let dy = direction * Int.random(in: 1...2, using: &rng)
            let delay = Double.random(in: 0.05...0.18, using: &rng)
            return (dy, delay)
        }
    }

    /// Silent by default (quiet modifiers). Optional character/number/arrow pool.
    mutating func keySequence(
        profile: ActivityProfile,
        allowCharacters: Bool
    ) -> [(key: SafeHIDKey, holdMs: UInt64, gap: TimeInterval)] {
        let pool: [SafeHIDKey]
        if allowCharacters {
            let roll = Double.random(in: 0...1, using: &rng)
            if roll < 0.55 {
                pool = SafeHIDKey.letterKeys
            } else if roll < 0.78 {
                pool = SafeHIDKey.numberKeys
            } else if roll < 0.92 {
                pool = SafeHIDKey.navigationKeys
            } else {
                pool = SafeHIDKey.quietActivityKeys
            }
        } else {
            pool = SafeHIDKey.quietActivityKeys
        }

        let length: Int
        switch profile {
        case .subtle: length = Int.random(in: 1...2, using: &rng)
        case .office: length = Int.random(in: 1...3, using: &rng)
        case .intensive: length = Int.random(in: 2...4, using: &rng)
        }

        return (0..<length).map { _ in
            let key = pool.randomElement(using: &rng) ?? .leftShift
            let hold = UInt64.random(in: 28...70, using: &rng)
            let gap = Double.random(in: 0.06...0.28, using: &rng)
            return (key, hold, gap)
        }
    }

    /// App / window / browser-tab switching chords.
    mutating func navigationChord(profile: ActivityProfile) -> KeyChord {
        let roll = Double.random(in: 0...1, using: &rng)
        let hold = UInt64.random(in: 35...70, using: &rng)
        let gap = Double.random(in: 0.15...0.45, using: &rng)

        // Weight toward browser tabs; occasional app / window switch.
        if roll < 0.50 {
            let reverse = Bool.random(using: &rng)
            return KeyChord(
                modifiers: reverse ? [.leftControl, .leftShift] : [.leftControl],
                key: .tab,
                holdMs: hold,
                gap: gap,
                label: reverse ? "⌃⇧Tab (prev tab)" : "⌃Tab (next tab)"
            )
        }
        if roll < 0.78 {
            return KeyChord(
                modifiers: [.leftCommand],
                key: .tab,
                holdMs: hold,
                gap: gap,
                label: "⌘Tab (switch app)"
            )
        }
        // Same-app window cycle (works in many apps including Chrome).
        let reverseWindow = profile != .subtle && Bool.random(using: &rng)
        return KeyChord(
            modifiers: reverseWindow ? [.leftCommand, .leftShift] : [.leftCommand],
            key: .grave,
            holdMs: hold,
            gap: gap,
            label: reverseWindow ? "⌘⇧` (prev window)" : "⌘` (next window)"
        )
    }

    mutating func travelDistance(profile: ActivityProfile) -> Double {
        switch profile {
        case .subtle:
            return Double.random(in: 12...90, using: &rng)
        case .office:
            return Double.random(in: 40...280, using: &rng)
        case .intensive:
            return Double.random(in: 60...420, using: &rng)
        }
    }

    // MARK: - Screen-aware helpers

    private func cursorCGPoint() -> CGPoint {
        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: location.x, y: screenHeight - location.y)
    }

    private func activeVisibleInset(margin: CGFloat) -> CGRect {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? visible.maxY
        // Convert AppKit bottom-left visibleFrame → CG top-left space.
        let cgVisible = CGRect(
            x: visible.origin.x,
            y: screenHeight - visible.origin.y - visible.height,
            width: visible.width,
            height: visible.height
        )
        return cgVisible.insetBy(dx: margin, dy: margin)
    }

    private mutating func pickTarget(
        from start: Point2D,
        distance: Double,
        inset: CGRect,
        center: Point2D
    ) -> Point2D {
        let safeStart = clamp(start, to: inset)

        // Outside / near edge → head toward center with some wander.
        if !inset.insetBy(dx: 12, dy: 12).contains(CGPoint(x: start.x, y: start.y)) {
            let pull = Point2D(
                x: center.x + Double.random(in: -inset.width * 0.2...inset.width * 0.2, using: &rng),
                y: center.y + Double.random(in: -inset.height * 0.2...inset.height * 0.2, using: &rng)
            )
            return clamp(pull, to: inset)
        }

        // Prefer angles that keep the destination inside the inset; retry a few times.
        for _ in 0..<8 {
            let angle = Double.random(in: 0...(2 * Double.pi), using: &rng)
            let candidate = Point2D(
                x: safeStart.x + cos(angle) * distance,
                y: safeStart.y + sin(angle) * distance
            )
            if inset.contains(CGPoint(x: candidate.x, y: candidate.y)) {
                return candidate
            }
        }

        // Fallback: move toward center by up to `distance`.
        let dx = center.x - safeStart.x
        let dy = center.y - safeStart.y
        let len = max(hypot(dx, dy), 1)
        let scale = min(distance, len) / len
        return clamp(Point2D(x: safeStart.x + dx * scale, y: safeStart.y + dy * scale), to: inset)
    }

    private func clamp(_ point: Point2D, to inset: CGRect) -> Point2D {
        Point2D(
            x: min(max(point.x, inset.minX), inset.maxX),
            y: min(max(point.y, inset.minY), inset.maxY)
        )
    }

    private mutating func bezierSamples(
        from start: Point2D,
        to end: Point2D,
        profile: ActivityProfile
    ) -> [Point2D] {
        let chord = Point2D(x: end.x - start.x, y: end.y - start.y)
        let distance = max(start.distance(to: end), 1)
        let perp = Point2D(x: -chord.y, y: chord.x)
        let perpLen = max(perp.distance(to: .zero), 1)
        let bend = Double.random(in: -0.45...0.45, using: &rng) * distance
        let c1Scale = Double.random(in: 0.2...0.45, using: &rng)
        let c2Scale = Double.random(in: 0.55...0.85, using: &rng)
        let c1 = Point2D(
            x: start.x + chord.x * c1Scale + (perp.x / perpLen) * bend * 0.6,
            y: start.y + chord.y * c1Scale + (perp.y / perpLen) * bend * 0.6
        )
        let c2 = Point2D(
            x: start.x + chord.x * c2Scale + (perp.x / perpLen) * bend,
            y: start.y + chord.y * c2Scale + (perp.y / perpLen) * bend
        )

        let steps = stepCount(for: distance, profile: profile)
        var samples: [Point2D] = [start]
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            samples.append(cubicBezier(t: easeInOut(t), p0: start, p1: c1, p2: c2, p3: end))
        }
        return samples
    }

    private mutating func deltas(
        from samples: [Point2D],
        profile: ActivityProfile
    ) -> [(dx: Int, dy: Int, delay: TimeInterval)] {
        var events: [(dx: Int, dy: Int, delay: TimeInterval)] = []
        var previous = samples.first ?? .zero
        let distance = samples.first?.distance(to: samples.last ?? previous) ?? 0
        let baseInterval = travelInterval(for: distance, profile: profile)

        for (index, point) in samples.enumerated() where index > 0 {
            var dx = point.x - previous.x
            var dy = point.y - previous.y

            if Double.random(in: 0...1, using: &rng) < 0.22 {
                dx += Double.random(in: -0.8...0.8, using: &rng)
                dy += Double.random(in: -0.8...0.8, using: &rng)
            }

            previous = point
            let progress = Double(index) / Double(max(samples.count - 1, 1))
            let speedMod = 0.65 + 0.7 * sin(progress * Double.pi)
            let jitter = Double.random(in: 0.75...1.30, using: &rng)
            let delay = max(0.004, baseInterval * speedMod * jitter)

            let chunks = chunkDeltas(dx: dx, dy: dy)
            for chunk in chunks {
                events.append((chunk.dx, chunk.dy, delay / Double(max(chunks.count, 1))))
            }
        }
        return events
    }

    // MARK: - Math helpers

    private mutating func logNormal(mu: Double, sigma: Double) -> Double {
        let u1 = Double.random(in: 0.0001...1, using: &rng)
        let u2 = Double.random(in: 0.0001...1, using: &rng)
        let z = sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2)
        return mu + sigma * z
    }

    private func cubicBezier(t: Double, p0: Point2D, p1: Point2D, p2: Point2D, p3: Point2D) -> Point2D {
        let u = 1 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        return Point2D(
            x: uuu * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + ttt * p3.x,
            y: uuu * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + ttt * p3.y
        )
    }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    private func stepCount(for distance: Double, profile: ActivityProfile) -> Int {
        let base = Int(distance / 6.0)
        switch profile {
        case .subtle: return min(max(base, 6), 28)
        case .office: return min(max(base, 10), 48)
        case .intensive: return min(max(base, 14), 64)
        }
    }

    private func travelInterval(for distance: Double, profile: ActivityProfile) -> TimeInterval {
        let id = log2(distance / 8.0 + 1)
        switch profile {
        case .subtle: return 0.014 + id * 0.0025
        case .office: return 0.010 + id * 0.0020
        case .intensive: return 0.007 + id * 0.0015
        }
    }

    private func chunkDeltas(dx: Double, dy: Double) -> [(dx: Int, dy: Int)] {
        var remainingX = dx
        var remainingY = dy
        var chunks: [(dx: Int, dy: Int)] = []
        while abs(remainingX) > 0.5 || abs(remainingY) > 0.5 {
            let stepX = Int(clampingTo127(remainingX))
            let stepY = Int(clampingTo127(remainingY))
            if stepX == 0 && stepY == 0 { break }
            chunks.append((stepX, stepY))
            remainingX -= Double(stepX)
            remainingY -= Double(stepY)
            if chunks.count > 40 { break }
        }
        return chunks
    }

    private func clampingTo127(_ value: Double) -> Int {
        min(127, max(-127, Int(value.rounded())))
    }
}
