import AppKit
import SwiftUI

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
                                SwitcherRow(result: result, icon: controller.icon(for: result.item),
                                            selected: index == controller.selectedIndex, rowHeight: layout.rowHeight) {
                                    controller.select(result.item)
                                }
                                .id(result.id)
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
        }
        .onChange(of: layout) { _, _ in controller.resizePanel() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            controller.resizePanel()
        }
    }
}
