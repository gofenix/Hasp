import AppKit
import Foundation

enum SwitchDiagnostics {
    /// Explicit opt-in probe, never part of startup or a read-only diagnostic.
    /// The runner must normally quit the ordinary app first; a live instance
    /// makes this probe refuse all writes. Only one known icon is targeted.
    @MainActor static func probeNativeFoldTransport(transport: NativeMenuBarVisibilityStorage.Transport = .container) async -> Data {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "app.hasp.menu")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard others.isEmpty else { return DiagnosticJSON.encode { ["refused": "Quit the regular Hasp instance before this explicit probe."] } }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let strips = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: 40) }
        return await Task.detached { DiagnosticJSON.encode {
            let owner = "com.yetone.magpie"
            let storage = NativeMenuBarVisibilityStorage(transport: transport)
            let transaction = MenuBarVisibilityTransaction(storage: storage)
            var report: [String: Any] = ["scope": "Explicit real hide/restore probe of the Magpie status icon only", "transport": String(describing: transport)]
            do {
                guard try storage.journal().isEmpty else { return ["refused": "Pending recovery exists; no probe was started."] }
                let original = try MenuBarVisibilityRecords(data: storage.read()).states
                var initialVisible: Set<String>?
                for _ in 0..<30 {
                    initialVisible = MenuBarCensus.nativeRenderedOwners(strips: strips)
                    if initialVisible?.contains(owner) == true { break }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                guard original[owner] == true, initialVisible?.contains(owner) == true else {
                    return ["refused": "Magpie must be initially allowed and visible; no probe was started.",
                            "initialAllowed": original[owner] as Any? ?? "missing", "nativeHostReadable": initialVisible != nil,
                            "initialVisible": initialVisible?.contains(owner) ?? false, "recordCount": original.count]
                }
                // Use the normal durable transaction and its failure rollback.
                // There is no synthetic input, app activation or menu action.
                do {
                    try transaction.fold(owners: [owner]) {
                        for _ in 0..<30 {
                            Thread.sleep(forTimeInterval: 0.2)
                            if MenuBarCensus.nativeItemsHidden(owners: [owner], strips: strips) == true { return true }
                        }
                        return false
                    }
                    report["hideConfirmed"] = true
                } catch {
                    report["hideConfirmed"] = false
                    report["failure"] = error.localizedDescription
                }
                try transaction.restore()
                let after = try MenuBarVisibilityRecords(data: storage.read()).states
                report["allOriginalFlagsRestored"] = after == original
                report["pendingRestoreCount"] = try storage.journal().count
                var visibleAgain = false
                for _ in 0..<10 {
                    if MenuBarCensus.nativeRenderedOwners(strips: strips)?.contains(owner) == true { visibleAgain = true; break }
                    Thread.sleep(forTimeInterval: 0.12)
                }
                report["magpieVisibleAgain"] = visibleAgain
            } catch {
                report["failure"] = error.localizedDescription
                // Normal startup can recover the durable journal if access was
                // revoked mid-probe; never discard it to report a false success.
                do { try transaction.restore(); report["recoveryCompleted"] = true }
                catch { report["recoveryFailure"] = error.localizedDescription }
            }
            return report
        } }.value
    }

    @MainActor static func foldCompatibilityReport() async -> Data {
        let policy = MenuBarCompatibility.policy(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        let displays = NSScreen.screens.map {
            MenuBarFoldGeometry.Display(width: $0.frame.width, trailingWidth: $0.auxiliaryTopRightArea?.width)
        }
        let targets = await Task.detached { MenuBarCensus.thirdPartyIcons().compactMap(\.target) }.value
        let frames = await Task.detached { MenuBarCensus.visibleItemFrames(targets: targets) }.value
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let strips = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: 40) }
        let rendered = await Task.detached { MenuBarCensus.nativeRenderedOwners(strips: strips) }.value
        let owners = Set(targets.map(\.bundleIdentifier))
        let nativeData = policy == .native27 ? await Task.detached { DiagnosticJSON.encode { ModernMenuBarFold.inspectConfiguration(itemOwners: owners) } }.value : Data("{}".utf8)
        let native = DiagnosticJSON.decode(nativeData)
        return DiagnosticJSON.encode { [
            "scope": "Read-only geometry and AX check; no status items registered, no fold or window changes",
            "systemVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "compatibilityPolicy": policy.rawValue,
            "usesSegmentedLayout": false,
            "nativeVisibility": native,
            "nativeHostReadable": rendered != nil,
            "nativeHostOwnerCount": rendered?.count ?? 0,
            "nativeHostOwners": (rendered ?? []).sorted(),
            "candidateOwners": Set(targets.map(\.bundleIdentifier)).sorted(),
            "displayWidths": displays.map(\.width),
            "plannedParts": [],
            "accessibilityTrusted": MenuBarCensus.isTrusted,
            "targetCount": targets.count,
            "geometryReadComplete": frames != nil,
            "rectangleCount": frames?.count ?? 0,
            "foldInteractionVerified": false
        ] }
    }

    static func audioInventoryReport() async -> Data {
        let reader = HardwareReader(bluetooth: BluetoothService())
        _ = await reader.read(includeBattery: false)
        await SystemBluetoothCatalog.finishRefresh()
        let snapshot = await reader.read(includeBattery: true)
        return DiagnosticJSON.encode { [
            "scope": "Read-only app-owned audio inventory; no connection or output changes",
            "outputs": AudioOutputInventory.items(snapshot).map { item in
                ["name": item.name, "paired": item.bluetoothAddress != nil,
                 "connected": item.connected, "current": item.isCurrent,
                 "audioEndpointReady": item.audioUID != nil, "subtitle": item.subtitle] as [String: Any]
            },
            "pairedDeviceCount": snapshot.devices.count
        ] }
    }

    static func readOnlyReport() async -> Data {
        let targetReady = await AppearanceService.ensureTargetRunning()
        let reader = HardwareReader(bluetooth: BluetoothService())
        let start = DispatchTime.now().uptimeNanoseconds
        _ = await reader.read(includeBattery: false)
        await SystemBluetoothCatalog.finishRefresh()
        let snapshot = await reader.read(includeBattery: true)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let appearanceStart = DispatchTime.now().uptimeNanoseconds
        let appearance = await Task.detached { AppearanceService.readDarkWithoutPrompt() }.value
        let appearanceMs = Double(DispatchTime.now().uptimeNanoseconds - appearanceStart) / 1_000_000
        let localStart = DispatchTime.now().uptimeNanoseconds
        let localAppearance = AppearanceService.isDark()
        let localMs = Double(DispatchTime.now().uptimeNanoseconds - localStart) / 1_000_000
        let permission = await Task.detached { AppearanceService.permissionStatus() }.value
        var report: [String: Any] = [
            "scope": "Read-only app-owned diagnostic; no theme, audio or device changes",
            "outputCount": snapshot.outputs.count,
            "inputCount": snapshot.devices.filter { $0.kind != .headphone }.count,
            "batteryCount": snapshot.batteries.count,
            "snapshotAndCatalogMs": elapsed,
            "appleEventsReadAllowed": appearance != nil,
            "appleEventsReadMs": appearanceMs,
            "localAppearanceReadMs": localMs,
            "appearanceSourcesAgree": appearance == localAppearance,
            "appleEventsPermissionStatus": permission,
            "systemEventsReady": targetReady
        ]
        if let appearance { report["darkModeReadViaAppleEvents"] = appearance }
        return DiagnosticJSON.encode { report }
    }
}
