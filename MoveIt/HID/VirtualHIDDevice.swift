import Foundation
import IOKit
import CoreGraphics
import AppKit

enum InputBackend: String {
    case virtualHID = "Virtual HID"
    case cgEvent = "CGEvent fallback"
    case unavailable = "Unavailable"
}

/// Posts mouse and keyboard activity via IOHIDUserDevice when the
/// `com.apple.developer.hid.virtual.device` entitlement is present; otherwise
/// falls back to CGEvent synthesis (useful for educational / testing setups).
final class VirtualHIDDevice {
    private var mouseDevice: IOHIDUserDevice?
    private var keyboardDevice: IOHIDUserDevice?
    private let queue = DispatchQueue(label: "com.moveit.hid", qos: .userInteractive)
    private(set) var backend: InputBackend = .unavailable
    private var keyboardModifiers: UInt8 = 0
    private let lock = NSLock()

    var isReady: Bool { backend != .unavailable }

    @discardableResult
    func start() -> InputBackend {
        lock.lock()
        defer { lock.unlock() }

        stopLocked()

        let mouse = createAndActivateDevice(
            descriptor: HIDDescriptors.mouse,
            product: "SMH Pointing Device",
            vendorID: 0x05AC,
            productID: 0x1001
        )
        let keyboard = createAndActivateDevice(
            descriptor: HIDDescriptors.keyboard,
            product: "SMH Keyboard",
            vendorID: 0x05AC,
            productID: 0x1002
        )

        if let mouse, let keyboard {
            mouseDevice = mouse
            keyboardDevice = keyboard
            backend = .virtualHID
        } else {
            tearDownDevice(mouse)
            tearDownDevice(keyboard)
            mouseDevice = nil
            keyboardDevice = nil
            backend = .cgEvent
        }

        return backend
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        releaseAllKeysLocked()
        setButtonLocked(0)
        tearDownDevice(mouseDevice)
        tearDownDevice(keyboardDevice)
        mouseDevice = nil
        keyboardDevice = nil
        backend = .unavailable
    }

    private func tearDownDevice(_ device: IOHIDUserDevice?) {
        guard let device else { return }
        IOHIDUserDeviceCancel(device)
        // Keep a strong ref until cancel completes; CFRelease via ARC when dropped.
        _ = device
    }

    // MARK: - Mouse

    func moveBy(dx: Int, dy: Int) {
        lock.lock()
        defer { lock.unlock() }

        let clampedDX = clamp8(dx)
        let clampedDY = clamp8(dy)

        switch backend {
        case .virtualHID:
            var report: [UInt8] = [
                0,
                UInt8(bitPattern: clampedDX),
                UInt8(bitPattern: clampedDY),
                0
            ]
            handleMouseReport(report)
        case .cgEvent:
            postCGMouseMove(dx: Int(clampedDX), dy: Int(clampedDY))
        case .unavailable:
            break
        }
    }

    /// Left click at the current cursor. Button is released before returning.
    func click() {
        setButton(0x01)
        Thread.sleep(forTimeInterval: 0.045)
        setButton(0x00)
    }

