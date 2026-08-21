import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = KeyboardShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    var displayString: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        value += Self.keyName(for: keyCode)
        return value
    }

    static func from(event: NSEvent) -> KeyboardShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        guard carbonFlags != 0 else { return nil }
        return KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: carbonFlags)
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "Esc", UInt32(kVK_Delete): "⌫", UInt32(kVK_ANSI_A): "A",
            UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F", UInt32(kVK_ANSI_G): "G",
            UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L", UInt32(kVK_ANSI_M): "M",
            UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R", UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X", UInt32(kVK_ANSI_Y): "Y",
            UInt32(kVK_ANSI_Z): "Z", UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4",
            UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

enum ModifierKind: String, CaseIterable, Codable {
    case command
    case option
    case control
    case shift

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }

    var cgEventFlag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .option: .maskAlternate
        case .control: .maskControl
        case .shift: .maskShift
        }
    }

    var doubleTapMode: ActivationShortcutMode {
        switch self {
        case .command: .doubleCommand
        case .option: .doubleOption
        case .control: .doubleControl
        case .shift: .doubleShift
        }
    }

    var bothSidesMode: ActivationShortcutMode {
        switch self {
        case .command: .bothCommandKeys
        case .option: .bothOptionKeys
        case .control: .bothControlKeys
        case .shift: .bothShiftKeys
        }
    }
}

enum ActivationShortcutMode: String, CaseIterable, Codable, Identifiable {
    case keyboard
    case doubleCommand
    case doubleOption
    case doubleControl
    case doubleShift
    case bothCommandKeys
    case bothOptionKeys
    case bothControlKeys
    case bothShiftKeys

    var id: Self { self }

    var displayName: String {
        switch self {
        case .keyboard: "Keyboard shortcut"
        case .doubleCommand: "Double-tap ⌘"
        case .doubleOption: "Double-tap ⌥"
        case .doubleControl: "Double-tap ⌃"
        case .doubleShift: "Double-tap ⇧"
        case .bothCommandKeys: "Left + right ⌘"
        case .bothOptionKeys: "Left + right ⌥"
        case .bothControlKeys: "Left + right ⌃"
        case .bothShiftKeys: "Left + right ⇧"
        }
    }

    var modifierGesture: ModifierGesture? {
        switch self {
        case .keyboard: nil
        case .doubleCommand: .doubleTap(.command)
        case .doubleOption: .doubleTap(.option)
        case .doubleControl: .doubleTap(.control)
        case .doubleShift: .doubleTap(.shift)
        case .bothCommandKeys: .bothSides(.command)
        case .bothOptionKeys: .bothSides(.option)
        case .bothControlKeys: .bothSides(.control)
        case .bothShiftKeys: .bothSides(.shift)
        }
    }
}

struct ActivationShortcut: Codable, Equatable {
    var mode: ActivationShortcutMode
    var keyboardShortcut: KeyboardShortcut

    static let `default` = ActivationShortcut(mode: .keyboard, keyboardShortcut: .default)

    var displayString: String {
        mode == .keyboard ? keyboardShortcut.displayString : mode.displayName
    }
}

enum ActivationShortcutStorage {
    static let defaultsKey = "activationShortcut"
    static let legacyDefaultsKey = "globalShortcut"

