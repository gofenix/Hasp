## macOS compatibility

Minimum deployment remains macOS 26. No runtime support is claimed for older
systems, unknown future versions or untested hardware just because it compiles.

| System | Fold strategy | Verification limit |
| --- | --- | --- |
| macOS 26.x | Existing separate native entry and wide divider | Legacy fake-item lifecycle/model tests; no macOS 26 machine available |
| macOS 27.x | Native per-app visibility through the explicit Control Center container plus separate system-item preferences | Installed production ON/OFF pipeline passed on this Mac's three displays: 14 third-party owners plus input menu and search hidden and restored; original settings and current input source preserved; no foreground change |
| Other major versions | Fail without folding, keep other controls available | Explicit policy and immediate failure tests |

The previous macOS 27 segmented-spacer approach is no longer used. It required
the user to arrange icons around a boundary and failed on this machine. Passing
geometry fixtures or reading an icon inventory did not make it a working
one-click fold implementation.

## Native visibility backend

macOS 27 stores per-application visibility in Control Center's protected
preferences. Hasp requires access to that configuration before it can use this
backend. The user-facing route is Settings → Permissions → Menu-bar configuration
access → Open Settings. Add and enable the installed `/Applications/Hasp.app`
under Full Disk Access and follow the system's relaunch instruction.

The independent implementation in `MenuBarVisibility.swift` uses the native
`trackedApplications` record format described in this [implementation reference](https://github.com/beaugunderson/tuck/blob/main/Sources/AllowList.swift).
No upstream source or dependency is bundled. This is an undocumented system
format: unknown or malformed records fail closed rather than being guessed.
An application owning multiple icons is managed as one native visibility entry.
The process providing an AX item is not necessarily the native switch's owner.
For example, Lark's helper, Defender's tray and Doubao's browser appear under
their enclosing application's `menuItemLocations`. Resolve these relationships
before writing; do not append an ineffective helper switch. Multiple records
referencing an item are resolved together, including duplicates left by earlier
versions. Unknown relationships or groups shared with Hasp, system items or
unrequested siblings fail before a journal or native setting is changed.

- Hide only the requested third-party owners. Hasp and Apple system applications
  are excluded from this operation; existing system-module handling is separate.
  `SystemMenuVisibility.swift` handles two explicitly identified exceptions on
  macOS 27: TextInputMenuAgent's input-menu icon (which displays the current
  input source, e.g. Doubao) and Campo/Spotlight's search icon. These are absent
  from `trackedApplications`; they use the input menu's `visible` preference
  and Spotlight's per-host `MenuItemHidden` preference respectively. No Apple
  bundle is added to the third-party allowlist. This changes icon visibility,
  not the selected input source or search service/shortcuts. A separate durable
  journal preserves exact original values, including absent keys; startup,
  normal quit and failed folds restore both journals. Repeated folds do not
  rewrite unchanged system settings. Actual native AX verification includes
  these two icons before the switch reports success.
- Change only `trackedApplications`, preserving unrelated preference keys and
  opaque record metadata. Fresh records are read on restoration, so unrelated
  edits made while folded survive.
  The defaults transport imports a plist containing that single key, taking
  its batch refresh path without re-importing a stale whole-domain snapshot.
  A real isolated-domain integration test verifies that other keys survive.
  Both export and import explicitly select `-container group.com.apple.controlcenter`
  and the `group.com.apple.controlcenter` domain. Addressing the file by absolute
  path, even from Hasp through public CFPreferences APIs, was rejected by the
  preferences daemon while returning locally consistent readback. Real native
  hide/restore failed with those transports and succeeded with the explicit
  container. File readability and successful command exit alone are insufficient.
- Write a durable restore journal before hiding anything. Previously user-hidden
  apps remain hidden; expansion restores only entries changed by Hasp.
- Serialize every native request. A slow hide cannot overtake a later show.
  Separate fold/layout generations reject stale callbacks, including handoffs.
- Confirm native flag readback and the fresh MenuBarAgent AX tree on all current displays
  before reporting fold success. Permission failures, unknown AX reads and still
  visible targets fail and restore. Preflight all native/system plans and save
  their recovery records before changing visibility. `MenuBarFoldBatch` submits
  applications, input/search and system modules continuously, then performs
  readback and a single combined AX confirmation. No category waits for the
  preceding category's renderer. A preflight/journal failure submits nothing;
  a failure after submission restores all participants.
- Await restoration before handing a row to its native menu. Retain the complete
  icon cache while native entries are hidden; reconcile newly discovered icons
  without flashing the main fold switch.