    /// Relative scroll. `dy` is vertical; `dx` is horizontal.
    /// Vertical can use the virtual HID wheel; horizontal always uses CGEvent
    /// (HID mouse descriptor has no horizontal pan axis).
    func scroll(dx: Int = 0, dy: Int = 0) {
        lock.lock()
        defer { lock.unlock() }
        guard dx != 0 || dy != 0 else { return }

        let wheelY = clamp8(dy)
        let wheelX = clamp8(dx)

        if backend == .virtualHID, dy != 0 {
            let report: [UInt8] = [0, 0, 0, UInt8(bitPattern: wheelY)]
            handleMouseReport(report)
        }

        let needsCG = dx != 0 || backend != .virtualHID
        guard needsCG else { return }

        let source = CGEventSource(stateID: .hidSystemState)
        let cgY: Int32 = (backend == .virtualHID && dy != 0) ? 0 : Int32(wheelY)
        if let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .line,
            wheelCount: 2,
            wheel1: cgY,
            wheel2: Int32(wheelX),
            wheel3: 0
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Keyboard (safe keys only)

    func tap(_ key: SafeHIDKey, holdMilliseconds: UInt64 = 40) {
        press(key)
        Thread.sleep(forTimeInterval: TimeInterval(holdMilliseconds) / 1000.0)
        release(key)
    }

    /// Hold modifiers, tap a key, then release (e.g. ⌘Tab, ⌃Tab).
    func tapChord(
        modifiers: [SafeHIDKey],
        key: SafeHIDKey,
        holdMilliseconds: UInt64 = 45
    ) {
        switch backend {
        case .virtualHID:
            for modifier in modifiers where modifier.isModifier {
                press(modifier)
            }
            Thread.sleep(forTimeInterval: 0.025)
            tap(key, holdMilliseconds: holdMilliseconds)
            for modifier in modifiers.reversed() where modifier.isModifier {
                release(modifier)
            }
            releaseAllKeys()
        case .cgEvent:
            postCGChord(modifiers: modifiers, key: key, holdMilliseconds: holdMilliseconds)
        case .unavailable:
            break
        }
    }

    func press(_ key: SafeHIDKey) {
        lock.lock()
        defer { lock.unlock() }

        switch backend {
        case .virtualHID:
            if key.isModifier {
                keyboardModifiers |= key.modifierBit
                sendKeyboardReportLocked(keys: [])
            } else {
                sendKeyboardReportLocked(keys: [key.rawValue])
            }
        case .cgEvent:
            postCGKey(key, keyDown: true, flags: cgFlags(for: [key].filter(\.isModifier)))
        case .unavailable:
            break
        }
    }

    func release(_ key: SafeHIDKey) {
        lock.lock()
        defer { lock.unlock() }

        switch backend {
        case .virtualHID:
            if key.isModifier {
                keyboardModifiers &= ~key.modifierBit
            }
            sendKeyboardReportLocked(keys: [])
        case .cgEvent:
            postCGKey(key, keyDown: false, flags: [])
        case .unavailable:
            break
        }
    }

    func releaseAllKeys() {
        lock.lock()
        defer { lock.unlock() }
        releaseAllKeysLocked()
    }

    // MARK: - Private

    private func releaseAllKeysLocked() {
        keyboardModifiers = 0
        if backend == .virtualHID {
            sendKeyboardReportLocked(keys: [])
        }
    }

    private func createAndActivateDevice(
        descriptor: [UInt8],
        product: String,
        vendorID: Int,
        productID: Int
    ) -> IOHIDUserDevice? {
        let descriptorData = Data(descriptor) as CFData
        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey as String: descriptorData,
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID,
            kIOHIDProductKey as String: product,
            kIOHIDManufacturerKey as String: "SMH",
            kIOHIDCountryCodeKey as String: 0
        ]

        guard let device = IOHIDUserDeviceCreateWithProperties(
            kCFAllocatorDefault,
            properties as CFDictionary,
            0
        ) else {
            return nil
        }

        IOHIDUserDeviceSetDispatchQueue(device, queue)
        IOHIDUserDeviceActivate(device)
        return device
    }

    private func setButton(_ buttons: UInt8) {
        lock.lock()
        defer { lock.unlock() }
        setButtonLocked(buttons)
    }

    private func setButtonLocked(_ buttons: UInt8) {
        switch backend {
        case .virtualHID:
            let report: [UInt8] = [buttons, 0, 0, 0]
            handleMouseReport(report)
        case .cgEvent:
            postCGClick(down: buttons != 0)
        case .unavailable:
            break
        }
    }

    private func postCGClick(down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let point = currentCGMouse()
        let type: CGEventType = down ? .leftMouseDown : .leftMouseUp
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func currentCGMouse() -> CGPoint {
        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: location.x, y: screenHeight - location.y)
    }

