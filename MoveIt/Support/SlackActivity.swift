import AppKit
import ApplicationServices
import CoreGraphics

/// One Slack behavior. Nothing here types into the composer or presses Return.
enum SlackMove: String, CaseIterable {
    case channel
    case messages
    case thread
    case closeThread
    case search
    case workspace

    func eventTitle(switching: Bool) -> String {
        switch self {
        case .channel:
            return switching ? "Slack · Channel · switch" : "Slack · Channel"
        case .messages:
            return "Slack · Messages"
        case .thread:
            return "Slack · Thread"
        case .closeThread:
            return "Slack · Close thread"
        case .search:
            return "Slack · Search"
        case .workspace:
            return "Slack · Organization"
        }
    }

    static func parse(eventTitle: String) -> (SlackMove, Bool)? {
        for move in SlackMove.allCases {
            if eventTitle == move.eventTitle(switching: true) {
                return (move, true)
            }
            if eventTitle == move.eventTitle(switching: false) {
                return (move, false)
            }
        }
        return nil
    }
}

/// Channel list, message transcript, and thread column inside the Slack window.
struct SlackLayout {
    var window: CGRect
    var channels: CGRect
    var messages: CGRect
    var thread: CGRect

    func channelPoint() -> CGPoint {
        point(in: channels, xRange: 0.28...0.78, yRange: 0.18...0.86)
    }

    func messagePoint() -> CGPoint {
        point(in: messages, xRange: 0.18...0.72, yRange: 0.12...0.78)
    }

    func threadPoint() -> CGPoint {
        point(in: thread, xRange: 0.15...0.8, yRange: 0.12...0.75)
    }

    private func point(
        in rect: CGRect,
        xRange: ClosedRange<CGFloat>,
        yRange: ClosedRange<CGFloat>
    ) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * CGFloat.random(in: xRange),
            y: rect.minY + rect.height * CGFloat.random(in: yRange)
        )
    }
}

/// Slack targeting. Shortcuts are the ones that move around Slack without sending a message.
enum SlackActivity {
    static let bundleID = "com.tinyspeck.slackmacgap"
    static let focusEventTitle = "Focus Slack"

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
            let name = app.localizedName ?? ""
            let id = app.bundleIdentifier ?? ""
            return name == "Slack" || id == bundleID
        }
    }

    static func isFrontmost() -> Bool {
        onMain {
            guard let front = NSWorkspace.shared.frontmostApplication else { return false }
            if front.bundleIdentifier == bundleID { return true }
            if front.localizedName == "Slack" { return true }
            return false
        }
    }

    static func layout() -> SlackLayout? {
        onMain { layoutOnMain() }
    }

    private static func layoutOnMain() -> SlackLayout? {
        guard let window = frontWindowOnMain(), window.width >= 640, window.height >= 420 else { return nil }
        let sidebarWidth = detectedSidebarWidth(in: window) ?? min(280, window.width * 0.24)
        let rail: CGFloat = 58
        let top: CGFloat = 56
        let composer: CGFloat = min(168, window.height * 0.2)
        let channels = CGRect(
            x: window.minX + rail,
            y: window.minY + top + 28,
            width: max(120, sidebarWidth - rail),
            height: max(160, window.height - top - 70)
        )
        let messages = CGRect(
            x: channels.maxX + 16,
            y: window.minY + top + 36,
            width: max(180, window.maxX - channels.maxX - 32),
            height: max(160, window.height - top - composer - 48)
        )
        let thread = CGRect(
            x: messages.maxX - messages.width * 0.4,
            y: messages.minY + 8,
            width: messages.width * 0.36,
            height: messages.height * 0.82
        )
        return SlackLayout(window: window, channels: channels, messages: messages, thread: thread)
    }

    /// Width of the left column (icon rail + channel list) when Accessibility can see it.
    private static func detectedSidebarWidth(in window: CGRect) -> CGFloat? {
        guard let app = runningApp() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        var best: CGFloat?
        var bestArea: CGFloat = 0
        var seen = 0
        func walk(_ element: AXUIElement, depth: Int) {
            if depth > 8 || seen > 500 { return }
            seen += 1
            if let frame = axFrame(element),
               frame.minX <= window.minX + 20,
               frame.maxX < window.midX,
               frame.width >= 180, frame.width <= 460,
               frame.height > window.height * 0.55 {
                let area = frame.width * frame.height
                if area > bestArea {
                    bestArea = area
                    best = frame.maxX - window.minX
                }
            }
            var kids: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &kids) == .success,
                  let children = kids as? [AXUIElement] else { return }
            for child in children { walk(child, depth: depth + 1) }
        }
        for windowElement in windows { walk(windowElement, depth: 0) }
        return best
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
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
        let raw = CGRect(origin: origin, size: size)
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let flipped = CGRect(x: raw.minX, y: screenHeight - raw.maxY, width: raw.width, height: raw.height)
        return raw.minY >= 0 ? raw : flipped
    }

    private static func frontWindowOnMain() -> CGRect? {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: runningBundleID ?? bundleID).map(\.processIdentifier))
        guard !pids.isEmpty,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
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
            let area = rect.width * rect.height
            if area > bestArea {
                bestArea = area
                best = rect
            }
        }
        return best
    }

    private static func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }
}
