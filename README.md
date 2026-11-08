# Hasp

常用控制，收进菜单栏。声音输出、蓝牙设备、自动外观和菜单栏折叠，一个原生 Mac 面板就够。

[下载 Mac 版](https://github.com/gofenix/Hasp/releases/tag/v0.1.0) · [反馈问题](https://github.com/gofenix/Hasp/issues) · [官网源码](website)

## 下载

需要 macOS 26.0 或更高版本，安装包同时包含 Apple Silicon 和 Intel 架构。下载 ZIP，解压后将完整的 `Hasp.app` 拖入“应用程序”。安装包使用 Developer ID 签名，但尚未完成 Apple 公证，macOS Gatekeeper 可能阻止直接打开。请先阅读 Release 说明。

当前实机验证环境为 macOS 26.6.2。macOS 27 折叠后端有自动化覆盖，尚待实机验收。未验收项目详见版本说明。

## Development

Swift 6 / Observation / AppKit / SwiftUI macOS menu-bar app. The minimum
runtime remains macOS 26.0. The development toolchain is Xcode 26.6 with its
bundled Swift 6.3.3 compiler, using Swift 6 language mode. Debug and Release
both use complete concurrency checking. No Xcode or macOS upgrade is required.

Select the toolchain for this repository's shell commands, without changing
other projects' global Xcode selection (adjust the path to the installed app):

```sh
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
xcrun swiftc --version
xcodebuild -version
```

The SDK version does not raise the app's deployment target. Any macOS 27-only
API must remain availability-gated with a macOS 26 implementation. AppKit
retains native menu-bar and popover ownership. Presentation state uses
Observation; AppKit observes settled changes with coalescing and lifecycle
cancellation, while blocking hardware and AX calls stay on their workers.

The fixed top toolbar includes a one-click Lock Screen button. It closes the
panel before requesting the system lock; the appearance selector keeps its full
width. See [lock-screen implementation and validation](docs/lock-screen.md).

## Build

```sh
xcodebuild -project Hasp.xcodeproj -scheme Hasp -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build build
```

The app is created at `build/Build/Products/Debug/Hasp.app`. Debug builds use
automatic signing with `Apple Development`. Add your developer account in
Xcode Settings → Accounts, then select its team in Signing & Capabilities or
run the helper. It uses the project's configured team or the single team cached
by `xcodebuild` for your currently logged-in Xcode account:

```sh
python3 scripts/build-local.py
```

If you have multiple teams, pass the chosen ten-character Team ID explicitly:

```sh
python3 scripts/build-local.py --team YOURTEAMID
```

Quit Hasp, then install the signed build at `/Applications/Hasp.app` as a
complete bundle. Copy into a fresh staging directory, verify its signature,
move the current app to a backup, then rename the staged app into place. A
direct `ditto` overlay can retain old Debug libraries when installing Release,
invalidating the sealed resources. Preserve a verified backup until the new
installation passes validation. Open the installed app when ready:

```sh
open /Applications/Hasp.app --args --open-panel
```

The helper enables Xcode provisioning updates so Xcode can generate or download
the development signing assets for the selected account. Apple ID passwords
and verification codes belong in Xcode's authentication UI, never in this
project. `HASP_DEVELOPMENT_TEAM` may supply the Team ID instead of `--team`.

Changing the signing identity requires granting permissions to the new app
once. Public release packages are signed separately with Developer ID. Notarization
status is recorded per release; a successful local build is not notarization.

## Permissions

Open Hasp → Settings → Permissions, or choose Permissions and Access from
the panel's more menu. The page lists Accessibility, Automation (System Events),
Bluetooth, optional Location, and macOS 27's menu-bar configuration access.
Checks never request consent, open another app, change devices or start location
tracking. A user must click Request Access or Open Settings. Returning to the
visible permissions page refreshes its status; native authorization callbacks also
refresh it. There is no polling timer. Passive checks publish only changed
values, and an in-flight read never disables or drops an authorization click.
Checks coalesce, and pre-request results cannot overwrite post-request consent.
Each action shows feedback; request failures include an Open Settings fallback.
The hardened-runtime build includes the Apple Events entitlement required to
request automation consent.

For Accessibility or Full Disk Access, enable Hasp in System Settings → Privacy
and Security. If it is absent, use + to add `/Applications/Hasp.app`. The page
offers the running application's draggable file, Show in Finder, and Copy Path
actions; they always resolve the current bundle rather than a hard-coded install
path. Opening the page never opens Finder or changes the clipboard. Reinstalling
or registering the app does not grant protected access. Follow macOS's relaunch instruction if
shown. Full Disk Access has no public exact authorization query: the dashboard
checks readability of the menu-bar configuration file, labels success as
“Configuration readable”, and distinguishes missing/invalid files from denied
access. On macOS 27 this access is required for the native per-app folding
backend; the other controls do not need it. The row is omitted on macOS 26.
The backend explicitly selects the Control Center preferences container and
domain for both reads and writes; a file-path export can read a local fallback
after a daemon rejection without changing the native menu bar. It writes only
`trackedApplications`, keeps a durable restore journal,
preserves apps the user had already hidden, and checks native flags and fresh
MenuBarAgent AX items on every display before confirming a fold. Permission denial or
an unknown schema fails without attempting to rearrange icons. See
`docs/compatibility.md` for the current real-device verification limits.

Bluetooth consent is requested only from the explicit permissions action,
never simply by opening the panel. No microphone or screen recording permission
is used. To inspect this installed app's statuses without prompting:

```sh
open -g -j -n -W --stdout permissions.json /Applications/Hasp.app --args --diagnose-permissions
```

`HaspTests/PermissionTests.swift` uses an injected backend to verify checks,
action routing, refresh coalescing, denial/error handling and invisible light/dark
rendering, without asking for permissions or opening Settings.

## Icon artwork

The menu-bar mark and application icon share the vector in `Hasp/IconStyle.swift`.
Panel symbols use one size and weight and adapt to the system appearance.
To regenerate the checked-in app-icon assets after editing the vector:

```sh
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library Hasp/IconStyle.swift scripts/generate-icons.swift \
  -o build/generate-icons
build/generate-icons
```

## Existing tests

Run all standalone regression suites with the selected toolchain:

```sh
python3 scripts/test-local.py
```

The runner explicitly uses Swift 6 language mode and complete concurrency
checking, saves compiler/runtime logs and a JSON report under
`build/swift6-tests`, and supplies each suite's artifact directories. A named
suite can be selected with `--suite ObservationTests`. The read-only census
integration suite reports a skip when its existing permission or input-source
prerequisite is unavailable; a skip is not a passing integration check.
Observation tests cover re-arming, settled reads, coalescing, stopped callbacks,
unchanged snapshots, and isolation between audio and appearance updates.


```sh
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library Hasp/Solar.swift Hasp/DeviceClassifier.swift \
  HaspTests/main.swift -o /tmp/hasp-tests
/tmp/hasp-tests
```

These tests cover appearance schedule boundaries, solar calculations and device
classification. They do not connect or disconnect actual Bluetooth devices.

The menu-bar census integration test exercises both a main-thread scan and
the detached scan used when folding. Run it on a logged-in Mac with an
input-source menu-bar item and Accessibility permission for the test host:

```sh
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library Hasp/MenuBarFold.swift Hasp/PreferenceStore.swift Hasp/AudioOutputService.swift \
  HaspTests/MenuBarCensusBackgroundTests.swift -o /tmp/hasp-census-tests
/tmp/hasp-census-tests
```

Menu lifetime tests need no GUI interaction or Accessibility permission:

```sh
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library Hasp/NativeMenuSessionState.swift \
  HaspTests/NativeMenuSessionTests.swift -o /tmp/hasp-menu-tests
/tmp/hasp-menu-tests
```

Preference batch tests use a temporary preference domain and only read the real
Control Center domain for timing; they do not hide or reveal the user's bar:

```sh
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library Hasp/PreferenceStore.swift \
  HaspTests/PreferenceStoreTests.swift -o /tmp/hasp-preference-tests
/tmp/hasp-preference-tests
```

Bluetooth catalog tests intentionally hold a worker query open and verify that
the main queue stays responsive, duplicate queries coalesce, and cached results
arrive on the main queue. No devices are connected or disconnected:

```sh
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library Hasp/DeviceClassifier.swift Hasp/SystemBluetoothCatalog.swift \
  HaspTests/BackgroundBluetoothCatalogTests.swift -o build/bluetooth-catalog-tests
build/bluetooth-catalog-tests
```

Device presentation tests cover pending disconnect state, rollback on failures,
and audio error feedback. Compile the app sources without its entry point and
include `HaspTests/DevicePresentationTests.swift` as the test entry point.

Review regression tests use fake login-item and location services and an isolated
preferences domain. They verify login-toggle success and failure rollback,
retrying an estimated solar coordinate after authorization, and safe menu census
identities across multiple processes. They do not change login items or request
location permission:

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
sources = [str(p) for p in Path('Hasp').glob('*.swift') if p.name != 'HaspApp.swift']
subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-strict-concurrency=complete', '-Onone', '-parse-as-library', *sources,
                'HaspTests/ReviewRegressionTests.swift', '-o', 'build/review-regression-tests'], check=True)
