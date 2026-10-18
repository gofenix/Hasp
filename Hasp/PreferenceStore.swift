import Foundation

/// A batch is scoped to the same user/host domains as defaults -currentHost.
struct PreferenceStore {
    let domain: String

    func refresh(currentHost: Bool = true) {
        CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser,
            currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost)
    }

    func integer(_ key: String, currentHost: Bool = true) -> Int? {
        let host = currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
        return (CFPreferencesCopyValue(key as CFString, domain as CFString, kCFPreferencesCurrentUser, host) as? NSNumber)?.intValue
    }

    func apply(_ values: [String: Any], removing keys: [String] = [], currentHost: Bool = true) {
        let host = currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
        CFPreferencesSetMultiple(values as CFDictionary, keys as CFArray, domain as CFString, kCFPreferencesCurrentUser, host)
        CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, host)
    }
}