    private func handleMouseReport(_ report: [UInt8]) {
        guard let device = mouseDevice else { return }
        report.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            _ = IOHIDUserDeviceHandleReportWithTimeStamp(
                device,
                mach_absolute_time(),
                base,
                report.count
            )
        }
    }

    private func sendKeyboardReportLocked(keys: [UInt8]) {
        guard let device = keyboardDevice else { return }
        var report = [UInt8](repeating: 0, count: HIDDescriptors.keyboardReportLength)
        report[0] = keyboardModifiers
        report[1] = 0
        for (index, code) in keys.prefix(6).enumerated() {
            report[2 + index] = code
        }
        report.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            _ = IOHIDUserDeviceHandleReportWithTimeStamp(
                device,
                mach_absolute_time(),
                base,
                report.count
            )
        }
    }

    private func postCGMouseMove(dx: Int, dy: Int) {
        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let current = CGPoint(x: location.x, y: screenHeight - location.y)
        let target = CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy))
        let source = CGEventSource(stateID: .hidSystemState)
        if let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func postCGChord(
        modifiers: [SafeHIDKey],
        key: SafeHIDKey,
        holdMilliseconds: UInt64
    ) {
        let flags = cgFlags(for: modifiers)
        // Press modifiers first so the key-down sees the full chord.
        for modifier in modifiers where modifier.isModifier {
            postCGKey(modifier, keyDown: true, flags: flags)
        }
        postCGKey(key, keyDown: true, flags: flags)
        Thread.sleep(forTimeInterval: TimeInterval(holdMilliseconds) / 1000.0)
        postCGKey(key, keyDown: false, flags: flags)
        for modifier in modifiers.reversed() where modifier.isModifier {
            postCGKey(modifier, keyDown: false, flags: [])
        }
    }

    private func postCGKey(_ key: SafeHIDKey, keyDown: Bool, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let virtualKey = cgKeyCode(for: key)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: virtualKey,
            keyDown: keyDown
        ) else {
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func cgFlags(for modifiers: [SafeHIDKey]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier {
            case .leftCommand, .rightCommand: flags.insert(.maskCommand)
            case .leftControl, .rightControl: flags.insert(.maskControl)
            case .leftShift, .rightShift: flags.insert(.maskShift)
            case .leftOption, .rightOption: flags.insert(.maskAlternate)
            default: break
            }
        }
        return flags
    }

    private func cgKeyCode(for key: SafeHIDKey) -> CGKeyCode {
        // macOS virtual key codes (ANSI layout)
        switch key {
        case .leftControl, .rightControl: return 59
        case .leftShift, .rightShift: return 56
        case .leftOption, .rightOption: return 58
        case .leftCommand, .rightCommand: return 55
        case .a: return 0
        case .s: return 1
        case .d: return 2
        case .f: return 3
        case .h: return 4
        case .g: return 5
        case .z: return 6
        case .x: return 7
        case .c: return 8
        case .v: return 9
        case .b: return 11
        case .q: return 12
        case .w: return 13
        case .e: return 14
        case .r: return 15
        case .y: return 16
        case .t: return 17
        case .digit1: return 18
        case .digit2: return 19
        case .digit3: return 20
        case .digit4: return 21
        case .digit6: return 22
        case .digit5: return 23
        case .digit9: return 25
        case .digit7: return 26
        case .digit8: return 28
        case .digit0: return 29
        case .o: return 31
        case .u: return 32
        case .i: return 34
        case .p: return 35
        case .l: return 37
        case .j: return 38
        case .k: return 40
        case .n: return 45
        case .m: return 46
        case .rightArrow: return 124
        case .leftArrow: return 123
        case .downArrow: return 125
        case .upArrow: return 126
        case .backspace: return 51
        case .space: return 49
        case .escape: return 53
        case .period: return 47
        case .leftBracket: return 33
        case .rightBracket: return 30
        case .tab: return 48
        case .grave: return 50
        }
    }

    private func clamp8(_ value: Int) -> Int8 {
        Int8(clamping: value)
    }
}
