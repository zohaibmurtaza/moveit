import Foundation

enum ActivityKind: String, Codable {
    case mouse
    case scroll
    case keyboard
    case silentKeys
    case appSwitch
    case tabSwitch
    case cursor
    case slack
    case microBreak
    case waiting
    case skipped

    var systemImage: String {
        switch self {
        case .mouse: return "computermouse"
        case .scroll: return "arrow.up.arrow.down"
        case .keyboard: return "keyboard"
        case .silentKeys: return "keyboard.fill"
        case .appSwitch: return "arrow.left.arrow.right.square"
        case .tabSwitch: return "rectangle.stack"
        case .cursor: return "macwindow"
        case .slack: return "bubble.left.and.bubble.right"
        case .microBreak: return "cup.and.saucer"
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
        case .tabSwitch: return "teal"
        case .cursor: return "green"
        case .slack: return "purple"
        case .microBreak: return "mint"
        case .waiting: return "secondary"
        case .skipped: return "secondary"
        }
    }
}

/// How often micro-breaks occur per hour.
enum MicroBreakFrequency: String, CaseIterable, Identifiable, Codable {
    case fewer = "Fewer"
    case standard = "Standard"
    case more = "More"

    var id: String { rawValue }

    var breaksPerHourRange: ClosedRange<Int> {
        switch self {
        case .fewer: return 1...2
        case .standard: return 1...3
        case .more: return 2...4
        }
    }

    var detail: String {
        switch self {
        case .fewer: return "1–2 breaks/hour · 30–120 sec each"
        case .standard: return "1–3 breaks/hour · 30–120 sec each"
        case .more: return "2–4 breaks/hour · 30–120 sec each"
        }
    }
}

/// Work rhythm phase — shifts weight among activity types to mimic real work patterns.
enum WorkRhythm: String, CaseIterable, Codable {
    case typing
    case reading
    case navigation
    case mixed
    case quiet

    /// Probability weights for (mouse, scroll, keyboard, appSwitch, tabSwitch).
    var weights: (mouse: Double, scroll: Double, keyboard: Double, appSwitch: Double, tabSwitch: Double) {
        switch self {
        case .typing: return (0.15, 0.05, 0.65, 0.05, 0.10)
        case .reading: return (0.20, 0.55, 0.05, 0.05, 0.15)
        case .navigation: return (0.35, 0.10, 0.05, 0.30, 0.20)
        case .mixed: return (0.35, 0.20, 0.20, 0.10, 0.15)
        case .quiet: return (0.50, 0.15, 0.10, 0.05, 0.20)
        }
    }

    var label: String {
        switch self {
        case .typing: return "Typing"
        case .reading: return "Reading"
        case .navigation: return "Navigation"
        case .mixed: return "Mixed work"
        case .quiet: return "Thinking"
        }
    }
}

/// Where tab-switching shortcuts are sent.
enum TabSwitchScope: String, CaseIterable, Identifiable, Codable {
    case browsersOnly = "Browsers only"
    case allApps = "All apps"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .browsersOnly: return "Only send ⌃Tab / ⌘1–9 when a recognized browser is frontmost. Prevents accidental edits in other apps."
        case .allApps: return "Send tab shortcuts to whatever app is frontmost. May insert tabs in editors."
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
