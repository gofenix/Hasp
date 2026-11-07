import AppKit

/// Copy only the notification identity needed for dismissal across isolation.
struct PanelDismissNotice: Sendable {
    let menuID: ObjectIdentifier?
    let processID: pid_t?
    init(_ note: Notification) {
        menuID = (note.object as? NSMenu).map(ObjectIdentifier.init)
        processID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }
}

/// Event observation is passive: global events cannot be changed, and local
/// mouse events are always returned unchanged to their original destination.
@MainActor struct PanelDismissEventSource {
    enum Center { case application, workspace }
    var globalMouse: (@escaping (NSEvent) -> Void) -> (() -> Void)
    var localInput: (@escaping (NSEvent) -> NSEvent?) -> (() -> Void)
    var notification: (Notification.Name, Center, @escaping @MainActor @Sendable (PanelDismissNotice) -> Void) -> (() -> Void)

    static var live: Self {
        Self(globalMouse: { handler in
            let token = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
                MainActor.assumeIsolated { handler(event) }
            }
            return { if let token { NSEvent.removeMonitor(token) } }
        }, localInput: { handler in
            let token = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { event in
                var result: NSEvent?
                MainActor.assumeIsolated { result = handler(event) }
                return result
            }
            return { if let token { NSEvent.removeMonitor(token) } }
        }, notification: { name, center, handler in
            let notifications = center == .workspace ? NSWorkspace.shared.notificationCenter : NotificationCenter.default
            let token = notifications.addObserver(forName: name, object: nil, queue: .main) { note in
                let notice = PanelDismissNotice(note)
                MainActor.assumeIsolated { handler(notice) }
            }
            return { notifications.removeObserver(token) }
        })
    }
}

@MainActor final class PanelDismissMonitor {
    private let source: PanelDismissEventSource
    private let mouseLocation: () -> CGPoint
    private var cleanups: [() -> Void] = []
    private var session = 0
    private var requestedClose = false
    private var menus = Set<ObjectIdentifier>()

    init(source: PanelDismissEventSource? = nil, mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.source = source ?? .live
        self.mouseLocation = mouseLocation
    }

    func start(isPanelWindow: @escaping (NSWindow?) -> Bool,
               containsPanelPoint: @escaping (CGPoint) -> Bool,
               containsEntryPoint: @escaping (CGPoint) -> Bool,
               containsMenuPoint: @escaping (CGPoint) -> Bool = { _ in false },
               close: @escaping () -> Void) {
        stop()
        let activeSession = session
        let dismiss: () -> Void = { [weak self] in
            guard let self, self.session == activeSession, !self.requestedClose else { return }
            self.requestedClose = true
            close()
        }
        cleanups.append(source.globalMouse { [weak self] _ in
            guard let self, self.session == activeSession else { return }
            let point = self.mouseLocation()
            if !self.menus.isEmpty, containsMenuPoint(point) { return }
            // The menu-bar agent may deliver the down outside our process and
            // the up to our status button. Let that button toggle only once.
            guard !containsEntryPoint(point), !containsPanelPoint(point) else { return }
            dismiss()
        })
        cleanups.append(source.localInput { [weak self] event in
            guard let self, self.session == activeSession else { return event }
            if event.type == .keyDown {
                // Esc first belongs to an open submenu. No global keyboard
                // monitor is installed, so another app's Esc stays untouched.
                if event.keyCode == 53, self.menus.isEmpty { dismiss(); return nil }
                return event
            }
            guard self.menus.isEmpty else { return event }
            let point = self.mouseLocation()
            if !isPanelWindow(event.window), !containsPanelPoint(point), !containsEntryPoint(point) { dismiss() }
            return event
        })
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            cleanups.append(source.notification(name, .application) { [weak self] note in
                guard let self, self.session == activeSession, let id = note.menuID else { return }
                if name == NSMenu.didBeginTrackingNotification { self.menus.insert(id) }
                else { self.menus.remove(id) }
            })
        }
        cleanups.append(source.notification(NSWorkspace.didActivateApplicationNotification, .workspace) { note in
            guard let pid = note.processID, pid != ProcessInfo.processInfo.processIdentifier else { return }
            dismiss()
        })
        for (name, center) in [
            (NSApplication.didResignActiveNotification, PanelDismissEventSource.Center.application),
            (NSWorkspace.activeSpaceDidChangeNotification, .workspace),
            (NSWorkspace.willSleepNotification, .workspace),
            (NSWorkspace.sessionDidResignActiveNotification, .workspace)
        ] {
            cleanups.append(source.notification(name, center) { _ in dismiss() })
        }
    }

    func stop() {
        session += 1
        let previous = cleanups
        cleanups.removeAll()
        previous.forEach { $0() }
        requestedClose = false
        menus.removeAll()
    }

    isolated deinit { cleanups.forEach { $0() } }
}
