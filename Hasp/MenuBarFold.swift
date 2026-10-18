import AppKit
import ApplicationServices
import Carbon
import CoreWLAN
import Foundation
import IOKit.ps

struct MenuBarIcon: Identifiable, Equatable {
    var id: String
    var name: String
    var status: String? = nil
    var image: NSImage? = nil
    var symbol: String = "menubar.rectangle"
    var target: MenuBarTarget? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.status == rhs.status
    }
}

final class MenuBarTarget: @unchecked Sendable {
    let pid: pid_t
    let element: AXUIElement
    let application: AXUIElement
    let bundleIdentifier: String

    init(app: NSRunningApplication, element: AXUIElement) {
        pid = app.processIdentifier
        self.element = element
        application = AXUIElementCreateApplication(pid)
        bundleIdentifier = app.bundleIdentifier ?? ""
        AXUIElementSetMessagingTimeout(application, 0.3)
    }

    var canPress: Bool {
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        return (actions as? [String] ?? []).contains(kAXPressAction)
    }

    func press() -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}

enum MenuBarCensus {
    /// Observe the native host's current item tree. Per-app AXExtrasMenuBar
    /// nodes can outlive their rendered items on macOS 27.
    static func nativeItemsHidden(owners: Set<String>, strips: [CGRect]) -> Bool? {
        guard let visible = nativeRenderedOwners(strips: strips) else { return nil }
        return visible.isDisjoint(with: owners)
    }

