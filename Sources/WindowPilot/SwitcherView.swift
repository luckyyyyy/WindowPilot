import AppKit
import SwiftUI

@MainActor
final class SwitcherPanel: NSPanel {
    private var presentationBounds = NSRect(x: 0, y: 0, width: 1440, height: 900)
    init(controller: SwitcherController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: SwitcherView(controller: controller))
        setAccessibilityLabel("WindowPilot 窗口切换器")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(layout: SwitcherLayout) {
        let target = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        presentationBounds = target?.visibleFrame ?? presentationBounds
        setFrame(layout.frame(in: presentationBounds), display: true)
        makeKeyAndOrderFront(nil)
    }

    func resize(layout: SwitcherLayout) {
        // Keep the panel on its current display even if the pointer moves away.
        presentationBounds = screen?.visibleFrame ?? presentationBounds
        let next = layout.frame(in: presentationBounds)
        if frame != next { setFrame(next, display: true) }
    }
}

struct SwitcherView: View {
    @Bindable var controller: SwitcherController

    private var layout: SwitcherLayout { controller.switcherLayout }

    var body: some View {
        GeometryReader { geometry in
            let overflows = layout.contentHeight > geometry.size.height + 0.5
            VStack(spacing: 0) {
                if controller.searching {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text(controller.query.isEmpty ? "输入应用名或窗口标题…" : controller.query)
                            .foregroundStyle(controller.query.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(controller.filteredItems.count)").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12)).padding(.horizontal, 14).frame(height: SwitcherLayout.searchHeight)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(controller.searchResults.enumerated()), id: \.element.id) { index, result in
                                Button { controller.select(result.item) } label: { row(result, selected: index == controller.selectedIndex) }
                                    .buttonStyle(.plain).help(result.item.title).id(result.id)
                            }
                            if controller.filteredItems.isEmpty {
                                Text("没有匹配的窗口").font(.system(size: 13)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).frame(height: SwitcherLayout.emptyHeight)
                            }
                        }.padding(.horizontal, 8)
                    }
                    .scrollDisabled(!overflows)
                    .scrollIndicators(overflows ? .visible : .hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: controller.selectedIndex) { _, _ in
                        if let item = controller.selected { proxy.scrollTo(item.id, anchor: .center) }
                    }
                    .onChange(of: controller.query) { _, _ in
                        if let item = controller.selected { proxy.scrollTo(item.id, anchor: .top) }
                    }
                    .onChange(of: controller.presented) { _, visible in
                        if visible, let item = controller.selected { proxy.scrollTo(item.id, anchor: .center) }
                    }
                    .onAppear { if let item = controller.selected { proxy.scrollTo(item.id, anchor: .center) } }
                }
            }
            .padding(.vertical, SwitcherLayout.verticalPadding)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.93), in: .rect(cornerRadius: 10))
            .background(.regularMaterial, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
        .onChange(of: layout) { _, _ in controller.resizePanel() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            controller.resizePanel()
        }
        .environment(\.colorScheme, .dark)
    }

    private func row(_ result: WindowSearchResult, selected: Bool) -> some View {
        let item = result.item
        return HStack(spacing: 9) {
            Text(item.initial).font(.system(size: 12))
                .foregroundStyle(selected ? .white.opacity(0.65) : .secondary).frame(width: 12)
            Text(SearchHighlight.text(item.appName, positions: result.appPositions, selected: selected)).font(.system(size: 13))
                .lineLimit(1).frame(width: 145, alignment: .trailing)
            Image(nsImage: controller.icon(for: item)).resizable().interpolation(.high).frame(width: 23, height: 23)
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
        .frame(height: layout.rowHeight)
        .background(selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear, in: .rect(cornerRadius: 5))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Build attributes against original graphemes, including emoji and composed accents.
enum SearchHighlight {
    static func text(_ text: String, positions: Set<Int>, selected: Bool) -> AttributedString {
        var value = AttributedString(text)
        var index = value.characters.startIndex
        for offset in 0..<text.count {
            let next = value.characters.index(after: index)
            if positions.contains(offset) {
                value[index..<next].foregroundColor = selected
                    ? Color(red: 0.72, green: 0.94, blue: 1) : .cyan
                value[index..<next].inlinePresentationIntent = .stronglyEmphasized
                value[index..<next].underlineStyle = .single
            }
            index = next
        }
        return value
    }
}
