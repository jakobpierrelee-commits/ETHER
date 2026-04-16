import Foundation
import AppKit
import Carbon.HIToolbox

/// Registers global keyboard shortcuts via Carbon's HotKey API, so Ether can
/// respond even when another app is frontmost. Actions are wired to closures.
@MainActor
final class GlobalHotkeys: ObservableObject {

    @Published var bypassEnabled: Bool = true
    @Published var abToggleEnabled: Bool = true

    var onBypassToggle: (() -> Void)?
    var onABToggle: (() -> Void)?

    private var bypassRef: EventHotKeyRef?
    private var abToggleRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private static let signature: OSType = OSType(UInt32(truncatingIfNeeded: 0x45544852))   // 'ETHR'
    private static let bypassID: UInt32 = 1
    private static let abToggleID: UInt32 = 2

    /// Singleton callback access for the C handler
    private static weak var shared: GlobalHotkeys?

    func install() {
        Self.shared = self
        installEventHandler()
        registerAll()
    }

    func uninstall() {
        unregisterAll()
        if let h = eventHandler {
            RemoveEventHandler(h)
            eventHandler = nil
        }
        if Self.shared === self { Self.shared = nil }
    }

    deinit {
        // Non-isolated in deinit — safe cleanup only
        // Skipping full cleanup; app termination handles it.
    }

    // MARK: - Register / Unregister

    private func registerAll() {
        unregisterAll()
        if bypassEnabled {
            // ⌘⌥B
            bypassRef = register(keyCode: UInt32(kVK_ANSI_B),
                                 modifiers: UInt32(cmdKey | optionKey),
                                 id: Self.bypassID)
        }
        if abToggleEnabled {
            // ⌘⌥X
            abToggleRef = register(keyCode: UInt32(kVK_ANSI_X),
                                   modifiers: UInt32(cmdKey | optionKey),
                                   id: Self.abToggleID)
        }
    }

    private func unregisterAll() {
        if let r = bypassRef { UnregisterEventHotKey(r); bypassRef = nil }
        if let r = abToggleRef { UnregisterEventHotKey(r); abToggleRef = nil }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
        var hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }

    // MARK: - Event handler

    private func installEventHandler() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout.size(ofValue: hotKeyID),
                              nil,
                              &hotKeyID)
            Task { @MainActor in
                guard let shared = GlobalHotkeys.shared else { return }
                switch hotKeyID.id {
                case GlobalHotkeys.bypassID:    shared.onBypassToggle?()
                case GlobalHotkeys.abToggleID:  shared.onABToggle?()
                default:                        break
                }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(),
                            handler,
                            1,
                            &spec,
                            nil,
                            &eventHandler)
    }

    /// Re-register after user toggles on/off
    func refresh() { registerAll() }
}
