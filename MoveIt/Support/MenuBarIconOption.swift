import SwiftUI

/// Menu-bar status item artwork. Persisted via `AppStorage` / `UserDefaults`.
enum MenuBarIconOption: String, CaseIterable, Identifiable {
    case moveit
    // Pointer / input
    case cursor
    case mouse
    case keyboard
    case hand
    case finger
    case trackpad
    // Activity / motion
    case circle
    case square
    case bolt
    case sparkles
    case wave
    case pulse
    case activity
    case arrowUpDown
    case arrowLeftRight
    case play
    case pause
    case infinity
    // Time / status
    case clock
    case timer
    case hourglass
    case eye
    case eyeSlash
    case moon
    case sun
    // Nature / shapes
    case leaf
    case drop
    case flame
    case star
    case heart
    case diamond
    case hexagon
    case triangle
    // Work / desk
    case laptop
    case desktop
    case display
    case wifi
    case antenna
    case gear
    case slider
    case checklist
    case target
    case location
    case compass
    case paperplane
    case wand
    case paintbrush
    case lightbulb
    case lock
    case shield
    case bunny
    case tortoise
    case hare
    case cat
    case dog

    static let storageKey = "menuBarIcon"

    var id: String { rawValue }

    var isDefault: Bool { self == .moveit }

    var title: String {
        switch self {
        case .moveit: return "MoveIt"
        case .cursor: return "Cursor"
        case .mouse: return "Mouse"
        case .keyboard: return "Keyboard"
        case .hand: return "Hand"
        case .finger: return "Finger"
        case .trackpad: return "Trackpad"
        case .circle: return "Dot"
        case .square: return "Square"
        case .bolt: return "Bolt"
        case .sparkles: return "Sparkles"
        case .wave: return "Wave"
        case .pulse: return "Pulse"
        case .activity: return "Activity"
        case .arrowUpDown: return "Up/Down"
        case .arrowLeftRight: return "Left/Right"
        case .play: return "Play"
        case .pause: return "Pause"
        case .infinity: return "Infinity"
        case .clock: return "Clock"
        case .timer: return "Timer"
        case .hourglass: return "Hourglass"
        case .eye: return "Eye"
        case .eyeSlash: return "Hidden"
        case .moon: return "Moon"
        case .sun: return "Sun"
        case .leaf: return "Leaf"
        case .drop: return "Drop"
        case .flame: return "Flame"
        case .star: return "Star"
        case .heart: return "Heart"
        case .diamond: return "Diamond"
        case .hexagon: return "Hexagon"
        case .triangle: return "Triangle"
        case .laptop: return "Laptop"
        case .desktop: return "Desktop"
        case .display: return "Display"
        case .wifi: return "Wi‑Fi"
        case .antenna: return "Antenna"
        case .gear: return "Gear"
        case .slider: return "Sliders"
        case .checklist: return "Checklist"
        case .target: return "Target"
        case .location: return "Location"
        case .compass: return "Compass"
        case .paperplane: return "Plane"
        case .wand: return "Wand"
        case .paintbrush: return "Brush"
        case .lightbulb: return "Bulb"
        case .lock: return "Lock"
        case .shield: return "Shield"
        case .bunny: return "Bunny"
        case .tortoise: return "Tortoise"
        case .hare: return "Hare"
        case .cat: return "Cat"
        case .dog: return "Dog"
        }
    }

    private var systemImageName: String? {
        switch self {
        case .moveit: return nil
        case .cursor: return "cursorarrow"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .hand: return "hand.raised.fill"
        case .finger: return "hand.point.up.left.fill"
        case .trackpad: return "hand.draw.fill"
        case .circle: return "circle.fill"
        case .square: return "square.fill"
        case .bolt: return "bolt.fill"
        case .sparkles: return "sparkles"
        case .wave: return "waveform"
        case .pulse: return "waveform.path.ecg"
        case .activity: return "figure.walk"
        case .arrowUpDown: return "arrow.up.arrow.down"
        case .arrowLeftRight: return "arrow.left.arrow.right"
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .infinity: return "infinity"
        case .clock: return "clock"
        case .timer: return "timer"
        case .hourglass: return "hourglass"
        case .eye: return "eye.fill"
        case .eyeSlash: return "eye.slash.fill"
        case .moon: return "moon.fill"
        case .sun: return "sun.max.fill"
        case .leaf: return "leaf.fill"
        case .drop: return "drop.fill"
        case .flame: return "flame.fill"
        case .star: return "star.fill"
        case .heart: return "heart.fill"
        case .diamond: return "diamond.fill"
        case .hexagon: return "hexagon.fill"
        case .triangle: return "triangle.fill"
        case .laptop: return "laptopcomputer"
        case .desktop: return "desktopcomputer"
        case .display: return "display"
        case .wifi: return "wifi"
        case .antenna: return "antenna.radiowaves.left.and.right"
        case .gear: return "gearshape.fill"
        case .slider: return "slider.horizontal.3"
        case .checklist: return "checklist"
        case .target: return "target"
        case .location: return "location.fill"
        case .compass: return "safari.fill"
        case .paperplane: return "paperplane.fill"
        case .wand: return "wand.and.stars"
        case .paintbrush: return "paintbrush.pointed.fill"
        case .lightbulb: return "lightbulb.fill"
        case .lock: return "lock.fill"
        case .shield: return "shield.fill"
        case .bunny: return "carrot.fill"
        case .tortoise: return "tortoise.fill"
        case .hare: return "hare.fill"
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        }
    }

    /// Custom asset has transparent padding; SF Symbols fill tighter — boost only MoveIt in pickers.
    func pickerImageSize(base: CGFloat = 14) -> CGFloat {
        isDefault ? base * 1.45 : base
    }

    @ViewBuilder
    func labelImage(size: CGFloat = 16) -> some View {
        Group {
            if self == .moveit {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if let systemImageName {
                Image(systemName: systemImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
    }
}
