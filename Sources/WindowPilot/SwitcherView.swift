import AppKit
import SwiftUI

@MainActor
final class SwitcherPanel: NSPanel {
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

    func show(rowCount: Int, compact: Bool) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(640.0, frame.width - 60)
        let height = min(CGFloat(min(max(rowCount, 1), 12)) * (compact ? 28 : 34) + 16, frame.height - 80)
        setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2 + 25, width: width, height: height), display: true)
        makeKeyAndOrderFront(nil)
    }
}

struct SwitcherView: View {
    @Bindable var controller: SwitcherController

    var body: some View {
        VStack(spacing: 0) {
            if !controller.query.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text(controller.query)
                    Spacer()
                    Text("\(controller.filteredItems.count)").foregroundStyle(.secondary)
                }
                .font(.system(size: 12)).padding(.horizontal, 14).frame(height: 28)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(controller.filteredItems.enumerated()), id: \.element.id) { index, item in
                            Button { controller.select(item) } label: { row(item, selected: index == controller.selectedIndex) }
                                .buttonStyle(.plain).help(item.title).id(item.id)
                        }
                        if controller.filteredItems.isEmpty {
                            Text("没有匹配的窗口").font(.system(size: 13)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(16)
                        }
                    }.padding(.horizontal, 8)
                }
                .scrollIndicators(.hidden)
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
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.93), in: .rect(cornerRadius: 10))
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private func row(_ item: WindowItem, selected: Bool) -> some View {
        HStack(spacing: 9) {
            Text(item.initial).font(.system(size: 12))
                .foregroundStyle(selected ? .white.opacity(0.65) : .secondary).frame(width: 12)
            Text(item.appName).font(.system(size: 13))
                .lineLimit(1).frame(width: 145, alignment: .trailing)
            Image(nsImage: controller.icon(for: item)).resizable().interpolation(.high).frame(width: 23, height: 23)
            Text(item.title).font(.system(size: 14, weight: .medium))
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
        .frame(height: controller.preferences.compact ? 28 : 34)
        .background(selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear, in: .rect(cornerRadius: 5))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
