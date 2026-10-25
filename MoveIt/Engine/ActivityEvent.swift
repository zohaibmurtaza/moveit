import Foundation

enum ActivityKind: String, Codable {
    case mouse
    case scroll
    case keyboard
    case silentKeys
    case appSwitch
    case waiting
    case skipped

    var systemImage: String {
        switch self {
        case .mouse: return "computermouse"
        case .scroll: return "arrow.up.arrow.down"
        case .keyboard: return "keyboard"
        case .silentKeys: return "keyboard.fill"
        case .appSwitch: return "arrow.left.arrow.right.square"
        case .waiting: return "hourglass"
        case .skipped: return "hand.raised"
        }
    }

    var tintName: String {
        switch self {
        case .mouse: return "blue"
        case .scroll: return "cyan"
        case .keyboard: return "purple"
        case .silentKeys: return "indigo"
        case .appSwitch: return "orange"
        case .waiting: return "secondary"
        case .skipped: return "secondary"
        }
    }
}

struct ActivityEvent: Identifiable, Equatable {
    let id: UUID
    let kind: ActivityKind
    let title: String
    let createdAt: Date

    init(id: UUID = UUID(), kind: ActivityKind, title: String, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
    }
}