for case in ['login', 'location', 'menu']:
    subprocess.run(['build/review-regression-tests', case], check=True)
PY
```

Panel appearance tests reproduce an opposite-theme parent window and verify
that the popover material and its SwiftUI content stay in the same appearance.
The test shows no windows and does not change the system theme:

```sh
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library Hasp/PanelAppearance.swift HaspTests/PanelAppearanceTests.swift \
  -o build/panel-appearance-tests
build/panel-appearance-tests
```

Selecting a folded entry now closes Hasp and invokes that status item's native
AXPress action. Menu notifications and visible popup lifetime determine when
to restore folding; there is no interaction deadline. The existing folding
switch controls expanding/collapsing the whole bar. Row context menus expose
opening the owning application as a separate action. Rows show application
icons and public status text, with battery/audio/Wi-Fi status from system APIs.
No unread count is inferred when an app does not publish it. The native tray
image and its notification badge are not claimed to be mirrored by the app icon.

Handoffs wait for the Hasp popover's dismissal before changing bar layout.
Preference changes are queued and batched via CFPreferences, and AX/popup
queries run on workers. Electron helper/main processes are tracked as one app
family. Missing startup evidence and AX timeouts do not mean the menu closed;
there is no 0.75-second auto-fold fallback. Unchanged status snapshots retain
fresh AX handles without publishing a redundant SwiftUI update. Diagnostic
handoff events use the `app.hasp.menu` / `NativeMenu` unified-log category.

## Accessibility diagnostics

The signed app supports `--diagnose-menu-bar`, which prints its bundle ID,
Accessibility trust result and discovered menu-bar apps as JSON, then exits.
It runs the census on a detached task, matching folding's scan, while the main
event loop services input-source queries on the main thread. This also checks
the thread scheduling that previously caused a HIToolbox assertion crash.
To check the app's own identity rather than a terminal helper's permission,
launch the app through Launch Services with `open --stdout`:

```sh
open -g -j -n -W --stdout /tmp/hasp-menu-bar.json /Applications/Hasp.app \
  --args --diagnose-menu-bar
