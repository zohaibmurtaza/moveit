import Foundation

/// Standard HID report descriptors for a relative mouse and a boot-protocol keyboard.
enum HIDDescriptors {
    /// Relative mouse: buttons (3) + X/Y (relative 8-bit) + wheel (relative 8-bit)
    /// Report size: 4 bytes — [buttons, dx, dy, wheel]
    static let mouse: [UInt8] = [
        0x05, 0x01, // Usage Page (Generic Desktop)
        0x09, 0x02, // Usage (Mouse)
        0xA1, 0x01, // Collection (Application)
        0x09, 0x01, //   Usage (Pointer)
        0xA1, 0x00, //   Collection (Physical)
        0x05, 0x09, //     Usage Page (Button)
        0x19, 0x01, //     Usage Minimum (1)
        0x29, 0x03, //     Usage Maximum (3)
        0x15, 0x00, //     Logical Minimum (0)
        0x25, 0x01, //     Logical Maximum (1)
        0x95, 0x03, //     Report Count (3)
        0x75, 0x01, //     Report Size (1)
        0x81, 0x02, //     Input (Data,Var,Abs)
        0x95, 0x01, //     Report Count (1)
        0x75, 0x05, //     Report Size (5)
        0x81, 0x03, //     Input (Const,Var,Abs)
        0x05, 0x01, //     Usage Page (Generic Desktop)
        0x09, 0x30, //     Usage (X)
        0x09, 0x31, //     Usage (Y)
        0x09, 0x38, //     Usage (Wheel)
        0x15, 0x81, //     Logical Minimum (-127)
        0x25, 0x7F, //     Logical Maximum (127)
        0x75, 0x08, //     Report Size (8)
        0x95, 0x03, //     Report Count (3)
        0x81, 0x06, //     Input (Data,Var,Rel)
        0xC0, //   End Collection
        0xC0 // End Collection
    ]

    /// Boot keyboard: modifier byte + reserved + 6 keycodes
    /// Report size: 8 bytes
    static let keyboard: [UInt8] = [
        0x05, 0x01, // Usage Page (Generic Desktop)
        0x09, 0x06, // Usage (Keyboard)
        0xA1, 0x01, // Collection (Application)
        0x05, 0x07, //   Usage Page (Key Codes)
        0x19, 0xE0, //   Usage Minimum (Left Control)
        0x29, 0xE7, //   Usage Maximum (Right GUI)
        0x15, 0x00, //   Logical Minimum (0)
        0x25, 0x01, //   Logical Maximum (1)
        0x75, 0x01, //   Report Size (1)
        0x95, 0x08, //   Report Count (8)
        0x81, 0x02, //   Input (Data,Var,Abs) — modifiers
        0x95, 0x01, //   Report Count (1)
        0x75, 0x08, //   Report Size (8)
        0x81, 0x03, //   Input (Const,Var,Abs) — reserved
        0x95, 0x06, //   Report Count (6)
        0x75, 0x08, //   Report Size (8)
        0x15, 0x00, //   Logical Minimum (0)
        0x25, 0x65, //   Logical Maximum (101)
        0x05, 0x07, //   Usage Page (Key Codes)
        0x19, 0x00, //   Usage Minimum (0)
        0x29, 0x65, //   Usage Maximum (101)
        0x81, 0x00, //   Input (Data,Array) — keycodes
        0xC0 // End Collection
    ]

    static let mouseReportLength = 4
    static let keyboardReportLength = 8
}

/// Keys that won't trigger browser/system shortcuts (no F-keys, Escape, Page Up/Down, etc.).
enum SafeHIDKey: UInt8 {
    // Modifiers
    case leftControl = 0xE0
    case leftShift = 0xE1
    case leftOption = 0xE2
    case leftCommand = 0xE3
    case rightControl = 0xE4
    case rightShift = 0xE5
    case rightOption = 0xE6
    case rightCommand = 0xE7

    // Letters a–z (USB HID)
    case a = 0x04, b = 0x05, c = 0x06, d = 0x07, e = 0x08
    case f = 0x09, g = 0x0A, h = 0x0B, i = 0x0C, j = 0x0D
    case k = 0x0E, l = 0x0F, m = 0x10, n = 0x11, o = 0x12
    case p = 0x13, q = 0x14, r = 0x15, s = 0x16, t = 0x17
    case u = 0x18, v = 0x19, w = 0x1A, x = 0x1B, y = 0x1C, z = 0x1D

    // Digits 1–9, 0
    case digit1 = 0x1E, digit2 = 0x1F, digit3 = 0x20, digit4 = 0x21, digit5 = 0x22
    case digit6 = 0x23, digit7 = 0x24, digit8 = 0x25, digit9 = 0x26, digit0 = 0x27

    // Arrows only (no Home/End/Page Up/Down — those jump pages)
    case rightArrow = 0x4F
    case leftArrow = 0x50
    case downArrow = 0x51
    case upArrow = 0x52

    // Editing
    case backspace = 0x2A
    case space = 0x2C
    case escape = 0x29
    case period = 0x37

    // Bracket keys — only used for Cursor terminal chords (⌘⇧[ / ⌘⇧]).
    case leftBracket = 0x2F
    case rightBracket = 0x30

    // Used only inside navigation chords (⌘Tab, ⌃Tab, ⌘`)
    case tab = 0x2B
    case grave = 0x35

    var isModifier: Bool {
        switch self {
        case .leftControl, .leftShift, .leftOption, .leftCommand,
             .rightControl, .rightShift, .rightOption, .rightCommand:
            return true
        default:
            return false
        }
    }

    var modifierBit: UInt8 {
        switch self {
        case .leftControl: return 0x01
        case .leftShift: return 0x02
        case .leftOption: return 0x04
        case .leftCommand: return 0x08
        case .rightControl: return 0x10
        case .rightShift: return 0x20
        case .rightOption: return 0x40
        case .rightCommand: return 0x80
        default: return 0
        }
    }

    static var letterKeys: [SafeHIDKey] {
        [
            .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
            .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z
        ]
    }

    static var numberKeys: [SafeHIDKey] {
        [.digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9, .digit0]
    }

    static var navigationKeys: [SafeHIDKey] {
        [.upArrow, .downArrow, .leftArrow, .rightArrow]
    }

    static var modifierKeys: [SafeHIDKey] {
        [
            .leftShift, .leftControl, .leftOption, .leftCommand,
            .rightShift, .rightControl, .rightOption, .rightCommand
        ]
    }

    /// Modifiers that rarely type characters or fire single-key app shortcuts.
    /// (No Command — that opens menus; no letters/digits/arrows.)
    static var quietActivityKeys: [SafeHIDKey] {
        [.leftShift, .rightShift, .leftControl, .rightControl, .leftOption, .rightOption]
    }
}
