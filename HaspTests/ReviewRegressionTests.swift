import AppKit
import CoreLocation
import Foundation

@MainActor enum SettingsWindow { static func show(model: AppModel) {} }

private final class FakeLoginItem: LoginItemManaging {
    var enabled = true
    var fail = false
    var requests: [Bool] = []
    func setEnabled(_ on: Bool) throws {
        requests.append(on)
        if fail { throw NSError(domain: "test", code: 1) }
        enabled = on
    }
}

private final class FakeSolarLocation: SolarLocationFetching {
    var isAuthorized = false
    var requests = 0
    var completion: ((CLLocation?) -> Void)?
    func request(_ completion: @escaping (CLLocation?) -> Void) {
        requests += 1
        self.completion = completion
    }
    func finish(_ location: CLLocation?) {
        let callback = completion
        completion = nil
        callback?(location)
    }
}

@main enum ReviewRegressionTests {
    @MainActor static func wait(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            precondition(Date() < deadline, "Timed out")
            try! await Task.sleep(for: .milliseconds(2))
        }
    }

    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        let suite = "app.hasp.review-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let login = FakeLoginItem()
        let location = FakeSolarLocation()
        let snapshot = [MenuBarIcon(id: "duplicate", name: "First"),
                        MenuBarIcon(id: "duplicate", name: "Duplicate"),
                        MenuBarIcon(id: "other-process", name: "Second instance")]
        let model = AppModel(services: SwitchServices(appearance: { _ in true }, audio: { _ in false },
            device: { _, _ in false }, snapshot: { _ in HardwareSnapshot(outputs: [], devices: [], batteries: [:]) }),
            store: store, menuServices: MenuBarServices(snapshot: { snapshot }, transition: { _, done in done() },
                isTrusted: { true }, requestAccess: { preconditionFailure("No permission prompts") }),
            locationFetcher: location, loginItem: login)

        switch CommandLine.arguments.last {
        case "login":
            model.setLaunchAtLogin(false)
            precondition(!model.launchAtLogin && !store.launchAtLogin && !login.enabled,
                         "Successful disable must update the visible toggle")
            model.setLaunchAtLogin(true)
            precondition(model.launchAtLogin && store.launchAtLogin && login.enabled)
            login.fail = true
            model.setLaunchAtLogin(false)
            precondition(model.launchAtLogin && store.launchAtLogin && login.enabled,
                         "Failed disable must restore both presentation and saved preference")
            login.fail = false
            model.setLaunchAtLogin(false)
            login.fail = true
            model.setLaunchAtLogin(true)
            precondition(!model.launchAtLogin && !store.launchAtLogin && !login.enabled,
                         "Failed enable must not persist a startup request")
            precondition(login.requests == [false, true, false, false, true])
        case "location":
            model.selectSchedule(.solar)
            precondition(location.requests == 1)
            location.finish(nil)
            await wait { store.locationIsEstimate }
            model.selectSchedule(.solar)
            precondition(location.requests == 1, "Do not repeatedly prompt after denial")
            location.isAuthorized = true
            model.selectSchedule(.solar)
            precondition(location.requests == 2, "New authorization must allow replacing the estimate")
            model.selectSchedule(.solar)
            precondition(location.requests == 2, "Coalesce repeated requests while location is pending")
            location.finish(nil)
            await wait {
                model.selectSchedule(.solar)
                return location.requests == 3
            }
            precondition(location.requests == 3, "An authorized transient failure must be retryable")
            location.finish(CLLocation(latitude: 39.9, longitude: 116.4))
            await wait { !store.locationIsEstimate }
            precondition(store.latitude == 39.9 && store.longitude == 116.4)
            model.selectSchedule(.solar)
            precondition(location.requests == 3, "Reuse a real coordinate")
        case "menu":
            let ids = [
                MenuBarCensus.iconID(bundle: "example.tray", pid: 100, index: 0),
                MenuBarCensus.iconID(bundle: "example.tray", pid: 101, index: 0),
                MenuBarCensus.iconID(bundle: "example.tray", pid: 100, index: 1)
            ]
            precondition(Set(ids).count == 3, "Separate processes and slots need separate identities")
            precondition(ids[0] == MenuBarCensus.iconID(bundle: "example.tray", pid: 100, index: 0),
                         "An unchanged item must keep its identity across scans")
            model.refreshMenuBarItems()
            await wait { !model.menuBarScanPending }
            precondition(model.menuBarIcons.map(\.id) == ["duplicate", "other-process"],
                         "A duplicate census entry must not crash or create duplicate UI rows")
            precondition(model.menuBarIcons.first?.name == "First")
        default: preconditionFailure("Choose login, location or menu")
        }
        print("Review regression passed: \(CommandLine.arguments.last!)")
    }
}