```


## Switch responsiveness

Build the optimized local version with the same Apple Development identity:

```sh
python3 scripts/build-local.py --configuration Release
```

Appearance uses direct Apple Events on a worker with bounded reply waits. System
Events starts in the background if necessary. The switch presents the requested
state immediately; the panel material follows confirmed system appearance.
Operations serialize per resource and coalesce to the newest pending intent.
Stale command replies and pre-command hardware snapshots cannot overwrite it.

Hardware and registry reads use a worker queue. Command completions and system
notification bursts coalesce into a snapshot refresh. Unchanged snapshots publish
no update; each panel section observes its own state. Row positions stay fixed
for an open panel and re-sort on reopening. Folding retains its cached census.

The sound section merges paired Bluetooth headphones with currently available
Core Audio outputs. Paired headphones keep an address-based row identity while
disconnected; Core Audio endpoint addresses are extracted from Bluetooth UIDs,
never guessed from a device's display name. Available outputs and disconnected
paired headphones have separate headings. The most recently used offline
headphone is directly visible, with additional headphones in a manual disclosure.
Unknown paired types remain under a separate "other paired devices" disclosure.
Every sound row reserves 44pt for its name, status, progress and action, so
connection transitions do not change row height.
Clicking an offline headphone connects it, waits up to eight seconds for its
audio endpoint, then selects and verifies the output. The UI distinguishes link
failure from a connected device whose sound output could not be selected.
Disconnect is available in a persistent ellipsis menu and the context menu.
Disconnection jobs and errors are independent per device; a failed disconnect's
primary retry repeats disconnection instead of selecting that device's audio.
Connection work does not block
selection of another output; superseded connection results cannot select audio.
Same-address connection jobs are shared/serialized. Disconnected devices are not
polled for battery levels. No discovery scan or automatic pairing is introduced.

The native entry stays 24pt wide; only its adjacent divider expands. The divider
is created at a positive width before the first fold, then removed from the
bar while unfolded to avoid a blank icon slot. Its saved position is restored
after removal and its final width is set before reinsertion. Keeping a separate, fixed-width
entry avoids Tahoe's multi-display popover positioning issues for wide hosts.
Fold layout requests go to the next main-actor turn and coalesce to the latest
intent; they do not wait for system preference synchronization. The native
popover opens/closes without animation to avoid delaying this small control.

On macOS 27.x, Hasp uses a separate layout policy: bounded segments sized for
the smallest display's menu-bar area, with enough parts for the widest display.
The normal entry keeps its native width and popover anchor. The menu-bar agent
owns ordering on this system; the old per-app preferred-position keys cannot
establish a layout. The first fold exposes a **折叠边界** marker if setup is
needed. Hold Command and move the icons to be hidden to the marker's left,
keeping Hasp, the marker and its intervening segments in their existing order,
then retry the fold. This is a one-time user arrangement, never synthetic input.
Items displaced on this OS may live in the system's native overflow menu.

The switch stays unconfirmed while native layout settles. Hasp reads actual
AX item rectangles on a worker and only confirms a fold when ordinary icons
have left the active display's menu-bar strip. Missing permission, failed AX
reads, incorrect ordering or remaining visible icons roll back the switch and
system-module preferences together. A read failure is never an empty success.
Display changes recalculate and revalidate the layout. No geometry validation
changes the frontmost application, clicks a foreign item or switches audio.

Compatibility references: [Apple NSStatusItem visibility](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible)
and [MenubarHide's macOS 27 notes](https://github.com/junior-rj/menubar-hide#macos-27).
The segment policy and validation in Hasp are implemented independently.

See [the compatibility matrix](docs/compatibility.md) for macOS 26, 27 and unknown
versions, recovery behavior, and the distinction between automated coverage and
actual machine verification. Unknown major versions keep folding unavailable
instead of inheriting an unverified layout. The deployment minimum stays 26.

Panel dismissal keeps the native transient popover and adds passive observers
only while it is shown. An outside mouse down, application switch, Space change
or session sleep closes the panel. Local mouse events pass through unchanged;
clicking the status entry remains the entry's own toggle. Native dropdowns stay
usable outside the panel's rectangle; Escape first belongs to a tracked menu
and otherwise dismisses the panel. Closing removes all observers, and callbacks
from a previous presentation cannot close a newly reopened panel. These hooks
never activate an application, move the pointer or synthesize global input.
`HaspTests/PanelDismissTests.swift` validates routing and lifecycle with injected
events; it does not interact with the user's desktop.

The menu-bar census warms a complete app-and-system snapshot before folding.
Each refresh keeps the previous full list until its replacement is ready; no
system-only intermediate list is published. While folded, system visibility
comes from Hasp's restore backup. One overall scroll viewport caps the expanded
panel to the active display's available height. There are no separate sound and
status-list scrollers. Appearance uses an explicit light/dark/automatic selector;
the settings footer opens independently of the selected schedule.
The row tree also stays mounted across fold changes. The unfolded viewport has
zero height, opacity and hit testing; its rows are hidden from accessibility.
Reopening reuses the existing controls and context menus instead of constructing
the entire list again.
Warm refreshes do not publish a loading state, fresh snapshots skip duplicate
scans and the periodic census only runs while the folded list is displayed.

Run the regression suite without changing real system appearance, audio routing
or device connections. It uses an isolated preferences domain and holds fake
backends open while exercising actual model handlers:

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
sources = [str(p) for p in Path('Hasp').glob('*.swift') if p.name != 'HaspApp.swift']
subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-strict-concurrency=complete', '-Onone', '-parse-as-library', *sources,
                'HaspTests/SwitchOptimizationTests.swift', '-o', 'build/switch-tests'], check=True)
subprocess.run(['build/switch-tests'], check=True)
PY
```

