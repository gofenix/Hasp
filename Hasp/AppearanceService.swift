import CoreFoundation
import Carbon
import AppKit
import Foundation

enum AppearanceService {
    static let permissionSubtitle = "未能切换，请重试或检查自动化权限"

    @MainActor
    static func ensureTargetRunning() async -> Bool {
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.systemevents" && !$0.isTerminated }) { return true }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app"), configuration: configuration)
            return true
        } catch { return false }
    }

    static func isDark() -> Bool {
        let value = CFPreferencesCopyValue(
            "AppleInterfaceStyle" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? String
        return value == "Dark"
    }

    private static func property(_ code: FourCharCode, container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code), forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return record.coerce(toDescriptorType: typeObjectSpecifier)!
    }

    static func event(dark: Bool? = nil) -> NSAppleEventDescriptor {
        // Codes come from System Events' appearance suite: aprp / thme.
        let preferences = property(0x61707270, container: NSAppleEventDescriptor.null())
        let mode = property(0x74686d65, container: preferences)
        let event = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: dark == nil ? kAEGetData : kAESetData,
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents"),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(mode, forKeyword: keyDirectObject)
        if let dark { event.setParam(NSAppleEventDescriptor(boolean: dark), forKeyword: keyAEData) }
        return event
    }

    static func canReadWithoutPrompt() -> Bool {
        permissionStatus() == noErr
    }

    static func permissionStatus() -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        guard let descriptor = target.aeDesc else { return OSStatus(errAECoercionFail) }
        return AEDeterminePermissionToAutomateTarget(descriptor, kAECoreSuite, kAEGetData, false)
    }

    static func requestPermission() -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        guard let descriptor = target.aeDesc else { return OSStatus(errAECoercionFail) }
        return AEDeterminePermissionToAutomateTarget(descriptor, kAECoreSuite, kAEGetData, true)
    }

    static func readDarkWithoutPrompt() -> Bool? {
        guard canReadWithoutPrompt(),
              let reply = try? event().sendEvent(options: [.waitForReply, .neverInteract], timeout: 3),
              (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0 else { return nil }
        return reply.paramDescriptor(forKeyword: keyDirectObject)?.booleanValue
    }

    /// A successful set reply already confirms command execution. The same
    /// local system preference that drives our theme can confirm its result
    /// without another cross-process event. Preserve the native fallback when
    /// that preference has not converged yet.
    static func confirmDark(_ dark: Bool, localRead: () -> Bool = isDark,
                            nativeRead: () -> Bool? = readDarkWithoutPrompt) -> Bool {
        if localRead() == dark { return true }
        if let confirmed = nativeRead() { return confirmed == dark }
        return true
    }

    static func setDark(_ dark: Bool) -> Bool {
        precondition(!Thread.isMainThread, "Appearance commands must not block the UI")
        let start = DispatchTime.now().uptimeNanoseconds
        let reply = try? event(dark: dark).sendEvent(options: [.waitForReply, .neverInteract], timeout: 5)
        SwitchTrace.duration("appearance-set", since: start)
        guard let reply else { return false }
        guard (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0 else { return false }
        let confirmStart = DispatchTime.now().uptimeNanoseconds
        let confirmed = confirmDark(dark)
        SwitchTrace.duration("appearance-confirm", since: confirmStart)
        return confirmed
    }
}
