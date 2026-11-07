import AppKit
import SwiftUI

struct PanelHeader: View {
    var state: ScreenLockState
    var lock: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Hasp").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                ScreenLockButton(enabled: !state.pending, action: lock)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(hovering && !state.pending ? 0.055 : 0),
                                in: RoundedRectangle(cornerRadius: 8))
                    .onHover { hovering = $0 }
            }
            if let message = state.message {
                Text(message).font(PanelLayout.secondaryFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Native keyboard focus, accessibility and a full 28pt click target, matching
/// the AppKit controls already used by the appearance selector.
private struct ScreenLockButton: NSViewRepresentable {
    var enabled: Bool
    var action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "lock", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))!,
                              target: context.coordinator, action: #selector(Coordinator.press))
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.toolTip = "锁定屏幕 · ⌃⌘Q"
        button.setAccessibilityLabel("锁定屏幕")
        button.setAccessibilityIdentifier("hasp.lock-screen")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = enabled
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: 28, height: 28)
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}