The suite covers coalescing, stale replies and snapshots, failure rollback,
state isolation and stable rows. It records handler timings beside its binary;
these are not click-to-present frame timings.

`HaspTests/MenuBarSnapshotTests.swift` uses the same source compilation pattern
(replace the test filename above) to exercise delayed census results, warm
cache, rapid fold transitions and stale-result rejection. It also measures the
real SwiftUI panel's loading/short/full-list sizes without displaying a window.

`HaspTests/MenuBarFoldLayoutTests.swift` checks 100 fold cycles: only the divider
changes width, the unfolded divider is invisible, and duplicate states do not
relayout. The fake item models AppKit deleting its preferred position on removal,
so each reinsertion must recover the saved position before becoming visible.
Live display placement requires the app's own layout report; these
simulations do not verify actual menu-bar clicks.
The suite also submits 100 rapid intents and verifies one deferred layout.

`HaspTests/HeadphoneRoutingTests.swift` uses the full source compilation pattern
above with an injected Bluetooth/audio backend. It checks offline paired rows,
stable identity through reconnection, same-name device separation, delayed/missing
audio endpoints, connection/routing/disconnection failures and retries, and a
late connection after the user selects another output. It never connects a real
device or changes system audio. `--diagnose-audio-inventory` is an app-owned,
read-only report of the merged sound list; it does not open the panel, connect
devices, or change audio output.

