import AppKit
import SwiftUI

/// Native macOS segmentation, with equal-width segments filling the panel.
struct AppearanceSelector: NSViewRepresentable {
    @Binding var selection: AppearanceChoice

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: AppearanceChoice.allCases.map(\.rawValue),
            trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.font = .systemFont(ofSize: 12)
        control.setAccessibilityLabel("外观模式")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.selectedSegment = AppearanceChoice.allCases.firstIndex(of: selection) ?? 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? PanelLayout.contentWidth, height: 24)
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<AppearanceChoice>
        init(selection: Binding<AppearanceChoice>) { self.selection = selection }
        @objc func changed(_ sender: NSSegmentedControl) {
            guard AppearanceChoice.allCases.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = AppearanceChoice.allCases[sender.selectedSegment]
        }
    }
}
