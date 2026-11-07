import Observation
import Darwin
import Foundation

enum ScreenLockError: LocalizedError {
    case unavailable
    var errorDescription: String? { "当前系统的锁屏接口不可用，请使用 ⌃⌘Q 锁屏。" }
}

/// Runtime-bound because login.framework is private and can change between
/// macOS versions. No key events, automation, sleep or screensaver fallback.
/// The resolved function is only invoked by the explicit user action.
@MainActor final class NativeScreenLock {
    static let shared = NativeScreenLock()
    private let handle: UnsafeMutableRawPointer?
    private let function: (@convention(c) () -> Void)?

    init() {
        let library = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/A/login", RTLD_LAZY | RTLD_LOCAL)
        handle = library
        function = library.flatMap { dlsym($0, "SACLockScreenImmediate") }
            .map { unsafeBitCast($0, to: (@convention(c) () -> Void).self) }
    }
    isolated deinit { if let handle { dlclose(handle) } }
    var available: Bool { function != nil }
    func lock() throws {
        guard let function else { throw ScreenLockError.unavailable }
        function()
    }
}

@MainActor @Observable final class ScreenLockState {
    var pending = false
    var message: String?
}
