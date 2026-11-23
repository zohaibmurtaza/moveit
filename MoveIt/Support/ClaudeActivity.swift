import AppKit
import ApplicationServices
import CoreGraphics

/// A surface inside the Claude desktop app. Panels can sit anywhere in the window,
/// so these are found by accessibility label, never by fixed geometry.
enum ClaudeSurface: String, CaseIterable {
    case chat
    case terminal
    case files
    case changes

    var label: String {
        switch self {
        case .chat: return "Chat"
        case .terminal: return "Terminal"
        case .files: return "Files"
        case .changes: return "Changes"
        }
    }

    func eventTitle(switching: Bool) -> String {
        switching ? "Claude · \(label) · switch" : "Claude · \(label)"
    }

    static func parse(eventTitle: String) -> (surface: ClaudeSurface, switching: Bool)? {
        for surface in ClaudeSurface.allCases {
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

/// Where Claude's panels actually are right now, in CG coordinates.
struct ClaudeLayout {
    var window: CGRect?
    var panes: [ClaudeSurface: CGRect] = [:]

    func has(_ surface: ClaudeSurface) -> Bool {
        interactionRect(for: surface) != nil
    }

    /// Body of a pane, kept off headers, tab strips, the composer, and neighboring panes.
    func interactionRect(for surface: ClaudeSurface) -> CGRect? {
        guard var rect = panes[surface] else { return nil }
        let topFraction: CGFloat
        let bottomFraction: CGFloat
        switch surface {
        case .chat:
            topFraction = 0.16
            bottomFraction = 0.28
        case .terminal:
            topFraction = 0.28
            bottomFraction = 0.08
        case .files:
            topFraction = 0.16
            bottomFraction = 0.08
        case .changes:
            topFraction = 0.16
            bottomFraction = 0.08
        }
        let side = min(16, rect.width * 0.06)
        let top = min(rect.height * topFraction, rect.height * 0.30)
        let bottom = min(rect.height * bottomFraction, rect.height * 0.32)
        rect = rect.insetBy(dx: side, dy: 0)
        rect.origin.y += top
        rect.size.height -= top + bottom
        if surface == .chat {
            for other in ClaudeSurface.allCases where other != .chat {
                rect = ClaudeLayout.clipped(rect, awayFrom: panes[other])
            }
        }
        guard rect.width >= 28, rect.height >= 28 else { return nil }
        return rect
    }

    /// A point deep inside a pane body (lower part for terminals so tab strips stay clear).
    func clickPoint(for surface: ClaudeSurface) -> CGPoint? {
        guard let rect = interactionRect(for: surface) else { return nil }
        let yRange: ClosedRange<CGFloat> = surface == .terminal ? 0.45...0.9 : 0.2...0.8
        return CGPoint(
            x: rect.minX + rect.width * CGFloat.random(in: 0.2...0.8),
            y: rect.minY + rect.height * CGFloat.random(in: yRange)
        )
    }

    private static func clipped(_ rect: CGRect, awayFrom other: CGRect?) -> CGRect {
        guard let other else { return rect }
        let overlap = rect.intersection(other)
        guard !overlap.isNull, !overlap.isEmpty else { return rect }
        let overlapArea = overlap.width * overlap.height
        guard overlapArea > rect.width * rect.height * 0.08 else { return rect }
        var result = rect
        // Cut along whichever axis loses the least.
        let horizontalLoss = overlap.width * rect.height
        let verticalLoss = overlap.height * rect.width
        if horizontalLoss <= verticalLoss {
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
        } else {
            if other.midY >= rect.midY {
                let height = other.minY - rect.minY - 6
                if height >= 28 { result.size.height = height }
            } else {
                let y = other.maxY + 6
                let height = rect.maxY - y
                if height >= 28 {
                    result.origin.y = y
                    result.size.height = height
                }
            }
        }
        return result
    }
}

/// Claude desktop targeting. Nothing here types, presses Return, or sends a message:
/// it only moves the pointer, scrolls, and (for Files / Changes / Terminal) clicks pane bodies.
enum ClaudeActivity {
    static let bundleID = "com.anthropic.claudefordesktop"
    static let focusEventTitle = "Focus Claude"

    static var isRunning: Bool {
        onMain { runningApp() != nil }
    }

    static var runningBundleID: String? {
        onMain { runningApp()?.bundleIdentifier }
    }

    static func runningApp() -> NSRunningApplication? {
        let exact = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.activationPolicy == .regular }
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        if let exact { return exact }
        return NSWorkspace.shared.runningApplications.first { app in
            guard app.activationPolicy == .regular else { return false }
            return app.localizedName == "Claude" || app.bundleIdentifier == bundleID
        }
    }

    static func isFrontmost() -> Bool {
        onMain {
            guard let front = NSWorkspace.shared.frontmostApplication else { return false }
            if front.bundleIdentifier == bundleID { return true }
            if front.localizedName == "Claude" { return true }
            return false
        }
    }

    /// Live panel frames. Recomputed when the window is resized or panels move.
    static func layout() -> ClaudeLayout {
        onMain { layoutOnMain() }
    }

    static func invalidateLayout() {
        onMain { layoutCache = nil }
    }

    static func cursorIsInside(_ rect: CGRect) -> Bool {
        rect.contains(cursorCGPoint())
    }

    private static var layoutCache: (layout: ClaudeLayout, at: Date, window: CGRect)?
    private static var enhancedPIDs: Set<pid_t> = []

    private static func layoutOnMain() -> ClaudeLayout {
        guard let window = frontWindowOnMain() else {
            layoutCache = nil
            return ClaudeLayout()
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

    private static func probeLayout(window: CGRect) -> ClaudeLayout {
        guard let app = runningApp() else { return fallbackLayout(window) }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.4)
        // Electron only builds its accessibility tree on request.
        if !enhancedPIDs.contains(app.processIdentifier) {
            enhancedPIDs.insert(app.processIdentifier)
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        guard let axWindow = axWindow(in: axApp, matching: window) else {
            return fallbackLayout(window)
        }

        var bestArea: [ClaudeSurface: CGFloat] = [:]
        var bestFrame: [ClaudeSurface: CGRect] = [:]
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) {
            if depth > 16 || visited > 1600 { return }
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
                if let surface = classify(element, role: role, frame: frame),
                   area > (bestArea[surface] ?? 0) {
                    bestArea[surface] = area
                    bestFrame[surface] = frame
                }
            }
            for child in axChildren(element) {
                walk(child, depth: depth + 1)
            }
        }
        walk(axWindow, depth: 0)

        // The transcript is the main column — if nothing labeled it, use the window body.
        if bestFrame[.chat] == nil {
            let others = bestFrame.values
            var body = window
            body.origin.y += 44
            body.size.height = max(0, body.height - 52)
            body = body.insetBy(dx: window.width * 0.12, dy: 0)
            if body.width >= 200, body.height >= 160,
               others.allSatisfy({ !overlapsHeavily(body, $0) }) {
                bestFrame[.chat] = body
            }
        }
        guard !bestFrame.isEmpty else { return fallbackLayout(window) }
        return ClaudeLayout(window: window, panes: bestFrame)
    }

    /// Used only when Accessibility cannot see inside the window: just the central column.
    private static func fallbackLayout(_ window: CGRect) -> ClaudeLayout {
        guard window.width >= 480, window.height >= 320 else {
            return ClaudeLayout(window: window)
        }
        let chat = CGRect(
            x: window.minX + window.width * 0.2,
            y: window.minY + 44,
            width: window.width * 0.6,
            height: window.height - 56
        )
        return ClaudeLayout(window: window, panes: [.chat: chat])
    }

    private static func overlapsHeavily(_ a: CGRect, _ b: CGRect) -> Bool {
        let hit = a.intersection(b)
        guard !hit.isNull, !hit.isEmpty else { return false }
        return hit.width * hit.height > min(a.width * a.height, b.width * b.height) * 0.5
    }

    private static func classify(_ element: AXUIElement, role: String, frame: CGRect) -> ClaudeSurface? {
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
        // Buttons / tabs / toggles are controls, not panes.
        let controlRoles: Set<String> = ["AXButton", "AXRadioButton", "AXCheckBox", "AXMenuButton", "AXPopUpButton", "AXTab", "AXLink"]
        if controlRoles.contains(role) { return nil }

        if (text.contains("terminal") || text.contains("xterm")) && !text.contains("toggle"),
           frame.width >= 160, frame.height >= 72 {
            return .terminal
        }
        if text.contains("changes") || text.contains("diff") || text.contains("source control"),
           frame.width >= 160, frame.height >= 120 {
            return .changes
        }
        if text.contains("file tree") || text.contains("file explorer") || text.contains("explorer")
            || text.contains("files") || text.contains("project files"),
           frame.width >= 140, frame.height >= 140 {
            return .files
        }
        if text.contains("chat") || text.contains("conversation") || text.contains("transcript")
            || text.contains("messages"),
           frame.width >= 220, frame.height >= 200 {
            return .chat
        }
        return nil
    }

    private static func axWindow(in app: AXUIElement, matching window: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let value else { return nil }
        var best: AXUIElement?
        var bestArea: CGFloat = 0
        for candidate in axElements(value) {
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
        guard !pids.isEmpty,
              let info = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]]
        else { return nil }

        var best: CGRect?
        var bestArea: CGFloat = 0
        for entry in info {
            guard let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  pids.contains(pid_t(pidNumber.int32Value)) else { continue }
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue
            else { continue }
            let rect = CGRect(x: x, y: y, width: width, height: height)
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

    private static func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }
}
