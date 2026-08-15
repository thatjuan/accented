import AppKit
import Carbon.HIToolbox
import os

/// Registers global hotkeys via Carbon `RegisterEventHotKey`.
///
/// Chosen over a `CGEventTap` so the trigger needs no Input Monitoring permission, adds no
/// per-keystroke latency, and still fires in secure-input fields. See
/// `docs/decisions/0001-carbon-hotkey.md`.
///
/// The API takes a `[Hotkey.Slot: Hotkey]` map so a second binding stays cheap. v1 registers
/// only `.picker`. Fire is a closure (same style as the status item); `AppCoordinator` points
/// it at `showPicker()`.
///
/// Persistence is `UserDefaults` (`settings.hotkeyKeyCode` / `settings.hotkeyModifiers`) until
/// `SettingsStore` (#8) owns it. The manager re-reads those keys when they change so
/// `defaults write` or the stub recorder re-registers without a relaunch.
@MainActor
final class HotkeyManager {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "Hotkey")
    private let defaults: UserDefaults

    /// Invoked on the main actor when a registered slot fires.
    var onFire: ((Hotkey.Slot) -> Void)?

    private var hotKeyRefs: [Hotkey.Slot: EventHotKeyRef] = [:]
    private var registered: [Hotkey.Slot: Hotkey] = [:]
    private var handlerRef: EventHandlerRef?
    private var defaultsObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var sequencer = DoubleTapSequencer()

    /// Carbon signature for our `EventHotKeyID`s (`acnt`).
    private static let signature: OSType = 0x61636E74

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    deinit {
        // Carbon refs must be released even if `stop()` was skipped (process teardown).
        for ref in hotKeyRefs.values { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func start() {
        installHandlerIfNeeded()
        reloadFromDefaults()
        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadFromDefaults() }
            }
        }
        // `defaults write` from another process does not always post didChangeNotification.
        // A cheap poll keeps the acceptance ("re-register without relaunch") honest.
        if pollTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadFromDefaults() }
            }
            timer.tolerance = 0.5
            pollTimer = timer
        }
        logger.info("Hotkey manager started — \(self.registered[.picker]?.displayString ?? "none", privacy: .public)")
    }

    /// Unregister everything. Call from `applicationWillTerminate` so a quit leaves no ghost.
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        unregisterAll()
        setDoubleTap(.off)
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        logger.info("Hotkey manager stopped")
    }

    /// Install or tear down the `flagsChanged` monitors. Default is off.
    func setDoubleTap(_ mode: DoubleTapModifier) {
        let kind = mode.kind
        if sequencer.watching == kind, (globalMonitor != nil) == (kind != nil) {
            return
        }
        tearDownMonitors()
        sequencer = DoubleTapSequencer()
        sequencer.watching = kind
        guard kind != nil else {
            logger.info("Double-tap trigger off")
            return
        }
        installMonitors()
        logger.info("Double-tap trigger \(mode.label, privacy: .public)")
    }

    /// Replace the registered set. Empty map unregisters. Unknown / deny-listed combos are logged
    /// and skipped rather than registered.
    func register(_ bindings: [Hotkey.Slot: Hotkey]) {
        if bindings == registered { return }
        unregisterAll()
        for (slot, hotkey) in bindings {
            if let denial = hotkey.denial() {
                logger.error("Refusing to register \(slot.rawValue, privacy: .public): \(String(describing: denial), privacy: .public)")
                continue
            }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: slot.carbonID)
            let status = RegisterEventHotKey(
                hotkey.keyCode,
                hotkey.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status != noErr {
                logger.error("RegisterEventHotKey failed for \(slot.rawValue, privacy: .public) status=\(status, privacy: .public)")
                continue
            }
            hotKeyRefs[slot] = ref
            registered[slot] = hotkey
            logger.info("Registered \(slot.rawValue, privacy: .public) as \(hotkey.displayString, privacy: .public)")
        }
    }

    func reloadFromDefaults() {
        let loaded = HotkeyDefaults.load(from: defaults)
        register([.picker: loaded])
    }

    // MARK: - Carbon handler

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let unmanaged = Unmanaged.passUnretained(self)
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            unmanaged.toOpaque(),
            &handlerRef
        )
        if status != noErr {
            logger.error("InstallEventHandler failed status=\(status, privacy: .public)")
        }
    }

    fileprivate func handleCarbonFire(hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == Self.signature else { return }
        guard let slot = Hotkey.Slot.allCases.first(where: { $0.carbonID == hotKeyID.id }) else {
            logger.error("Hotkey fired with unknown id \(hotKeyID.id, privacy: .public)")
            return
        }
        logger.info("Hotkey fired (\(slot.rawValue, privacy: .public), \(self.registered[slot]?.displayString ?? "?", privacy: .public))")
        onFire?(slot)
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMonitorEvent(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMonitorEvent(event) }
            return event
        }
    }

    private func tearDownMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleMonitorEvent(_ event: NSEvent) {
        let result: DoubleTapSequencer.Result
        if event.type == .flagsChanged, let kind = DoubleTapSequencer.kind(forKeyCode: event.keyCode) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            result = sequencer.noteFlags(kind: kind, isDown: DoubleTapSequencer.isDown(kind, flags: flags), at: event.timestamp)
        } else if event.type == .flagsChanged {
            result = sequencer.noteOther()
        } else {
            result = sequencer.noteOther()
        }
        switch result {
        case .none:
            break
        case .fire:
            logger.info("Double-tap fired")
            onFire?(.picker)
        case .reset(let reason):
            logger.debug("Double-tap reset (\(reason, privacy: .public))")
        }
    }

    private func unregisterAll() {
        for (slot, ref) in hotKeyRefs {
            let status = UnregisterEventHotKey(ref)
            if status != noErr {
                logger.error("UnregisterEventHotKey \(slot.rawValue, privacy: .public) status=\(status, privacy: .public)")
            }
        }
        hotKeyRefs.removeAll()
        registered.removeAll()
    }
}

/// C callback installed once. `userData` is an unretained `HotkeyManager`.
private func hotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
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
    guard status == noErr else { return status }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.handleCarbonFire(hotKeyID: hotKeyID)
    }
    return noErr
}
