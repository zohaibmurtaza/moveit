import AppKit
import ApplicationServices
import CoreGraphics

/// A surface inside the Cursor editor layout.
enum CursorSurface: String, CaseIterable {
    case editor
    case terminal
    case chat

    var label: String {
        switch self {
        case .editor: return "Files"
        case .terminal: return "Terminal"
        case .chat: return "Chat"
        }
    }

    func eventTitle(switching: Bool) -> String {
        switching ? "Cursor · \(label) · switch" : "Cursor · \(label)"
    }

    static func parse(eventTitle: String) -> (surface: CursorSurface, switchTabs: Bool)? {
        for surface in CursorSurface.allCases {
            if eventTitle == surface.eventTitle(switching: true) {
                return (surface, true)
            }
            if eventTitle == surface.eventTitle(switching: false) {
                return (surface, false)
            }
        }
        return nil
    }
}

/// Where Cursor's editor, terminal, and chat actually are right now, in CG coordinates.
struct CursorLayout {
    var window: CGRect?
    var editor: CGRect?
    var terminal: CGRect?
    var chat: CGRect?
    /// Left-hand Explorer (file tree).
    var explorer: CGRect?
    /// Visible file rows inside the Explorer, in CG coordinates.
    var fileRows: [CGRect] = []

    func has(_ surface: CursorSurface) -> Bool {
        interactionRect(for: surface) != nil
    }

    /// Body of a pane, kept off tab strips, the chat input, and neighboring panes.
    func interactionRect(for surface: CursorSurface) -> CGRect? {
        let raw: CGRect?
        switch surface {
        case .editor: raw = editor
        case .terminal: raw = terminal
        case .chat: raw = chat
        }
        guard var rect = raw else { return nil }
        let topFraction: CGFloat
        let bottomFraction: CGFloat
        switch surface {
        case .editor:
            topFraction = 0.12
            bottomFraction = 0.06
        case .terminal:
            topFraction = 0.14
            bottomFraction = 0.08
        case .chat:
            topFraction = 0.12
            bottomFraction = 0.24
        }
        let side = min(16, rect.width * 0.06)
        let top = min(rect.height * topFraction, rect.height * 0.28)
        let bottom = min(rect.height * bottomFraction, rect.height * 0.30)
        rect = rect.insetBy(dx: side, dy: 0)
        rect.origin.y += top
        rect.size.height -= top + bottom
        if surface == .editor {
            rect = CursorLayout.clipped(rect, awayFrom: explorer)
            rect = CursorLayout.clipped(rect, awayFrom: chat)
            rect = CursorLayout.clipped(rect, awayFrom: terminal)
        }
        guard rect.width >= 28, rect.height >= 28 else { return nil }
        return rect
    }

    /// Shrink `rect` so it does not cover a neighboring pane.
    private static func clipped(_ rect: CGRect, awayFrom other: CGRect?) -> CGRect {
        guard let other else { return rect }
        let overlap = rect.intersection(other)
        guard !overlap.isNull, !overlap.isEmpty else { return rect }
        let overlapArea = overlap.width * overlap.height
        guard overlapArea > rect.width * rect.height * 0.08 else { return rect }
        var result = rect
        if other.midX >= rect.midX {
            let width = other.minX - rect.minX - 6
            if width >= 28 { result.size.width = width }
        } else {
            let x = other.maxX + 6
            let width = rect.maxX - x
            if width >= 28 {
                result.origin.x = x
                result.size.width = width
            }
        }
        if other.midY >= rect.midY {
            let height = other.minY - rect.minY - 6
            if height >= 28 { result.size.height = height }
        }
        return result
    }
}

/// Cursor-specific targeting. Shortcuts are the safe subset of Cursor's defaults:
/// file tabs, terminal tabs, and chat tabs. Nothing here types, sends, or accepts edits.
enum CursorActivity {
    static let bundleID = "com.todesktop.230313mzl4w4u92"
    static let focusEventTitle = "Focus Cursor IDE"

