import AppKit
import Carbon
import Foundation

@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    var onTogglePanel: (@MainActor () -> Void)?
    var onJumpMostUrgent: (@MainActor () -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var toggleHotKeyRef: EventHotKeyRef?
    private var jumpHotKeyRef: EventHotKeyRef?

    // Signature 'AGMT' = 0x41474D54
    private static let signature: OSType = 0x4147_4D54
    private static let toggleHotKeyID: UInt32 = 1
    private static let jumpHotKeyID: UInt32 = 2

    private init() {}

    func setEnabled(_ enabled: Bool) {
        if enabled {
            registerHotKeys()
        } else {
            unregisterHotKeys()
        }
    }

    func registerHotKeys() {
        unregisterHotKeys()

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == GlobalHotKeyManager.signature else {
                return OSStatus(eventNotHandledErr)
            }

            let id = hotKeyID.id
            Task { @MainActor in
                switch id {
                case GlobalHotKeyManager.toggleHotKeyID:
                    GlobalHotKeyManager.shared.onTogglePanel?()
                case GlobalHotKeyManager.jumpHotKeyID:
                    GlobalHotKeyManager.shared.onJumpMostUrgent?()
                default:
                    break
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )

        // 1. ⌥ + Space (Option + Space): Toggle panel open/close
        let toggleID = EventHotKeyID(signature: Self.signature, id: Self.toggleHotKeyID)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            toggleID,
            GetApplicationEventTarget(),
            0,
            &toggleHotKeyRef
        )

        // 2. ⌥ + Return (Option + Return): Jump straight to the #1 most urgent Agent session
        let jumpID = EventHotKeyID(signature: Self.signature, id: Self.jumpHotKeyID)
        RegisterEventHotKey(
            UInt32(kVK_Return),
            UInt32(optionKey),
            jumpID,
            GetApplicationEventTarget(),
            0,
            &jumpHotKeyRef
        )
    }

    func unregisterHotKeys() {
        if let toggleHotKeyRef {
            UnregisterEventHotKey(toggleHotKeyRef)
            self.toggleHotKeyRef = nil
        }
        if let jumpHotKeyRef {
            UnregisterEventHotKey(jumpHotKeyRef)
            self.jumpHotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