- Attempt journal recovery before startup enumeration and before normal quit.
  A failed restore retains its journal and shows recovery UI, rather than an
  apparently successful fold switch. Force termination cannot run cleanup; the
  next launch attempts journal recovery. Revoked access can prevent restoration.
- Run native preference commands and AX verification on one worker, with bounded
  command execution. No keyboard/mouse simulation, app activation, TCC database
  modification, global spacing changes or menu-bar agent restart is involved.
- Retain a complete warm icon inventory across ON/OFF. App launch, activation,
  termination, space change and wake notifications reconcile running-app
  changes; a cold inventory is still populated. No timer polls the census.
  An icon discovered after a fold is folded through an incremental transaction
  that stages only the new owners, so an app whose native switch is not
  recorded yet stays pending instead of restoring the whole bar.
  Avoid making every visibility toggle await another all-app AX enumeration.
  Per-attempt timings distinguish prepare, submission, readback and actual
  combined visual confirmation. The verifier reads immediately, then samples
  within a three-second deadline, without two separate initial sleep barriers.

The permissions page reports actual configuration readability, not an exact
Full Disk Access switch value. No permission request or setting is triggered by
merely inspecting status.

## Verification

`MenuBarVisibilityTests` exercises helper-to-parent and duplicate relationships,
protected/shared groups, unknown owners, schema rejection, unknown-field preservation,
original user choices, append/no-op behavior, durable crash recovery, missing
access, journal failure, write/readback failure, and AX-failure rollback. All
storage is injected; no real native visibility flags are changed by these tests.

`MenuBarSnapshotTests` covers atomic snapshots, stale callbacks, native completion
barriers, failed restoration UI, no automatic AX prompt, and the unshown panel's
height limit. `SwitchOptimizationTests` verifies blocked fake backends do not
stall handlers or publish global panel signals; its timings are not on-screen
frame measurements. Legacy lifecycle tests preserve macOS 26 behavior.

The app-owned `--diagnose-fold-compatibility` mode is read-only: it reports actual
configuration readiness, item-to-switch mapping and pending recovery without registering status items,
changing preferences, or exercising fold controls. It never labels those reads
as an actual fold interaction test. This machine now grants configuration access.
Read-only inspection confirmed the helper mappings. The explicit-container
transport then passed a real single-icon hide/restore, followed by the installed
production controller/model's complete ON/OFF pipeline on all three displays.
All 14 eligible third-party owners plus the input menu and search disappeared
and returned. Original native flags, system-module settings and both system
icon preferences were restored, including Spotlight's originally absent key.
The current input source stayed the same and both recovery journals ended
empty. The foreground app did not change and no panel opened. This is evidence
for this machine, not a substitute for macOS 26 hardware verification.

`SystemMenuVisibilityTests` injects an in-memory preferences backend and an
isolated journal directory. It covers absent-key restoration, crash recovery,
originally hidden icons, failed restore/readback, unchanged refreshes and
protected Apple/Hasp owners without touching real system preferences.

The coordinated-batch optimization was checked against the immediately preceding
installed build on this same three-display, 16-owner setup. Warm production
ON/OFF probe fold completion fell from 3576ms to 984ms (about 72% less time);
the signed candidate measured 896ms. Both new runs confirmed all target icons
hidden and visible again, original flags/module/input/search settings restored,
the selected input source unchanged, no panel opened and empty recovery journals.
These are whole-operation timings including AX confirmation, not frame-rate
measurements. The prior operation also forced a complete inventory refresh;
the optimized operation retains the existing complete inventory, as intended.
Native rendering still took most of the remaining time: the installed run
submitted all three categories within 16ms and spent about 907ms confirming
their appearance. No same-frame rendering guarantee is made for other systems.

The fold switch now reflects requested ON/OFF immediately, including while
`layoutPending` is true. Pending completion is shown separately as folding or
unfolding; failure still rolls back to the recovery result. Temporary native-menu
reveal still shows the switch OFF. Previously the binding forced OFF throughout
the native operation, making the switch itself appear unresponsive even after
the backend speedup. `MenuBarFoldSwitchTests` exercises the real native NSSwitch
inside a never-shown full PanelView with 16 cached rows and an injected blocked
backend. It confirms ON before backend completion, failure rollback, successful
completion, temporary reveal and immediate OFF. The requested state was observed
after a 40ms render pump; this is a hidden-view regression check, not a measured
live-desktop frame-latency guarantee.

`--probe-native-fold-transport` and `--probe-fold-pipeline` are explicit **live**
verification tools, not read-only diagnostics: normally quit Hasp before using
them. The first targets Magpie's status icon; the second exercises the actual
controller/model switch path and restores it. Both refuse to overlap a regular
Hasp instance or a pending recovery. They never send keyboard/mouse events.
