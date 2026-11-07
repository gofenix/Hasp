import AppKit
import ApplicationServices
import OSLog

private struct MenuPresentationSnapshot {
    var visibility: NativeMenuVisibility
    var windows: [CGWindowID: CGRect]
    var windowServerAvailable: Bool
    var targetFrame: CGRect?
    var targetTerminated: Bool
}

/// All remote AX/window queries run on a worker. Electron tray elements can
/// live in a helper while their native menus belong to the main application.
/// Immutable native handles; each session serializes scan/press operations.
private final class MenuPresentationProbe: @unchecked Sendable {
    let target: MenuBarTarget
    let applications: [AXUIElement]
    let pids: Set<pid_t>

    init(target: MenuBarTarget) {
        self.target = target
        let owner = NSRunningApplication(processIdentifier: target.pid).flatMap(MenuBarCensus.ownerApplicationURL)
        var family = Set<pid_t>([target.pid])
        if let owner {
            for app in NSWorkspace.shared.runningApplications where MenuBarCensus.ownerApplicationURL(app) == owner {
                family.insert(app.processIdentifier)
            }
        }
        pids = family
        applications = family.map { pid in
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 0.1)
            return root
        }
    }

    func windows() -> [CGWindowID: CGRect]? {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
        var result: [CGWindowID: CGRect] = [:]
        for info in list {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(pid),
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.height > 35 else { continue }
            result[number.uint32Value] = rect
        }
        return result
    }

    func scan(baseline: Set<CGWindowID>) -> MenuPresentationSnapshot {
        let current = windows()
        let popups = current?.filter { !baseline.contains($0.key) } ?? [:]
        var visibility: NativeMenuVisibility = current == nil ? .unknown : .absent
        if !popups.isEmpty {
            visibility = .visible
        } else {
            for application in applications {
                var budget = 32
                switch hasMenu(application, depth: 0, budget: &budget) {
                case true?: visibility = .visible
                case nil: if visibility != .visible { visibility = .unknown }
                default: break
                }
            }
        }
        var frame: CGRect?
        if let value = MenuBarCensus.attribute(target.element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() {
            var rect = CGRect.zero
            if AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgRect, &rect) { frame = rect }
        }
        return MenuPresentationSnapshot(visibility: visibility, windows: popups, windowServerAvailable: current != nil,
            targetFrame: frame, targetTerminated: NSRunningApplication(processIdentifier: target.pid)?.isTerminated != false)
    }

    private func hasMenu(_ element: AXUIElement, depth: Int, budget: inout Int) -> Bool? {
        guard depth < 3, budget > 0 else { return nil }
        budget -= 1
        guard let role = MenuBarCensus.attribute(element, kAXRoleAttribute) as? String else { return nil }
        if role == kAXMenuBarRole { return false }
        if role == kAXMenuRole { return true }
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw)
        if error == .attributeUnsupported { return false }
        guard error == .success, let children = raw as? [AXUIElement] else { return nil }
        var unknown = false
        for child in children {
            if budget <= 0 { return nil }
            switch hasMenu(child, depth: depth + 1, budget: &budget) {
            case true?: return true
            case nil: unknown = true
            default: break
            }
        }
        return unknown ? nil : false
    }
}

@MainActor
final class MenuBarInteraction {
    private let probe: MenuPresentationProbe
    private var observers: [AXObserver] = []
    private var timer: Timer?
    private var monitors: [Any] = []
    private var state = NativeMenuSessionState()
    private var baselineWindows = Set<CGWindowID>()
    private var lastSnapshot: MenuPresentationSnapshot?
    private var probePending = false
    private var didObservePopupWindow = false
    private var outsideInteraction = false
    private var active = false
    private let onFinish: (String?) -> Void
    private let logger = Logger(subsystem: "app.hasp.menu", category: "NativeMenu")

    init(target: MenuBarTarget, onFinish: @escaping (String?) -> Void) {
        probe = MenuPresentationProbe(target: target)
        self.onFinish = onFinish
    }

    func start() {
        active = true
        let probe = self.probe
        Task.detached { [weak self] in
            guard let self else { return }
            let context = Unmanaged.passUnretained(self).toOpaque()
            let baseline = Set((probe.windows() ?? [:]).keys)
            let observers = Self.makeObservers(probe: probe, context: context)
            await self.prepared(observers: observers, baseline: baseline)
        }
    }

