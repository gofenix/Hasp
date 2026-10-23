import AppKit
import SwiftUI

enum PanelLayout {
    static let width: CGFloat = 320
    static let inset: CGFloat = 16
    static let verticalInset: CGFloat = 10
    static let iconSize: CGFloat = 28
    static let gap: CGFloat = 8
    static let rowHeight: CGFloat = 44
    static let deviceRowHeight: CGFloat = 36
    static let footerHeight: CGFloat = 30
    static let accessoryWidth: CGFloat = 22
    static let batteryWidth: CGFloat = 32
    static let contentWidth = width - 2 * inset
    static let textInset = iconSize + gap
    static let footerChrome = 2 * verticalInset + 2 * gap + 1 + footerHeight
    static let secondaryFont = Font.system(size: 11)
}

/// Every row uses the same icon, text and trailing-control columns.
struct PanelRow<Content: View>: View {
    var height: CGFloat = PanelLayout.rowHeight
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: PanelLayout.gap, content: content)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .contentShape(Rectangle())
    }
}

struct PanelSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }
}

struct PanelSeparator: View {
    var body: some View { Divider().padding(.vertical, PanelLayout.gap) }
}

struct PanelToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(.blue)
            .fixedSize()
    }
}

struct PanelMoreMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: PanelLayout.accessoryWidth, height: PanelLayout.iconSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: PanelLayout.accessoryWidth, height: PanelLayout.iconSize)
    }
}

/// One optical size for controls and application artwork throughout the panel.
struct PanelIcon: View {
    let symbol: String
    var image: NSImage? = nil
    var symbolPointSize: CGFloat = 15

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: symbolPointSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
                    .frame(width: PanelLayout.iconSize, height: PanelLayout.iconSize)
            }
        }
        .frame(width: PanelLayout.iconSize, height: PanelLayout.iconSize)
        .accessibilityHidden(true)
    }
}

/// Secondary menus share their row's hover surface without reserving empty slots.
struct PanelHoverRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .padding(.horizontal, 6)
            .background(Color.primary.opacity(hovering ? 0.055 : 0), in: .rect(cornerRadius: 8))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .padding(.horizontal, -6)
    }
}

struct PanelActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionBody(configuration: configuration)
    }

    private struct ActionBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.1 : hovering ? 0.055 : 0) : 0),
                            in: RoundedRectangle(cornerRadius: 8))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Two opposing switches. The same vector is used at menu-bar and app-icon sizes.
enum HaspGlyph {
    static var path: CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: 1, y: 3, width: 14, height: 2), cornerWidth: 1, cornerHeight: 1)
        path.addEllipse(in: CGRect(x: 2, y: 1, width: 6, height: 6))
        path.addRoundedRect(in: CGRect(x: 1, y: 11, width: 14, height: 2), cornerWidth: 1, cornerHeight: 1)
        path.addEllipse(in: CGRect(x: 8, y: 9, width: 6, height: 6))
        return path
    }

    static var menuBarImage: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: 1, y: 1)
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Hasp"
        return image
    }
}