`HaspTests/ApprovedDesignTests.swift` verifies explicit appearance selection,
failure rollback, settings without mode changes, fixed row heights, and overall
viewport bounds on a small screen. It renders the production components in both
appearances and both disclosure states, without showing a desktop window.
Headphone routing tests also cover independent concurrent disconnections,
connection/selection of A while disconnecting B, and retrying a failed disconnect.

Start normally with `--diagnose-menu-layout` to also log the native entry and
divider frames and saved positions at startup and after user fold actions. This
mode does not open the panel or initiate a fold.

For local latency diagnosis, create an empty file and start normally with
`--latency-log <file>`. Generic operation labels and milliseconds are appended
on a worker; no device addresses, application names or user content are logged.
`panel-show` and `fold-layout` measure native API duration, not the first visible
frame or final Window Server layout. This option performs no test clicks.
`panel-prepare` measures deferred preparation of closed contents; existing
Bluetooth permission and notifications are initialized before first opening.
`appearance-set` and `appearance-confirm` split the native set and confirmation
costs. A matching local system appearance preference avoids a redundant native
query; otherwise the original confirmation path is used.

The app-owned `--diagnose-switch-performance` mode checks hardware snapshots and
existing System Events permission without requesting new permission or changing
settings. It waits for the catalog worker before exiting. Start it through
Launch Services in the background, using a fresh output file:

```sh
open -g -j -n -W --stdout "$PWD/build/switch-diagnostic.json" /Applications/Hasp.app \
  --args --diagnose-switch-performance
```

For actual user-click profiling, attach the SwiftUI, Animation Hitches and Time
Profiler instruments to the existing Hasp process. Signposts under
`app.hasp.menu` / `SwitchPerformance` mark `SwitchIntent`, `SwitchBackend` and
`SwitchStateApplied`. They contain operation categories, not device names or
addresses. Measure visible feedback separately from system completion; handler
benchmarks do not establish the 50ms first-frame target.

## Source availability

The repository is public. A project-wide open-source license has not yet been
selected; public visibility alone does not grant a reuse license. Website
third-party licenses are recorded in [website/THIRD_PARTY_NOTICES.md](website/THIRD_PARTY_NOTICES.md).