    static func load(from defaults: UserDefaults = .standard) -> ActivationShortcut {
        if let data = defaults.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(ActivationShortcut.self, from: data) {
            return saved
        }
        if let data = defaults.data(forKey: legacyDefaultsKey),
           let legacyShortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            return ActivationShortcut(mode: .keyboard, keyboardShortcut: legacyShortcut)
        }
        return .default
    }

    static func save(_ shortcut: ActivationShortcut, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

enum ModifierGesture: Equatable {
    case doubleTap(ModifierKind)
    case bothSides(ModifierKind)
}

enum PhysicalModifier: UInt16, CaseIterable {
    case leftCommand = 55
    case rightCommand = 54
    case leftShift = 56
    case rightShift = 60
    case leftOption = 58
    case rightOption = 61
    case leftControl = 59
    case rightControl = 62

    var kind: ModifierKind {
        switch self {
        case .leftCommand, .rightCommand: .command
        case .leftOption, .rightOption: .option
        case .leftControl, .rightControl: .control
        case .leftShift, .rightShift: .shift
        }
    }
}

struct ModifierGestureRecognizer {
    private struct Tap {
        let key: PhysicalModifier
        let startedAt: TimeInterval
        let completesDoubleTap: Bool
    }

    private let gesture: ModifierGesture
    private let maximumTapDuration: TimeInterval
    private let maximumTimeBetweenTaps: TimeInterval
    private var pressedKeys = Set<PhysicalModifier>()
    private var activeTap: Tap?
    private var lastTapEndedAt: TimeInterval?
    private var chordIsLatched = false

    init(
        gesture: ModifierGesture,
        maximumTapDuration: TimeInterval = 0.35,
        maximumTimeBetweenTaps: TimeInterval = 0.40
    ) {
        self.gesture = gesture
        self.maximumTapDuration = maximumTapDuration
        self.maximumTimeBetweenTaps = maximumTimeBetweenTaps
    }

    mutating func flagsChanged(
        key: PhysicalModifier,
        modifierIsActive: Bool,
        timestamp: TimeInterval
    ) -> Bool {
        let wasPressed = pressedKeys.contains(key)
        // A modifier flag remains active while either physical key is down. Toggling
        // a key already in our set therefore represents its key-up transition.
        let isKeyDown = modifierIsActive && !wasPressed
        if isKeyDown {
            pressedKeys.insert(key)
        } else {
            pressedKeys.remove(key)
        }

        switch gesture {
        case .doubleTap(let kind):
            return recognizeDoubleTap(of: kind, key: key, isKeyDown: isKeyDown, timestamp: timestamp)
        case .bothSides(let kind):
            return recognizeBothSides(of: kind, changedKey: key, isKeyDown: isKeyDown)
        }
    }

    mutating func interrupt() {
        activeTap = nil
        lastTapEndedAt = nil
    }

    private mutating func recognizeDoubleTap(
        of kind: ModifierKind,
        key: PhysicalModifier,
        isKeyDown: Bool,
        timestamp: TimeInterval
    ) -> Bool {
        guard key.kind == kind else {
            interrupt()
            return false
        }

        if isKeyDown {
            guard pressedKeys.count == 1 else {
                interrupt()
                return false
            }
            let completesDoubleTap = lastTapEndedAt.map {
                timestamp - $0 <= maximumTimeBetweenTaps
            } ?? false
            activeTap = Tap(key: key, startedAt: timestamp, completesDoubleTap: completesDoubleTap)
            return false
        }

        guard let activeTap, activeTap.key == key, pressedKeys.isEmpty else {
            interrupt()
            return false
        }
        self.activeTap = nil
        guard timestamp - activeTap.startedAt <= maximumTapDuration else {
            lastTapEndedAt = nil
            return false
        }
        if activeTap.completesDoubleTap {
            lastTapEndedAt = nil
            return true
        }
        lastTapEndedAt = timestamp
        return false
    }

    private mutating func recognizeBothSides(
        of kind: ModifierKind,
        changedKey: PhysicalModifier,
        isKeyDown: Bool
    ) -> Bool {
        let requiredKeys = Set(PhysicalModifier.allCases.filter { $0.kind == kind })
        if !requiredKeys.isSubset(of: pressedKeys) {
            chordIsLatched = false
        }
        guard isKeyDown,
              changedKey.kind == kind,
              pressedKeys == requiredKeys,
              !chordIsLatched else { return false }
        chordIsLatched = true
        return true
    }
}

struct ShortcutCaptureRecognizer {
    private struct Tap {
        let key: PhysicalModifier
        let startedAt: TimeInterval
        let completesDoubleTap: Bool
    }

    private struct CompletedTap {
        let kind: ModifierKind
        let endedAt: TimeInterval
    }

    private let maximumTapDuration: TimeInterval
    private let maximumTimeBetweenTaps: TimeInterval
    private var pressedKeys = Set<PhysicalModifier>()
    private var activeTap: Tap?
    private var completedTap: CompletedTap?

    init(
        maximumTapDuration: TimeInterval = 0.35,
        maximumTimeBetweenTaps: TimeInterval = 0.40
    ) {
        self.maximumTapDuration = maximumTapDuration
        self.maximumTimeBetweenTaps = maximumTimeBetweenTaps
    }

    mutating func flagsChanged(
        key: PhysicalModifier,
        modifierIsActive: Bool,
        timestamp: TimeInterval
    ) -> ActivationShortcutMode? {
        let wasPressed = pressedKeys.contains(key)
        let isKeyDown = modifierIsActive && !wasPressed
        if isKeyDown {
            pressedKeys.insert(key)
        } else {
            pressedKeys.remove(key)
        }

        if isKeyDown {
            let kinds = Set(pressedKeys.map(\.kind))
            if pressedKeys.count == 2, kinds.count == 1, let kind = kinds.first {
                clearTapSequence()
                return kind.bothSidesMode
            }

            guard pressedKeys.count == 1 else {
                clearTapSequence()
                return nil
            }
            let completesDoubleTap = completedTap.map {
                $0.kind == key.kind && timestamp - $0.endedAt <= maximumTimeBetweenTaps
            } ?? false
            activeTap = Tap(key: key, startedAt: timestamp, completesDoubleTap: completesDoubleTap)
            return nil
        }

        guard let activeTap, activeTap.key == key, pressedKeys.isEmpty else {
            clearTapSequence()
            return nil
        }
        self.activeTap = nil
        guard timestamp - activeTap.startedAt <= maximumTapDuration else {
            completedTap = nil
            return nil
        }
        if activeTap.completesDoubleTap {
            completedTap = nil
            return key.kind.doubleTapMode
        }
        completedTap = CompletedTap(kind: key.kind, endedAt: timestamp)
        return nil
    }

    mutating func interrupt() {
        clearTapSequence()
    }

    private mutating func clearTapSequence() {
        activeTap = nil
        completedTap = nil
    }
}

private var hotKeyAction: (() -> Void)?

private let modifierEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Task { @MainActor [weak manager] in manager?.enableModifierEventTap() }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let timestamp = TimeInterval(event.timestamp) / 1_000_000_000
    Task { @MainActor [weak manager] in
        manager?.handleModifierEvent(type: type, keyCode: keyCode, flags: flags, timestamp: timestamp)
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var modifierEventTap: CFMachPort?
    private var modifierRunLoopSource: CFRunLoopSource?
    private var modifierRecognizer: ModifierGestureRecognizer?
    private var registeredShortcut: ActivationShortcut
    private var isSuspended = false
    private var isWaitingForModifierRelease = false
    private let action: () -> Void

    init(shortcut: ActivationShortcut, action: @escaping () -> Void) {
        registeredShortcut = shortcut
        self.action = action
        hotKeyAction = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { hotKeyAction?() }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        register(shortcut)
    }

    func register(_ shortcut: ActivationShortcut) {
        registeredShortcut = shortcut
        guard !isSuspended else { return }
        isWaitingForModifierRelease = false
        apply(shortcut)
    }

    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        if suspended {
            isWaitingForModifierRelease = false
            unregisterCurrentShortcut()
        } else {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let trackedFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            isWaitingForModifierRelease = registeredShortcut.mode != .keyboard
                && !flags.intersection(trackedFlags).isEmpty
            apply(registeredShortcut)
        }
    }

    private func apply(_ shortcut: ActivationShortcut) {
        unregisterCurrentShortcut()

        if shortcut.mode == .keyboard {
            let identifier = EventHotKeyID(signature: OSType(0x4B56545A), id: 1) // KVTZ
            RegisterEventHotKey(
                shortcut.keyboardShortcut.keyCode,
                shortcut.keyboardShortcut.modifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &hotKey
            )
        } else if let gesture = shortcut.mode.modifierGesture {
            modifierRecognizer = ModifierGestureRecognizer(gesture: gesture)
            installModifierEventTap()
        }
    }

    fileprivate func handleModifierEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        timestamp: TimeInterval
    ) {
        if isWaitingForModifierRelease {
            let trackedFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            if flags.intersection(trackedFlags).isEmpty {
                isWaitingForModifierRelease = false
            }
            return
        }
        guard var recognizer = modifierRecognizer else { return }
        let shouldActivate: Bool
        if type == .keyDown {
            recognizer.interrupt()
            shouldActivate = false
        } else if type == .flagsChanged, let modifier = PhysicalModifier(rawValue: keyCode) {
            shouldActivate = recognizer.flagsChanged(
                key: modifier,
                modifierIsActive: flags.contains(modifier.kind.cgEventFlag),
                timestamp: timestamp
            )
        } else {
            recognizer.interrupt()
            shouldActivate = false
        }
        modifierRecognizer = recognizer
        if shouldActivate { action() }
    }

    fileprivate func enableModifierEventTap() {
        if let modifierEventTap {
            CGEvent.tapEnable(tap: modifierEventTap, enable: true)
        }
    }

    private func installModifierEventTap() {
        guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else { return }
        let eventMask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: modifierEventTapCallback,
            userInfo: pointer
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        modifierEventTap = tap
        modifierRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func unregisterCurrentShortcut() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let modifierRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), modifierRunLoopSource, .commonModes)
            self.modifierRunLoopSource = nil
        }
        if let modifierEventTap {
            CFMachPortInvalidate(modifierEventTap)
            self.modifierEventTap = nil
        }
        modifierRecognizer = nil
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let modifierRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), modifierRunLoopSource, .commonModes)
        }
        if let modifierEventTap { CFMachPortInvalidate(modifierEventTap) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