    private func prepared(observers: sending [AXObserver], baseline: Set<CGWindowID>) {
        guard active else { return }
        self.observers = observers
        baselineWindows = baseline
        for observer in observers {
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        installMonitors()
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestProbe() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        logger.info("Native handoff ready; family PIDs: \(self.probe.pids.count), observers: \(observers.count)")
        let target = probe.target
        Task.detached { [weak self] in await self?.pressCompleted(target.press()) }
    }

    private func pressCompleted(_ result: AXError) {
        guard active else { return }
        logger.info("Native press returned \(result.rawValue)")
        // A timeout or missing popup is ambiguous. Never fold merely because
        // the menu was not observed within a guessed startup deadline.
        if result == .actionUnsupported || result == .invalidUIElement || result == .apiDisabled || result == .illegalArgument {
            finish("这个项目暂时无法打开原菜单，可用折叠开关展开后直接点击原图标。")
        } else {
            requestProbe()
        }
    }

    func cancel() {
        active = false
        timer?.invalidate()
        timer = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        for observer in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
    }

    private func finish(_ message: String? = nil) {
        guard active else { return }
        logger.info("Native handoff finished; observed presentation: \(self.state.didPresent), outside interaction: \(self.outsideInteraction)")
        cancel()
        onFinish(message)
    }

    nonisolated private static func makeObservers(probe: MenuPresentationProbe, context: UnsafeMutableRawPointer) -> [AXObserver] {
        let callback: AXObserverCallback = { _, element, notification, context in
            guard let context else { return }
            let session = Unmanaged<MenuBarInteraction>.fromOpaque(context).takeUnretainedValue()
            let name = notification as String
            let identifier = UInt64(CFHash(element))
            MainActor.assumeIsolated {
                guard session.active else { return }
                if name == kAXMenuOpenedNotification { session.state.menuOpened(id: identifier) }
                if name == kAXMenuClosedNotification { session.state.menuClosed(id: identifier) }
                session.requestProbe()
            }
        }
        var result: [AXObserver] = []
        for pid in probe.pids {
            var observer: AXObserver?
            guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { continue }
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 0.1)
            for name in [kAXMenuOpenedNotification, kAXMenuClosedNotification, kAXWindowCreatedNotification, kAXUIElementDestroyedNotification] {
                _ = AXObserverAddNotification(observer, root, name as CFString, context)
            }
            result.append(observer)
        }
        return result
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.observe(event) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.observe(event) }
            return event
        }) { monitors.append(monitor) }
    }

    private func observe(_ event: NSEvent) {
        guard active else { return }
        if event.type == .keyDown {
            guard event.keyCode == 53 else { return }
        } else {
            // Use the worker's latest snapshot, never remote AX queries here.
            guard let snapshot = lastSnapshot else { return }
            let mouse = NSEvent.mouseLocation
            let point = CGPoint(x: mouse.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - mouse.y)
            if snapshot.windows.values.contains(where: { $0.contains(point) }) || snapshot.targetFrame?.contains(point) == true { return }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.outsideInteraction = true
            self?.requestProbe()
        }
    }

    private func requestProbe() {
        guard active, !probePending else { return }
        probePending = true
        let probe = self.probe
        let baseline = baselineWindows
        Task.detached { [weak self] in
            let snapshot = probe.scan(baseline: baseline)
            await self?.apply(snapshot)
        }
    }

    private func apply(_ snapshot: MenuPresentationSnapshot) {
        probePending = false
        guard active else { return }
        lastSnapshot = snapshot
        if !snapshot.windows.isEmpty { didObservePopupWindow = true }
        if snapshot.targetTerminated { finish(); return }
        var visibility = snapshot.visibility
        if visibility == .unknown && snapshot.windowServerAvailable && snapshot.windows.isEmpty &&
            (state.didReceiveClose || didObservePopupWindow) {
            // Disappearance of a positively observed popup is valid evidence,
            // even when unrelated main-window AX contents are inaccessible.
            visibility = .absent
        }
        if state.shouldFinish(visibility: visibility, outsideInteraction: outsideInteraction) { finish() }
    }
}
