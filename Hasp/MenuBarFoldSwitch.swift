import SwiftUI

struct MenuBarFoldSwitch: View {
    var state: MenuBarState
    var request: @MainActor (Bool) -> Void

    var body: some View {
        PanelToggle(title: "折叠状态栏", isOn: Binding(
            get: { state.switchOn }, set: { request($0) }
        ))
        .disabled(state.layoutPending)
        .accessibilityHint(state.layoutPending ? state.progressDescription : "")
    }
}
