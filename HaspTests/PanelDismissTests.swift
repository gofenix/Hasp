import AppKit

@MainActor final class EventGate {
    var point = CGPoint(x: 100, y: 100)
    var global: ((NSEvent) -> Void)?
    var local: ((NSEvent) -> NSEvent?)?
    var notes: [Notification.Name: (PanelDismissNotice) -> Void] = [:]
    var registrations = 0
    var removals = 0
    var source: PanelDismissEventSource {
        PanelDismissEventSource(globalMouse: { handler in
            self.global = handler; self.registrations += 1
            return { self.global = nil; self.removals += 1 }
        }, localInput: { handler in
            self.local = handler; self.registrations += 1
            return { self.local = nil; self.removals += 1 }
        }, notification: { name, _, handler in
            self.notes[name] = handler; self.registrations += 1
            return { self.notes[name] = nil; self.removals += 1 }
        })
    }
    func send(_ name: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        notes[name]?(PanelDismissNotice(Notification(name: name, object: object, userInfo: userInfo)))
    }
}

@main enum PanelDismissTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let gate = EventGate()
        var monitor: PanelDismissMonitor? = PanelDismissMonitor(source: gate.source, mouseLocation: { gate.point })
        var closes = 0
        func start() {
            monitor!.start(isPanelWindow: { _ in false },
                           containsPanelPoint: { CGRect(x: 50, y: 50, width: 200, height: 300).contains($0) },
                           containsEntryPoint: { CGRect(x: 100, y: 400, width: 40, height: 24).contains($0) },
                           containsMenuPoint: { CGRect(x: 250, y: 100, width: 100, height: 200).contains($0) },
                           close: { closes += 1 })
        }
        let mouse = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!

        start()
        precondition(closes == 0, "Do not close simply because another app was already active at opening")
        precondition(gate.local?(mouse) === mouse && closes == 0, "Internal clicks stay open and pass through")
        gate.point = CGPoint(x: 110, y: 410)
        gate.global?(mouse)
        precondition(gate.local?(mouse) === mouse && closes == 0, "A status-icon down must not close before its toggle on up")
        gate.point = CGPoint(x: 800, y: 500)
        precondition(gate.local?(mouse) === mouse && closes == 1, "Outside local clicks close without swallowing the target click")
        gate.global?(mouse)
        precondition(closes == 1, "Duplicate native/global signals close only once")

        start()
        let menu = NSMenu(), submenu = NSMenu()
        gate.send(NSMenu.didBeginTrackingNotification, object: menu)
        gate.send(NSMenu.didBeginTrackingNotification, object: submenu)
        precondition(gate.local?(escape) === escape && closes == 1, "Esc belongs to an open submenu first")
        gate.point = CGPoint(x: 300, y: 150)
        gate.global?(mouse)
        precondition(gate.local?(mouse) === mouse && closes == 1, "A native dropdown outside the panel is still part of the interaction")
        gate.send(NSMenu.didEndTrackingNotification, object: submenu)
        precondition(gate.local?(escape) === escape && closes == 1)
        gate.send(NSMenu.didEndTrackingNotification, object: menu)
        precondition(gate.local?(escape) == nil && closes == 2, "Esc closes the panel once menus have finished")

        start()
        gate.send(NSMenu.didBeginTrackingNotification, object: menu)
        gate.point = CGPoint(x: 900, y: 500)
        gate.global?(mouse)
        precondition(closes == 3, "Clicking another app closes both the panel interaction and an open menu")

        start()
        gate.send(NSWorkspace.didActivateApplicationNotification,
                  userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        precondition(closes == 3, "Own activation is not an outside switch")
        if let other = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier != getpid() }) {
            gate.send(NSWorkspace.didActivateApplicationNotification, userInfo: [NSWorkspace.applicationUserInfoKey: other])
            precondition(closes == 4, "Switching apps closes without a global keyboard monitor")
        } else { preconditionFailure("Expected another running application") }

        start()
        let staleGlobal = gate.global
        let staleActivation = gate.notes[NSApplication.didResignActiveNotification]
        start()
        staleGlobal?(mouse)
        staleActivation?(PanelDismissNotice(Notification(name: NSApplication.didResignActiveNotification)))
        precondition(closes == 4, "A stale callback must not close a newly reopened panel")
        gate.send(NSWorkspace.activeSpaceDidChangeNotification)
        precondition(closes == 5)
        monitor!.stop()
        precondition(gate.registrations == gate.removals && gate.notes.isEmpty && gate.local == nil && gate.global == nil)
        for _ in 0..<100 { start(); monitor!.stop() }
        precondition(gate.registrations == gate.removals, "Repeated opens cannot accumulate passive monitors")
        start()
        monitor = nil
        precondition(gate.registrations == gate.removals, "Deinit cleans up remaining monitors")
        print("Panel dismissal passed: outside mouse delivery unchanged; icon toggle protected; nested menus and Esc; app/Space changes; stale callback isolation; 100 lifecycle cycles. No windows shown or input posted.")
    }
}
