import Foundation
import Carbon.HIToolbox

struct Shortcut: Equatable {
    var key: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if command { flags |= UInt32(cmdKey) }
        if shift { flags |= UInt32(shiftKey) }
        if option { flags |= UInt32(optionKey) }
        if control { flags |= UInt32(controlKey) }
        return flags
    }

    var displayString: String {
        let pieces = [
            command ? "⌘" : nil,
            shift ? "⇧" : nil,
            option ? "⌥" : nil,
            control ? "⌃" : nil,
            key.uppercased()
        ].compactMap { $0 }

        return pieces.joined()
    }
}

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    init() {
        installHandlerIfNeeded()
    }

    deinit {
        unregister()
    }

    func register(shortcut: Shortcut, action: @escaping () -> Void) {
        unregister()
        self.action = action

        guard let keyCode = Self.keyCode(for: shortcut.key) else {
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D434C50), id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            print("Unable to register hotkey: \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.action?()
                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
    }

    private static func keyCode(for key: String) -> UInt32? {
        let map: [String: UInt32] = [
            "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5,
            "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12,
            "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27,
            "8": 28, "0": 29, "]": 30, "O": 31, "U": 32,
            "[": 33, "I": 34, "P": 35, "L": 37, "J": 38,
            "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43,
            "/": 44, "N": 45, "M": 46, ".": 47
        ]

        return map[key.uppercased()]
    }
}