    static func nativeRenderedOwners(strips: [CGRect]) -> Set<String>? {
        guard isTrusted, !strips.isEmpty,
              let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else { return nil }
        let application = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.1)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &raw) == .success,
              let windows = raw as? [AXUIElement] else { return nil }
        func frame(_ element: AXUIElement) -> CGRect? {
            guard let value = attribute(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var result = CGRect.zero
            return AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgRect, &result) ? result : nil
        }
        var result = Set<String>(), readableBars = 0, budget = 512
        var covered = Set<Int>()
        func visit(_ element: AXUIElement, depth: Int, slot: CGRect?) -> Bool {
            guard depth <= 5, budget > 0 else { return false }
            budget -= 1
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success else { return false }
            if pid != agent.processIdentifier {
                // Inactive-display slots may point to AXApplication roots,
                // which have no frame and expose their *primary* menu tree.
                // The native host container is the rendered slot's geometry.
                guard let bounds = slot ?? frame(element) else { return false }
                if !bounds.isEmpty, strips.contains(where: { $0.intersects(bounds) }),
                   let owner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier { result.insert(owner) }
                return true
            }
            if attribute(element, "AXHidden") as? Bool == true { return true }
            let bounds = frame(element) ?? slot
            if let role = attribute(element, kAXRoleAttribute) as? String,
               [kAXButtonRole, kAXMenuBarItemRole, kAXMenuButtonRole].contains(role) { return true }
            var children: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            if error == .attributeUnsupported || error == .noValue { return true }
            guard error == .success, let elements = children as? [AXUIElement] else { return false }
            for child in elements { if !visit(child, depth: depth + 1, slot: bounds) { return false } }
            return true
        }
        for window in windows {
            guard let bounds = frame(window) else { return nil }
            guard !bounds.isEmpty, bounds.height <= 80, strips.contains(where: { $0.intersects(bounds) }) else { continue }
            for (index, strip) in strips.enumerated() where strip.intersects(bounds) { covered.insert(index) }
            readableBars += 1
            guard visit(window, depth: 0, slot: nil) else { return nil }
        }
        // An empty/locked/incomplete host is not successful hiding. During a
        // real fold Hasp's own excluded entry is always expected to survive.
        guard readableBars > 0, covered.count == strips.count, !result.isEmpty else { return nil }
        return result
    }
    /// AX rectangles use a top-left origin. The controller converts these to
    /// AppKit coordinates using the primary display's top edge.
    static func visibleItemFrames(targets: [MenuBarTarget]) -> [CGRect]? {
        guard isTrusted else { return nil }
        var frames: [CGRect] = []
        for target in targets {
            let item = target.element
            AXUIElementSetMessagingTimeout(item, 0.05)
            if attribute(item, "AXHidden") as? Bool == true { continue }
            guard let p = attribute(item, kAXPositionAttribute),
                  let s = attribute(item, kAXSizeAttribute),
                  CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
            var origin = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &origin),
                  AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
            if size.width > 0, size.height > 0 { frames.append(CGRect(origin: origin, size: size)) }
        }
        return frames
    }
    /// Apps that currently have a menu-bar icon. Control Center hosts the
    /// windows, so names come from each app's own status item.
    static func thirdPartyIcons() -> [MenuBarIcon] {
        var icons: [MenuBarIcon] = []
        let inputName = currentInputName()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier != "com.apple.controlcenter" && $0.bundleIdentifier != "app.hasp.menu" && $0.bundleIdentifier != "com.apple.MenuBarAgent" }
        for app in apps {
            guard let bundle = app.bundleIdentifier else { continue }
            let name = friendlyName(for: app, inputName: inputName).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            for (index, element) in statusItems(app).enumerated() {
                let id = index == 0 ? bundle : "\(bundle).status.\(index)"
                let image = ownerApplicationURL(app).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? app.icon
                icons.append(MenuBarIcon(id: id, name: name, status: statusText(element, name: name), image: image, target: MenuBarTarget(app: app, element: element)))
            }
        }
        return icons.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func ownerApplicationURL(_ app: NSRunningApplication) -> URL? {
        guard var url = app.bundleURL else { return nil }
        var owner = url
        while url.path != "/" {
            if url.pathExtension == "app" { owner = url }
            url.deleteLastPathComponent()
        }
        return owner
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccess() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func statusItems(_ app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return [] }
        let bar = unsafeBitCast(value, to: AXUIElement.self)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return [] }
        return items
    }

    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private static func statusText(_ element: AXUIElement, name: String) -> String? {
        var values: [String] = []
        for key in [kAXValueAttribute, kAXTitleAttribute, kAXHelpAttribute, kAXDescriptionAttribute] {
            guard let value = attribute(element, key) as? String else { continue }
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty && text != name && !values.contains(text) { values.append(text) }
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    static func systemTarget(_ key: String) -> MenuBarTarget? {
        let identifiers: [String: [String]] = [
            "WiFi": ["wifi", "wi-fi", "airport"], "Battery": ["battery"],
            "Sound": ["sound", "volume"], "FocusModes": ["focus", "donotdisturb", "dnd"]
        ]
        let labels: [String: [String]] = [
            "WiFi": ["Wi-Fi", "WiFi"], "Battery": ["电池", "Battery"],
            "Sound": ["声音", "音量", "Sound", "Volume"], "FocusModes": ["专注", "勿扰", "Focus", "Do Not Disturb"]
        ]
        for bundle in ["com.apple.controlcenter", "com.apple.systemuiserver"] {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundle) {
                for item in statusItems(app) {
                    let identifier = (attribute(item, kAXIdentifierAttribute) as? String ?? "").lowercased()
                    let text = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].compactMap { attribute(item, $0) as? String }.joined(separator: " ")
                    if (identifiers[key] ?? []).contains(where: { identifier.contains($0) }) ||
                       (labels[key] ?? []).contains(where: { text.localizedCaseInsensitiveContains($0) }) {
                        return MenuBarTarget(app: app, element: item)
                    }
                }
            }
        }
        return nil
    }

    static func refreshSystemIcon(_ icon: MenuBarIcon) -> MenuBarIcon {
        var result = icon
        result.target = systemTarget(String(icon.id.dropFirst("system.".count)))
        if let target = result.target { result.status = statusText(target.element, name: icon.name) }
        return result
    }

    static func target(for icon: MenuBarIcon) -> MenuBarTarget? {
        if icon.id.hasPrefix("system.") { return systemTarget(String(icon.id.dropFirst("system.".count))) }
        if let target = icon.target, NSRunningApplication(processIdentifier: target.pid)?.isTerminated == false, target.canPress { return target }
        return thirdPartyIcons().first { $0.id == icon.id }?.target
    }

    private static func friendlyName(for app: NSRunningApplication, inputName: String?) -> String {
        let bundle = app.bundleIdentifier ?? ""
        if bundle == "com.apple.TextInputMenuAgent" {
            return inputName ?? "输入法"
        }
        if bundle.contains("lark"),
           let main = NSRunningApplication.runningApplications(withBundleIdentifier: "com.electron.lark").first?.localizedName,
           !main.isEmpty {
            return main
        }
        var name = app.localizedName ?? bundle
        if name.hasSuffix(" Helper") {
            name = String(name.dropLast(" Helper".count))
        }
        return name
    }

    static func currentInputIdentifier() -> String? {
        guard Thread.isMainThread else { return DispatchQueue.main.sync { currentInputIdentifier() } }
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func currentInputName() -> String? {
        // HIToolbox input-source APIs assert their main-queue requirement in
        // a running app. The census itself also runs from detached fold tasks.
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync { currentInputName() }
        }
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
        let name = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        return name.isEmpty ? nil : name
    }
}