    static var isRunning: Bool {
        onMain { runningApp() != nil }
    }

    /// Bundle id of the Cursor that is actually running, if any.
    static var runningBundleID: String? {
        onMain { runningApp()?.bundleIdentifier }
    }

    static func runningApp() -> NSRunningApplication? {
        let exact = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.activationPolicy == .regular } ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        if let exact { return exact }
        return NSWorkspace.shared.runningApplications.first { app in
            guard app.activationPolicy == .regular else { return false }
            let name = app.localizedName ?? ""
            let id = app.bundleIdentifier ?? ""
            return name == "Cursor" || id.hasPrefix("com.todesktop.")
        }
    }

    static func isFrontmost() -> Bool {
        onMain {
            guard let front = NSWorkspace.shared.frontmostApplication else { return false }
            if front.bundleIdentifier == bundleID { return true }
            if front.localizedName == "Cursor" { return true }
            if let id = front.bundleIdentifier, id.hasPrefix("com.todesktop.") { return true }
            return false
        }
    }

    /// Largest on-screen Cursor window in CG coordinates (origin top-left, Y down).
    static func frontWindowCGRect() -> CGRect? {
        onMain { frontWindowOnMain() }
    }

    static func cursorIsInside(_ rect: CGRect) -> Bool {
        rect.contains(cursorCGPoint())
    }

    /// Live pane frames. Recomputed when the window is resized or panels are dragged.
    static func layout() -> CursorLayout {
        onMain { layoutOnMain() }
    }

    static func invalidateLayout() {
        onMain { layoutCache = nil }
    }

    /// A point on a file name in the left Explorer.
    static func explorerFilePoint() -> CGPoint? {
        onMain { filePoint(in: layoutOnMain()) }
    }

    /// A point on a line in the open editor, past the line-number gutter.
    static func editorLinePoint() -> CGPoint? {
        onMain {
            guard let editor = layoutOnMain().interactionRect(for: .editor) else { return nil }
            let textLeft = editor.minX + 58
            let textRight = editor.maxX - 70
            guard textRight > textLeft + 16 else { return nil }
            let yTop = editor.minY + 10
            let yBottom = editor.maxY - 10
            guard yBottom > yTop + 16 else { return nil }
            return CGPoint(
                x: CGFloat.random(in: textLeft...textRight),
                y: CGFloat.random(in: yTop...yBottom)
            )
        }
    }

    private static var layoutCache: (layout: CursorLayout, at: Date, window: CGRect)?

    private static func layoutOnMain() -> CursorLayout {
        guard let window = frontWindowOnMain() else {
            layoutCache = nil
            return CursorLayout()
        }
        if let layoutCache,
           Date().timeIntervalSince(layoutCache.at) < 1.0,
           abs(layoutCache.window.width - window.width) < 4,
           abs(layoutCache.window.height - window.height) < 4,
           abs(layoutCache.window.minX - window.minX) < 4,
           abs(layoutCache.window.minY - window.minY) < 4 {
            return layoutCache.layout
        }
        let layout = probeLayout(window: window)
        layoutCache = (layout, Date(), window)
        return layout
    }

    private static func probeLayout(window: CGRect) -> CursorLayout {
        guard let app = runningApp() else { return percentageLayout(window) }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.4)
        guard let axWindow = axWindow(in: axApp, matching: window) else {
            return percentageLayout(window)
        }

        var bestArea: [CursorSurface: CGFloat] = [:]
        var bestFrame: [CursorSurface: CGRect] = [:]
        var rightPane: CGRect?
        var rightPaneArea: CGFloat = 0
        var leftPane: CGRect?
        var leftPaneArea: CGFloat = 0
        var fileRows: [CGRect] = []
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) {
            if depth > 14 || visited > 1400 { return }
            visited += 1
            let role = axString(element, kAXRoleAttribute as String) ?? ""
            if role == "AXMenu" || role == "AXMenuBar" || role == "AXMenuItem" { return }
            if let raw = axRawFrame(element), let frame = frameInWindow(raw, window: window) {
                let windowArea = max(window.width * window.height, 1)
                let area = frame.width * frame.height
                guard area < windowArea * 0.94 else {
                    for child in axChildren(element) { walk(child, depth: depth + 1) }
                    return
                }
                if let surface = classify(element, frame: frame), area > (bestArea[surface] ?? 0) {
                    bestArea[surface] = area
                    bestFrame[surface] = frame
                }
                // A tall pane flush with the right edge is the chat column, even when
                // its accessible name is just the current conversation.
                if frame.maxX >= window.maxX - 28,
                   frame.minX > window.minX + window.width * 0.2,
                   frame.height > window.height * 0.45,
                   frame.width > 180,
                   area > rightPaneArea {
                    rightPaneArea = area
                    rightPane = frame
                }
                // Explorer sits on the left, under the title bar, and is not the icon strip.
                if frame.minX <= window.minX + 80,
                   frame.minY <= window.minY + 100,
                   frame.maxX < window.midX,
                   frame.width >= 120, frame.width <= 480,
                   frame.height > window.height * 0.45,
                   area > leftPaneArea {
                    leftPaneArea = area
                    leftPane = frame
                }
                let label = axString(element, kAXTitleAttribute as String)
                    ?? axString(element, kAXDescriptionAttribute as String)
                    ?? ""
                if looksLikeFile(label),
                   frame.height >= 14, frame.height <= 36,
                   frame.width >= 40, frame.width <= 460,
                   frame.minX < window.midX,
                   fileRows.count < 80 {
                    fileRows.append(frame)
                }
            }
            for child in axChildren(element) {
                walk(child, depth: depth + 1)
            }
        }
        walk(axWindow, depth: 0)

        if let leftPane {
            fileRows = fileRows.filter { row in
                leftPane.insetBy(dx: -10, dy: -10).contains(CGPoint(x: row.midX, y: row.midY))
            }
        }
        fileRows = uniqueRows(fileRows)

        let chat = bestFrame[.chat] ?? rightPane
        let terminal = bestFrame[.terminal]
        var editor = bestFrame[.editor]
        if editor == nil || overlaps(editor, chat) || overlaps(editor, terminal) {
            editor = derivedEditor(window: window, chat: chat, terminal: terminal)
        }
        if chat == nil, terminal == nil, editor == nil, leftPane == nil {
            return percentageLayout(window)
        }
        return CursorLayout(
            window: window,
            editor: editor,
            terminal: terminal,
            chat: chat,
            explorer: leftPane,
            fileRows: fileRows
        )
    }

    /// Click the filename, not the disclosure triangle or the scrollbar.
    private static func filePoint(in layout: CursorLayout) -> CGPoint? {
        guard let explorer = layout.explorer, explorer.width >= 80, explorer.height >= 120 else { return nil }
        if let row = layout.fileRows.randomElement() {
            let x = min(row.maxX - 16, row.minX + max(36, row.width * 0.62))
            return CGPoint(x: max(explorer.minX + 28, x), y: row.midY)
        }
        let top = explorer.minY + explorer.height * 0.22
        let bottom = explorer.maxY - explorer.height * 0.08
        guard bottom > top + 20 else { return nil }
        return CGPoint(
            x: explorer.minX + explorer.width * CGFloat.random(in: 0.38...0.72),
            y: CGFloat.random(in: top...bottom)
        )
    }

    private static func uniqueRows(_ rows: [CGRect]) -> [CGRect] {
        var kept: [CGRect] = []
        for row in rows.sorted(by: { $0.minY < $1.minY }) {
            if let last = kept.last, abs(last.midY - row.midY) < 7 { continue }
            kept.append(row)
        }
        return kept
    }

    private static func looksLikeFile(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 3, name.count < 180 else { return false }
        let lower = name.lowercased()
        let blocked = [
            "explorer", "open editors", "outline", "timeline", "search",
            "source control", "run and debug", "extensions", "npm scripts"
        ]
        if blocked.contains(where: { lower == $0 || lower.hasPrefix($0) }) { return false }
        let token = name.split(separator: ",").first.map(String.init) ?? name
        let base = (token as NSString).lastPathComponent
        guard !base.hasPrefix("."), let dot = base.lastIndex(of: ".") else { return false }
        let ext = base[base.index(after: dot)...]
        return (1...8).contains(ext.count) && !ext.contains(" ") && !ext.contains("/")
    }

    /// Used only when Accessibility cannot see inside the window.
    private static func percentageLayout(_ window: CGRect) -> CursorLayout {
        guard window.width >= 480, window.height >= 320 else {
            return CursorLayout(window: window)
        }
        let chat = CGRect(
            x: window.minX + window.width * 0.58,
            y: window.minY + 40,
            width: window.width * 0.40,
            height: window.height - 52
        )
        let terminal = CGRect(
            x: window.minX + 8,
            y: window.minY + window.height * 0.78,
            width: window.width * 0.52,
            height: window.height * 0.18
        )
        let explorer = CGRect(
            x: window.minX + 46,
            y: window.minY + 40,
            width: min(250, window.width * 0.2),
            height: max(120, window.height - 88)
        )
        let editor = derivedEditor(window: window, chat: chat, terminal: terminal)
        return CursorLayout(
            window: window,
            editor: editor,
            terminal: terminal,
            chat: chat,
            explorer: explorer
        )
    }

    /// Editor column is whatever is left beside the chat and above the terminal.
    /// Returns nil when that column is gone (chat expanded over the files).
    private static func derivedEditor(window: CGRect, chat: CGRect?, terminal: CGRect?) -> CGRect? {
        var area = window
        area.origin.y += 38
        area.size.height = max(0, area.height - 52)
        area.origin.x += 6
        area.size.width = max(0, area.width - 12)

        if let chat, chat.width >= 80, chat.height >= 120 {
            if chat.midX >= area.midX {
                let width = chat.minX - area.minX - 8
                guard width >= 150 else { return nil }
                area.size.width = width
            } else {
                let x = chat.maxX + 8
                let width = area.maxX - x
                guard width >= 150 else { return nil }
                area.origin.x = x
                area.size.width = width
            }
        }
        if let terminal, terminal.height >= 50 {
            let overlap = area.intersection(terminal)
            if !overlap.isNull, overlap.width > 40 {
                let height = terminal.minY - area.minY - 6
                guard height >= 120 else { return nil }
                area.size.height = height
            }
        }
        guard area.width >= 150, area.height >= 120 else { return nil }
        return area
    }

    private static func overlaps(_ a: CGRect?, _ b: CGRect?) -> Bool {
        guard let a, let b else { return false }
        let hit = a.intersection(b)
        guard !hit.isNull, !hit.isEmpty else { return false }
        return hit.width * hit.height > a.width * a.height * 0.2
    }

    private static func classify(_ element: AXUIElement, frame: CGRect) -> CursorSurface? {
        let text = [
            axString(element, kAXTitleAttribute as String),
            axString(element, kAXDescriptionAttribute as String),
            axString(element, kAXRoleDescriptionAttribute as String),
            axString(element, kAXHelpAttribute as String),
            axString(element, "AXDOMIdentifier"),
            axClassList(element)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        guard !text.isEmpty else { return nil }

        let chatName = text.contains("unified agents")
            || text.contains("agents sidebar")
            || text.contains("agent-sidebar")
            || text.contains("unified-agents")
            || text.contains("aichat")
            || text.contains("composer")
            || (text.contains("chat") && !text.contains("editor"))
        if chatName, frame.width >= 160, frame.height >= 180 {
            return .chat
        }

        let terminalName = text.contains("terminal") && !text.contains("toggle")
        if terminalName, frame.width >= 160, frame.height >= 72 {
            return .terminal
        }

        let editorName = (text.contains("editor group") || text.contains("editor-group") || text.contains("monaco"))
            && !text.contains("lock")
        if editorName, frame.width >= 160, frame.height >= 140 {
            return .editor
        }
        return nil
    }

    private static func axWindow(in app: AXUIElement, matching window: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let value else { return nil }
        let windows = axElements(value)
        var best: AXUIElement?
        var bestArea: CGFloat = 0
        for candidate in windows {
            guard let raw = axRawFrame(candidate), let frame = frameInWindow(raw, window: window) else { continue }
            let hit = frame.intersection(window)
            guard !hit.isNull else { continue }
            let area = hit.width * hit.height
            if area > bestArea {
                bestArea = area
                best = candidate
            }
        }
        return best
    }

    private static func frameInWindow(_ raw: CGRect, window: CGRect) -> CGRect? {
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let candidates = [
            raw,
            CGRect(x: raw.minX, y: screenHeight - raw.maxY, width: raw.width, height: raw.height),
            CGRect(x: raw.minX, y: screenHeight - raw.minY, width: raw.width, height: raw.height)
        ]
        let expanded = window.insetBy(dx: -12, dy: -12)
        var best: CGRect?
        var bestArea: CGFloat = 0
        for candidate in candidates {
            guard candidate.width > 8, candidate.height > 8 else { continue }
            let hit = expanded.intersection(candidate)
            guard !hit.isNull, !hit.isEmpty else { continue }
            let area = hit.width * hit.height
            let elementArea = candidate.width * candidate.height
            guard area > elementArea * 0.5 else { continue }
            if area > bestArea {
                bestArea = area
                best = candidate
            }
        }
        return best
    }

    private static func axRawFrame(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 1, size.height > 1
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let value else { return [] }
        return axElements(value)
    }

    private static func axElements(_ value: CFTypeRef) -> [AXUIElement] {
        value as? [AXUIElement] ?? []
    }

    private static func axString(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value else { return nil }
        return value as? String
    }

    private static func axClassList(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &value) == .success,
              let value else { return nil }
        if let text = value as? String { return text }
        if let names = value as? [String] { return names.joined(separator: " ") }
        if let array = value as? NSArray {
            return array.compactMap { $0 as? String }.joined(separator: " ")
        }
        return nil
    }

    private static func frontWindowOnMain() -> CGRect? {
        let pids = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: runningBundleID ?? bundleID)
                .map(\.processIdentifier)
        )
        guard !pids.isEmpty else { return nil }
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var best: CGRect?
        var bestArea: CGFloat = 0
        for entry in info {
            guard let pid = pidValue(entry[kCGWindowOwnerPID as String]), pids.contains(pid) else { continue }
            let layer = intValue(entry[kCGWindowLayer as String]) ?? 0
            guard layer == 0 else { continue }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let rect = cgRect(bounds) else { continue }
            guard rect.width >= 240, rect.height >= 180 else { continue }
            let area = rect.width * rect.height
            if area > bestArea {
                bestArea = area
                best = rect
            }
        }
        return best
    }

    private static func cursorCGPoint() -> CGPoint {
        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: location.x, y: screenHeight - location.y)
    }

    private static func cgRect(_ bounds: [String: Any]) -> CGRect? {
        guard let x = cgFloat(bounds["X"]),
              let y = cgFloat(bounds["Y"]),
              let width = cgFloat(bounds["Width"]),
              let height = cgFloat(bounds["Height"]) else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        switch value {
        case let number as NSNumber:
            return CGFloat(number.doubleValue)
        case let number as Double:
            return CGFloat(number)
        case let number as CGFloat:
            return number
        case let number as Int:
            return CGFloat(number)
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let number as Int:
            return number
        case let number as Int32:
            return Int(number)
        default:
            return nil
        }
    }

    private static func pidValue(_ value: Any?) -> pid_t? {
        switch value {
        case let number as NSNumber:
            return pid_t(number.int32Value)
        case let number as Int32:
            return number
        case let number as Int:
            return pid_t(number)
        default:
            return nil
        }
    }

    private static func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }
}
