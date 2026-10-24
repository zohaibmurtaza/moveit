import SwiftUI

/// Menu-bar status item artwork. Persisted via `AppStorage` / `UserDefaults`.
enum MenuBarIconOption: String, CaseIterable, Identifiable {
    case moveit
    case cursor
    case mouse
    case keyboard
    case circle
    case square
    case bolt
    case sparkles
    case wave
    case clock
    case leaf
    case drop

    static let storageKey = "menuBarIcon"

    var id: String { rawValue }

    var isDefault: Bool { self == .moveit }

    var title: String {
        switch self {
        case .moveit: return "MoveIt"
        case .cursor: return "Cursor"
        case .mouse: return "Mouse"
        case .keyboard: return "Keyboard"
        case .circle: return "Dot"
        case .square: return "Square"
        case .bolt: return "Bolt"
        case .sparkles: return "Sparkles"
        case .wave: return "Wave"
        case .clock: return "Clock"
        case .leaf: return "Leaf"
        case .drop: return "Drop"
        }
    }

    private var systemImageName: String? {
        switch self {
        case .moveit: return nil
        case .cursor: return "cursorarrow"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .circle: return "circle.fill"
        case .square: return "square.fill"
        case .bolt: return "bolt.fill"
        case .sparkles: return "sparkles"
        case .wave: return "waveform"
        case .clock: return "clock"
        case .leaf: return "leaf.fill"
        case .drop: return "drop.fill"
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
