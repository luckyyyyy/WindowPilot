import AppKit
import SwiftUI

struct SwitcherRow: View {
    let result: WindowSearchResult
    let icon: NSImage
    let selected: Bool
    let rowHeight: CGFloat
    let action: () -> Void
    @State private var hovered = false

    private var item: WindowItem { result.item }
    private var backgroundColor: Color {
        // Keyboard selection remains distinct from neutral pointer feedback.
        if selected { return Color(nsColor: .selectedContentBackgroundColor) }
        return hovered ? Color.primary.opacity(0.10) : .clear
    }

    var body: some View {
        Button(action: action) { content }
            .buttonStyle(.plain)
            .help(item.title)
            .onDisappear { hovered = false }
    }

    private var content: some View {
        HStack(spacing: 9) {
            Text(item.initial).font(.system(size: 12))
                .foregroundStyle(selected ? .white.opacity(0.65) : .secondary).frame(width: 12)
            Text(SearchHighlight.text(item.appName, positions: result.appPositions, selected: selected)).font(.system(size: 13))
                .lineLimit(1).frame(width: 145, alignment: .trailing)
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 23, height: 23)
            Text(SearchHighlight.text(item.title, positions: result.titlePositions, selected: selected)).font(.system(size: 14, weight: .medium))
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            if item.minimized {
                Image(systemName: "minus.rectangle").font(.system(size: 11)).help("已最小化 · 选中后恢复")
                    .accessibilityLabel("已最小化")
            } else if item.hidden {
                Image(systemName: "eye.slash").font(.system(size: 11)).help("应用已隐藏")
            }
        }
        .foregroundStyle(selected ? .white : .primary)
        .padding(.horizontal, 7)
        .frame(height: rowHeight)
        .background(backgroundColor, in: .rect(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
