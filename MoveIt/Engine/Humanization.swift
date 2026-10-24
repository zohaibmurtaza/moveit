import Foundation
import CoreGraphics

enum ActivityProfile: String, CaseIterable, Identifiable {
    case subtle = "Subtle"
    case office = "Office"
    case intensive = "Intensive"

    var id: String { rawValue }

    /// Relative activity density 0...1
    var density: Double {
        switch self {
        case .subtle: return 0.28
        case .office: return 0.55
        case .intensive: return 0.85
        }
    }

    /// Chance a burst includes keyboard activity
    var keyboardProbability: Double {
        switch self {
        case .subtle: return 0.25
        case .office: return 0.45
        case .intensive: return 0.65
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

    mutating func burstLength(profile: ActivityProfile) -> Int {
        let weights: [Int]
        switch profile {
        case .subtle: weights = [1, 1, 2, 2, 3]
        case .office: weights = [2, 3, 3, 4, 5, 6]
        case .intensive: weights = [3, 4, 5, 6, 7, 8, 9]
        }
        return weights.randomElement(using: &rng) ?? 3
    }

    /// Relative path (sum of deltas) with Bezier shape, overshoot, and micro-tremor.
    mutating func mousePath(
        distanceHint: Double,
        profile: ActivityProfile
    ) -> [(dx: Int, dy: Int, delay: TimeInterval)] {
        let angle = Double.random(in: 0...(2 * Double.pi), using: &rng)
        let distance = max(8, distanceHint * Double.random(in: 0.55...1.45, using: &rng))
        let end = Point2D(x: cos(angle) * distance, y: sin(angle) * distance)

        // Control points offset perpendicular to the chord for natural curvature.
        let perp = Point2D(x: -end.y, y: end.x)
        let perpLen = max(perp.distance(to: .zero), 1)
        let bend = Double.random(in: -0.45...0.45, using: &rng) * distance
        let c1Scale = Double.random(in: 0.2...0.45, using: &rng)
        let c2Scale = Double.random(in: 0.55...0.85, using: &rng)
        let c1 = Point2D(
            x: end.x * c1Scale + (perp.x / perpLen) * bend * 0.6,
            y: end.y * c1Scale + (perp.y / perpLen) * bend * 0.6
        )
        let c2 = Point2D(
            x: end.x * c2Scale + (perp.x / perpLen) * bend,
            y: end.y * c2Scale + (perp.y / perpLen) * bend
        )

        let steps = stepCount(for: distance, profile: profile)
        var samples: [Point2D] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            samples.append(cubicBezier(t: easeInOut(t), p0: .zero, p1: c1, p2: c2, p3: end))
        }

        // Occasional overshoot then correction (Fitts-like).
        if distance > 40, Double.random(in: 0...1, using: &rng) < 0.35 {
            let overshoot = Point2D(
                x: end.x * Double.random(in: 1.04...1.12, using: &rng),
                y: end.y * Double.random(in: 1.04...1.12, using: &rng)
            )
            samples.append(overshoot)
            samples.append(end)
        }

        var events: [(dx: Int, dy: Int, delay: TimeInterval)] = []
        var previous = Point2D.zero
        let baseInterval = travelInterval(for: distance, profile: profile)

        for (index, point) in samples.enumerated() where index > 0 {
            var dx = point.x - previous.x
            var dy = point.y - previous.y

            // Micro-tremor
            if Double.random(in: 0...1, using: &rng) < 0.22 {
                dx += Double.random(in: -0.8...0.8, using: &rng)
                dy += Double.random(in: -0.8...0.8, using: &rng)
            }

            previous = point
            let progress = Double(index) / Double(max(samples.count - 1, 1))
            let speedMod = 0.65 + 0.7 * sin(progress * Double.pi) // slower at ends
            let jitter = Double.random(in: 0.75...1.30, using: &rng)
            let delay = max(0.004, baseInterval * speedMod * jitter)

            // Split large deltas into ±127 chunks for HID.
            for chunk in chunkDeltas(dx: dx, dy: dy) {
                events.append((chunk.dx, chunk.dy, delay / Double(max(chunkDeltas(dx: dx, dy: dy).count, 1))))
            }
        }

        return events
    }

    mutating func localJitterPath(profile: ActivityProfile) -> [(dx: Int, dy: Int, delay: TimeInterval)] {
        let count = Int.random(in: 3...8, using: &rng)
        var events: [(dx: Int, dy: Int, delay: TimeInterval)] = []
        for _ in 0..<count {
            let dx = Int.random(in: -3...3, using: &rng)
            let dy = Int.random(in: -3...3, using: &rng)
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

    mutating func keySequence(profile: ActivityProfile) -> [(key: SafeHIDKey, holdMs: UInt64, gap: TimeInterval)] {
        // Only letters, numbers, arrows, and bare modifiers — never F-keys / Esc / Page*
        // (those fire browser and system shortcuts, e.g. F7 → Caret Browsing).
        // Modifiers are tapped alone (not chorded), so ⌘C / ⌘Q never fire.
        let pool: [SafeHIDKey]
        let roll = Double.random(in: 0...1, using: &rng)
        if roll < 0.50 {
            pool = SafeHIDKey.letterKeys
        } else if roll < 0.70 {
            pool = SafeHIDKey.numberKeys
        } else if roll < 0.88 {
            pool = SafeHIDKey.navigationKeys
        } else {
            pool = SafeHIDKey.modifierKeys
        }

        let length: Int
        switch profile {
        case .subtle: length = Int.random(in: 1...3, using: &rng)
        case .office: length = Int.random(in: 2...5, using: &rng)
        case .intensive: length = Int.random(in: 3...7, using: &rng)
        }

        return (0..<length).map { _ in
            let key = pool.randomElement(using: &rng) ?? .a
            let hold = UInt64.random(in: 28...70, using: &rng)
            let gap = Double.random(in: 0.06...0.28, using: &rng)
            return (key, hold, gap)
        }
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

    // MARK: - Math helpers

    private mutating func logNormal(mu: Double, sigma: Double) -> Double {
        // Box-Muller
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
        // Rough Fitts-inspired: longer moves are faster mid-path but more samples.
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
