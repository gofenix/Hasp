import SwiftUI

struct MenuBarFoldSwitch: View {
    @ObservedObject var state: MenuBarState
    var request: (Bool) -> Void

    var body: some View {
        PanelToggle(title: "折叠状态栏", isOn: Binding(
            get: { state.switchOn }, set: request
        ))
        .disabled(state.layoutPending)
        .accessibilityHint(state.layoutPending ? state.progressDescription : "")
    }
}
