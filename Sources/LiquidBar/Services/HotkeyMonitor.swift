import Foundation
import Carbon
import ApplicationServices

struct HotkeyShortcut: Sendable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static func parse(_ raw: String) -> HotkeyShortcut? {
        let tokens = raw
            .lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }

        var modifiers: UInt32 = 0
        var keyCode: UInt32?

        for token in tokens {
            switch token {
            case "cmd", "command":
                modifiers |= UInt32(cmdKey)
            case "ctrl", "control":
                modifiers |= UInt32(controlKey)
            case "alt", "option":
                modifiers |= UInt32(optionKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            default:
                keyCode = keyCodeForToken(token)
            }
        }

        guard modifiers != 0, let keyCode else { return nil }

        return HotkeyShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    /// Cmd+Tab (and Cmd+Shift+Tab) are intercepted by the system before Carbon
    /// hotkeys fire.  A CGEventTap at `.cgSessionEventTap` can intercept them.
    var requiresCGEventTap: Bool {
        keyCode == UInt32(kVK_Tab) && modifiers & UInt32(cmdKey) != 0
    }

    private static func keyCodeForToken(_ token: String) -> UInt32? {
        switch token {
        case "tab":
            return UInt32(kVK_Tab)
        case "space":
            return UInt32(kVK_Space)
        case "enter", "return":
            return UInt32(kVK_Return)
        case "escape", "esc":
            return UInt32(kVK_Escape)
        case "up":
            return UInt32(kVK_UpArrow)
        case "down":
            return UInt32(kVK_DownArrow)
        case "left":
            return UInt32(kVK_LeftArrow)
        case "right":
            return UInt32(kVK_RightArrow)
        default:
            return letterOrDigitKeyCode(token)
        }
    }

    private static func letterOrDigitKeyCode(_ token: String) -> UInt32? {
        switch token {
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "`", "grave":
            return UInt32(kVK_ANSI_Grave)
        default:
            return nil
        }
    }
}

final class HotkeyMonitor {
    enum EventTapDecision: Equatable {
        case passThrough
        case swallowMatchedPress
        case emitRelease
    }

    struct EventTapContext {
        let type: CGEventType
        let keyCode: Int64?
        let flags: CGEventFlags
        let shortcut: HotkeyShortcut?
        let sessionActive: Bool
    }

    private static let signature: OSType = 0x4C42534B // "LBSK"
    private static let hotkeyId: UInt32 = 1

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let shouldHandleEventTapPress: @Sendable () -> Bool
    private let onPress: @Sendable () -> Bool
    private let onRelease: @Sendable () -> Void
    private var currentShortcut: HotkeyShortcut?
    private var didRequestListenEventAccess = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var usesEventTap: Bool = false

    /// Static callback pointer — same pattern as MouseTracker._activeTapPtr.
    /// The C callback cannot capture `self`, so we stash the closure pointer here.
    nonisolated(unsafe) private static var _shouldHandleEventTapPressCallback: (@Sendable () -> Bool)?
    nonisolated(unsafe) private static var _onPressCallback: (@Sendable () -> Bool)?
    nonisolated(unsafe) private static var _onReleaseCallback: (@Sendable () -> Void)?
    nonisolated(unsafe) private static var _activeTapPort: CFMachPort?
    nonisolated(unsafe) private static var _tapShortcutSessionActive = false

    init(
        shouldHandleEventTapPress: @escaping @Sendable () -> Bool = { true },
        onPress: @escaping @Sendable () -> Bool,
        onRelease: @escaping @Sendable () -> Void = {}
    ) {
        self.shouldHandleEventTapPress = shouldHandleEventTapPress
        self.onPress = onPress
        self.onRelease = onRelease
        installEventHandler()
    }

    deinit {
        unregister()
        uninstallEventHandler()
    }

    func register(shortcut: HotkeyShortcut) {
        guard currentShortcut != shortcut else { return }
        unregister()

        if shortcut.requiresCGEventTap {
            if !Self.listenEventAccessGranted() {
                if !didRequestListenEventAccess {
                    didRequestListenEventAccess = true
                    _ = Self.requestListenEventAccess()
                }
                guard Self.listenEventAccessGranted() else {
                    Log.ui.error("Cmd+Tab hotkey requires Input Monitoring permission. Grant it in System Settings and re-apply.")
                    return
                }
            }
            installEventTap()
            if eventTap != nil {
                currentShortcut = shortcut
                usesEventTap = true
                Self._currentShortcutForTap = shortcut
            } else {
                Log.ui.error("Failed to install CGEventTap for Cmd+Tab (Input Monitoring permission required)")
            }
        } else {
            let id = EventHotKeyID(signature: Self.signature, id: Self.hotkeyId)
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                id,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr {
                currentShortcut = shortcut
                Self._currentShortcutForTap = nil
            } else {
                Log.ui.error("Failed to register hotkey status=\(status)")
            }
        }
    }

