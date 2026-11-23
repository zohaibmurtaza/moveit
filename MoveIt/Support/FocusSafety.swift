import ApplicationServices
import AppKit

/// Detects whether keystrokes would land in a text field / editor / terminal.
enum FocusSafety {
    /// True when typing characters would disturb the user.
    /// Safe to call from a background thread (hops to main for AX).
    static var isEditingText: Bool {
        if Thread.isMainThread {
            return isEditingTextOnMain()
        }
        var result = false
        DispatchQueue.main.sync {
            result = isEditingTextOnMain()
        }
        return result
    }

    /// Cursor is Electron: its terminal / editor often hides from Accessibility, so while it
    /// is frontmost treat every character key as unsafe (belt and suspenders).
    private static func frontmostIsCursor() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if front.bundleIdentifier == CursorActivity.bundleID { return true }
        if let id = front.bundleIdentifier, id.hasPrefix("com.todesktop.") { return true }
        return front.localizedName == "Cursor"
    }

    private static func isEditingTextOnMain() -> Bool {
        if frontmostIsCursor() { return true }
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
        let focused = focusedRef else {
            return false
        }

        var element = focused as! AXUIElement
        for _ in 0..<10 {
            if looksEditable(element) {
                return true
            }
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXParentAttribute as CFString,
                &parentRef
            ) == .success,
            let parent = parentRef else {
                break
            }
            element = parent as! AXUIElement
        }
        return false
    }

    private static func looksEditable(_ element: AXUIElement) -> Bool {
        if let role = stringAttribute(element, kAXRoleAttribute as String) {
            let editableRoles: Set<String> = [
                kAXTextFieldRole as String,
                kAXTextAreaRole as String,
                kAXComboBoxRole as String,
                "AXSearchField",
                "AXWebArea"
            ]
            if editableRoles.contains(role) {
                // Web areas aren't always typing — require editable or selection attrs.
                if role == "AXWebArea" {
                    return boolAttribute(element, "AXEditable") == true
                        || hasAttribute(element, kAXSelectedTextAttribute as String)
                        || hasAttribute(element, "AXInsertionPointLineNumber")
                }
                return true
            }
        }

        if let subrole = stringAttribute(element, kAXSubroleAttribute as String)?.lowercased() {
            if subrole.contains("search") || subrole.contains("textarea") || subrole.contains("input") {
                return true
            }
        }

        if let roleDescription = stringAttribute(element, kAXRoleDescriptionAttribute as String)?
            .lowercased()
        {
            let hints = ["text", "editor", "search", "terminal", "console", "xterm", "vte", "field", "input", "area"]
            if hints.contains(where: { roleDescription.contains($0) }) {
                return true
            }
        }

        // Terminals in Electron / VTE apps often only reveal themselves by label.
        let terminalHints = ["terminal", "console", "xterm", "vte"]
        for attribute in [kAXTitleAttribute as String, kAXDescriptionAttribute as String] {
            if let text = stringAttribute(element, attribute)?.lowercased(),
               terminalHints.contains(where: { text.contains($0) }) {
                return true
            }
        }

        if boolAttribute(element, "AXEditable") == true {
            return true
        }

        // Presence of a caret / selected text is a strong signal (IDEs, Electron).
        if hasAttribute(element, "AXInsertionPointLineNumber")
            || hasAttribute(element, kAXSelectedTextAttribute as String)
            || hasAttribute(element, kAXNumberOfCharactersAttribute as String)
        {
            // Avoid treating static labels that expose empty AXSelectedText.
            if let selected = stringAttribute(element, kAXSelectedTextAttribute as String),
               selected.isEmpty,
               boolAttribute(element, "AXEditable") != true,
               !hasAttribute(element, "AXInsertionPointLineNumber")
            {
                return false
            }
            if hasAttribute(element, "AXInsertionPointLineNumber") {
                return true
            }
            if hasAttribute(element, kAXNumberOfCharactersAttribute as String),
               boolAttribute(element, "AXEditable") == true
            {
                return true
            }
        }

        return false
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value else { return nil }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }

    private static func hasAttribute(_ element: AXUIElement, _ name: String) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
            && value != nil
    }
}
