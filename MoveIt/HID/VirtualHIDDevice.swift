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

    func scroll(dy: Int) {
        lock.lock()
        defer { lock.unlock() }

        let wheel = clamp8(dy)

        switch backend {
        case .virtualHID:
            let report: [UInt8] = [0, 0, 0, UInt8(bitPattern: wheel)]
            handleMouseReport(report)
        case .cgEvent:
            let source = CGEventSource(stateID: .hidSystemState)
            if let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 1,
                wheel1: Int32(wheel),
                wheel2: 0,
                wheel3: 0
            ) {
                event.post(tap: .cghidEventTap)
            }
        case .unavailable:
            break
        }
    }

    // MARK: - Keyboard (safe keys only)

    func tap(_ key: SafeHIDKey, holdMilliseconds: UInt64 = 40) {
        press(key)
        Thread.sleep(forTimeInterval: TimeInterval(holdMilliseconds) / 1000.0)
        release(key)
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
            postCGKey(key, keyDown: true)
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
            postCGKey(key, keyDown: false)
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

    private func postCGKey(_ key: SafeHIDKey, keyDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let virtualKey = cgKeyCode(for: key)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: virtualKey,
            keyDown: keyDown
        ) else {
            return
        }
        event.flags = []
        event.post(tap: .cghidEventTap)
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
        }
    }

    private func clamp8(_ value: Int) -> Int8 {
        Int8(clamping: value)
    }
}