enum MenuBarPrefs {
    private static let domain = "com.apple.controlcenter"
    private static let preferences = PreferenceStore(domain: domain)
    private static let backupKey = "hasp.menuBarFoldBackup"

    struct Backup: Codable {
        var restore: [String: Int]
        var bentoVisible: Bool
    }

    private static let queue = DispatchQueue(label: "app.hasp.menubar")
    private static let requestLock = NSLock()
    private static var latestRequest = 0

    /// Enqueue directly from the caller so rapid switch changes stay ordered.
    /// Coalesce superseded requests and perform all preference I/O off the UI.
    static func transition(hidden: Bool, captureSystemIcons: Bool = false, completion: @escaping ([MenuBarIcon]) -> Void) {
        requestLock.lock()
        latestRequest += 1
        let request = latestRequest
        requestLock.unlock()
        queue.async {
            requestLock.lock()
            let current = request == latestRequest
            requestLock.unlock()
            guard current else { return }
            // Native targets and Wi-Fi/audio metadata are refreshed separately;
            // do not put remote AX queries on the switch transition's path.
            let icons = captureSystemIcons ? systemIconPlaceholders() : []
            if hidden { hideOnQueue() } else { showOnQueue() }
            DispatchQueue.main.async { completion(icons) }
        }
    }

    static func restoreIfNeeded() {
        queue.sync {
            guard let backup = load() else { return }
            restore(backup)
            UserDefaults.standard.removeObject(forKey: backupKey)
        }
    }

    static func hide() {
        queue.sync { hideOnQueue() }
    }

    private static func hideOnQueue() {
        guard let backup = try? prepareHideOnQueue() else { return }
        applyHidden(backup)
    }

    static func prepareHide() throws -> Backup {
        try queue.sync { try prepareHideOnQueue() }
    }
    private static func prepareHideOnQueue() throws -> Backup {
        if let backup = load() { return backup }
        let backup = capture()
        UserDefaults.standard.set(try JSONEncoder().encode(backup), forKey: backupKey)
        return backup
    }
    static func commitHide(_ backup: Backup) {
        queue.sync { applyHidden(backup) }
    }

    static func show() {
        queue.sync { showOnQueue() }
    }

    private static func showOnQueue() {
        guard let backup = load() else { return }
        restore(backup)
        UserDefaults.standard.removeObject(forKey: backupKey)
    }