    func unregister() {
        if usesEventTap {
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
            }
            eventTap = nil
            runLoopSource = nil
            Self._activeTapPort = nil
            Self._shouldHandleEventTapPressCallback = nil
            Self._onPressCallback = nil
            Self._onReleaseCallback = nil
            Self._currentShortcutForTap = nil
            Self._tapShortcutSessionActive = false
            usesEventTap = false
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        currentShortcut = nil
        Self._currentShortcutForTap = nil
    }

    private func installEventTap() {
        Self._shouldHandleEventTapPressCallback = shouldHandleEventTapPress
        Self._onPressCallback = onPress
        Self._onReleaseCallback = onRelease

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(
                (1 << CGEventType.keyDown.rawValue) |
                (1 << CGEventType.flagsChanged.rawValue)
            ),
            callback: { proxy, type, event, refcon in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = HotkeyMonitor._activeTapPort {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard let shortcut = HotkeyMonitor.currentShortcutForTap() else {
                    return Unmanaged.passUnretained(event)
                }
                let flags = event.flags
                let keyCode = type == .keyDown
                    ? event.getIntegerValueField(.keyboardEventKeycode)
                    : nil
                let decision = HotkeyMonitor.eventTapDecision(
                    context: EventTapContext(
                        type: type,
                        keyCode: keyCode,
                        flags: flags,
                        shortcut: shortcut,
                        sessionActive: HotkeyMonitor._tapShortcutSessionActive
                    ),
                    shouldHandleMatchedPress: type == .keyDown
                        ? (HotkeyMonitor._shouldHandleEventTapPressCallback?() ?? false)
                        : false
                )

                switch decision {
                case .passThrough:
                    return Unmanaged.passUnretained(event)
                case .swallowMatchedPress:
                    HotkeyMonitor._tapShortcutSessionActive = true
                    if let onPress = HotkeyMonitor._onPressCallback {
                        DispatchQueue.main.async {
                            _ = onPress()
                        }
                    }
                    return nil
                case .emitRelease:
                    HotkeyMonitor._tapShortcutSessionActive = false
                    if let onRelease = HotkeyMonitor._onReleaseCallback {
                        DispatchQueue.main.async {
                            onRelease()
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }
            },
            userInfo: nil
        )
        guard let tap else { return }

        Self._activeTapPort = tap
        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        runLoopSource = source
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                monitor.handleHotKeyEvent(event)
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )
        if status != noErr {
            Log.ui.error("Failed to install hotkey event handler status=\(status)")
        }
    }

    private func uninstallEventHandler() {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func handleHotKeyEvent(_ event: EventRef) {
        var hk = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hk
        )
        guard status == noErr else { return }
        guard hk.signature == Self.signature, hk.id == Self.hotkeyId else { return }

        _ = onPress()
    }

    private nonisolated(unsafe) static var _currentShortcutForTap: HotkeyShortcut?

    private static func currentShortcutForTap() -> HotkeyShortcut? {
        _currentShortcutForTap
    }

    static func eventTapDecision(
        context: EventTapContext,
        shouldHandleMatchedPress: Bool
    ) -> EventTapDecision {
        guard let shortcut = context.shortcut else { return .passThrough }

        if context.type == .flagsChanged {
            return shouldReleaseEventTapSession(
                flags: context.flags,
                shortcut: shortcut,
                sessionActive: context.sessionActive
            ) ? .emitRelease : .passThrough
        }

        guard context.type == .keyDown, let keyCode = context.keyCode else { return .passThrough }
        guard matchesEventTapEvent(
            keyCode: keyCode,
            flags: context.flags,
            shortcut: shortcut
        ) else {
            return .passThrough
        }
        return shouldHandleMatchedPress ? .swallowMatchedPress : .passThrough
    }

    private static func shouldReleaseEventTapSession(
        flags: CGEventFlags,
        shortcut: HotkeyShortcut,
        sessionActive: Bool
    ) -> Bool {
        guard sessionActive else { return false }
        let activeModifiers = normalizedEventTapModifiers(flags)
        let requiredModifiers = normalizedEventTapModifiers(shortcut.modifiers)
        return !activeModifiers.isSuperset(of: requiredModifiers)
    }

    static func listenEventAccessGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    static func requestListenEventAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    static func matchesEventTapEvent(
        keyCode: Int64,
        flags: CGEventFlags,
        shortcut: HotkeyShortcut
    ) -> Bool {
        guard keyCode == Int64(shortcut.keyCode) else { return false }
        let active = normalizedEventTapModifiers(flags)
        let expected = normalizedEventTapModifiers(shortcut.modifiers)
        return active == expected
    }

    private static func normalizedEventTapModifiers(_ flags: CGEventFlags) -> CGEventFlags {
        let relevant: CGEventFlags = [
            .maskCommand,
            .maskControl,
            .maskAlternate,
            .maskShift
        ]
        return flags.intersection(relevant)
    }

    private static func normalizedEventTapModifiers(_ carbonModifiers: UInt32) -> CGEventFlags {
        var result: CGEventFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 {
            result.insert(.maskCommand)
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            result.insert(.maskControl)
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            result.insert(.maskAlternate)
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            result.insert(.maskShift)
        }
        return result
    }
}
