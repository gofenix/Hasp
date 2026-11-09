import Foundation

/// A scan returns the entire list. Intermediate results stay off the UI.
@MainActor struct MenuBarServices {
    var snapshot: () async -> [MenuBarIcon]
    var transition: (Bool, @escaping () -> Void) -> Void
    /// Fold icons discovered after the last full fold. Reports whether the
    /// attempt succeeded and which owners have no native switch yet.
    var extend: ([MenuBarIcon], @escaping @MainActor @Sendable (Bool, Set<String>) -> Void) -> Void = { _, done in done(true, []) }
    var isTrusted: () -> Bool
    var requestAccess: () -> Void
    var waitsForLayout = false
    var refreshesAfterTransition = true

    static var live: Self {
        Self(snapshot: {
            await Task.detached {
                let live = MenuBarCensus.thirdPartyIcons()
                let apps = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 ? ModernMenuBarFold.shared.completeIcons(live) : live
                let system = MenuBarPrefs.shownSystemIcons()
                return apps + system
            }.value
        }, transition: { hidden, completion in
            if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 {
                // The modern batch owns all three participants, including
                // module restoration and handoffs. No duplicate later write.
                completion()
            } else {
                MenuBarPrefs.transition(hidden: hidden) { _ in completion() }
            }
        }, extend: { icons, completion in
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else {
                completion(true, []); return
            }
            ModernMenuBarFold.shared.extend(icons: icons, completion: completion)
        }, isTrusted: { MenuBarCensus.isTrusted }, requestAccess: {
            MenuBarCensus.promptForAccess()
        }, waitsForLayout: ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27,
           refreshesAfterTransition: ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 27)
    }
}
