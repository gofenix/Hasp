## Lock Screen

The fixed panel header places a small Hasp title on the left and a neutral lock
button on the right. The button has a 28pt click target, keyboard focus,
accessibility label and a tooltip showing the existing system shortcut ⌃⌘Q.
The appearance selector below keeps the full content width. Header height is
deducted from the scroll viewport, including inline failure text, so long lists
and smaller displays do not push the button offscreen or exceed the panel limit.

Only an explicit click requests locking. AppModel waits for the existing panel
dismissal callback before invoking the backend. Repeated clicks while dismissal
is pending and duplicate dismissal callbacks are ignored. An unavailable backend
restores the panel with an inline message and the system shortcut.

`NativeScreenLock` resolves `SACLockScreenImmediate` from the system
`login.framework` at runtime, independently implementing the dynamic binding
also used by [Hammerspoon](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/caffeinate/libcaffeinate.m).
This is a private macOS interface: availability on a new OS must be checked,
and Mac App Store eligibility is not claimed. Loading or resolving the symbol
does not lock the Mac. There are no synthesized input events, automation
requests, sleep/screensaver substitutes, extra permissions or settings changes.
The call requests the native lock; it is not a proof that the resulting lock
screen appeared. No native return status is inferred from a void call.

## Validation

`ScreenLockTests` uses an injected backend and never invokes the native lock.
It checks dismissal ordering, repeated clicks/callbacks, unavailable-backend
feedback, retry, and the actual native button's action in a never-shown window.
Light/dark full panels with long lists, 360/540pt bounds, and inline failure text
verify the fixed header and click target. Menu snapshot regression tests retain
coverage of the existing fold behavior and panel height limit.

`Hasp --diagnose-lock-screen` is read-only: it reports whether the symbol resolves
and explicitly emits `lockInvoked: false`. It does not request locking or open a
panel. macOS 27.0.1 resolved the interface in the signed application. Actual
screen locking was deliberately not performed during automated verification.
macOS 26 still needs a device acceptance check; deployment-target compilation
and an available symbol alone do not establish end-to-end compatibility.
