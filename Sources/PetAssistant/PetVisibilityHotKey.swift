import Carbon
import Foundation

/// 全局快捷键 ⌃⌥⌘P；注册专用按键组合，不监听其他键盘输入。
@MainActor
final class PetVisibilityHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: @MainActor () -> Void
    private(set) var isRegistered = false

    init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &key
            )
            guard status == noErr, key.signature == 0x50455441, key.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let owner = Unmanaged<PetVisibilityHotKey>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in owner.onPress() }
            return noErr
        }, 1, &eventType, context, &handler)
        guard installed == noErr else { return }
        let key = EventHotKeyID(signature: 0x50455441, id: 1)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        isRegistered = RegisterEventHotKey(
            UInt32(kVK_ANSI_P), modifiers, key, GetApplicationEventTarget(), 0, &hotKey
        ) == noErr
        if !isRegistered, let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