    private static let defaultVisible: Set<String> = ["WiFi", "Battery", "Sound", "FocusModes"]
    private static let candidates = [
        "WiFi", "Battery", "Sound", "FocusModes", "Bluetooth", "AirDrop",
        "ScreenMirroring", "Display", "NowPlaying"
    ]

    private static func capture() -> Backup {
        preferences.refresh()
        var restore: [String: Int] = [:]
        for module in candidates {
            let current = copyInteger(module, host: kCFPreferencesCurrentHost)
            if current == 8 { continue }
            if current == nil && !defaultVisible.contains(module) { continue }
            restore[module] = current ?? 18
        }
        return Backup(restore: restore, bentoVisible: true)
    }

    private static func applyHidden(_ backup: Backup) {
        preferences.apply(Dictionary(uniqueKeysWithValues: backup.restore.keys.map { ($0, 8) }))
        if backup.bentoVisible {
            preferences.apply(["NSStatusItem Visible BentoBox": false], currentHost: false)
        }
    }

    private static func restore(_ backup: Backup) {
        preferences.apply(backup.restore)
        if backup.bentoVisible {
            preferences.apply(["NSStatusItem Visible BentoBox": true], currentHost: false)
        }
    }

    static func shownSystemIcons() -> [MenuBarIcon] {
        // Read after pending hide/show writes; when folded, the backup records
        // which modules were visible before Hasp hid them.
        let icons = queue.sync { systemIconPlaceholders() }
        return icons.map(refreshSystemIcon)
    }

    private static func systemIconPlaceholders() -> [MenuBarIcon] {
        preferences.refresh()
        return systemIconPlaceholders(backup: load()) {
            copyInteger($0, host: kCFPreferencesCurrentHost)
        }
    }

    static func systemIconPlaceholders(backup: Backup?, value: (String) -> Int?) -> [MenuBarIcon] {
        let pairs = [
            ("FocusModes", "专注模式"),
            ("WiFi", "Wi-Fi"),
            ("Battery", "电池"),
            ("Sound", "声音")
        ]
        return pairs.compactMap { key, name in
            if let backup {
                guard backup.restore[key] != nil else { return nil }
            } else if value(key) == 8 { return nil }
            return MenuBarIcon(id: "system.\(key)", name: name)
        }
    }

    static func refreshSystemIcon(_ icon: MenuBarIcon) -> MenuBarIcon {
        var result = MenuBarCensus.refreshSystemIcon(icon)
        switch icon.id {
        case "system.WiFi":
            result.symbol = "wifi"
            if let interface = CWWiFiClient.shared().interface() {
                result.status = interface.powerOn() ? (interface.ssid() ?? "Wi-Fi 已开启") : "Wi-Fi 已关闭"
            }
        case "system.Battery":
            result.symbol = "battery.100percent"
            if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
               let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
                for source in sources {
                    guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                          description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                          let current = description[kIOPSCurrentCapacityKey] as? Int,
                          let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                    let percent = max(0, min(100, current * 100 / maximum))
                    result.status = "\(percent)%" + ((description[kIOPSIsChargingKey] as? Bool == true) ? " · 充电中" : "")
                    break
                }
            }
        case "system.Sound":
            result.symbol = "speaker.wave.2"
            result.status = AudioOutputService.volumeDescription() ?? result.status
        case "system.FocusModes": result.symbol = "moon"
        default: break
        }
        // Keep the native target captured before hiding if Control Center's
        // hidden placeholders no longer expose their identifiers.
        if result.target == nil { result.target = icon.target }
        return result
    }

    private static func load() -> Backup? {
        guard let data = UserDefaults.standard.data(forKey: backupKey) else { return nil }
        return try? JSONDecoder().decode(Backup.self, from: data)
    }

    private static func copyInteger(_ key: String, host: CFString) -> Int? {
        preferences.integer(key, currentHost: CFEqual(host, kCFPreferencesCurrentHost))
    }
}
