import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController {
    init(controller: SwitcherController) {
        let hosting = NSHostingController(rootView: SettingsRoot(controller: controller))
        let window = NSWindow(contentViewController: hosting)
        window.title = "WindowPilot 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.toolbar = NSToolbar(identifier: "WindowPilotSettingsToolbar")
        window.setContentSize(NSSize(width: 740, height: 660))
        window.minSize = NSSize(width: 700, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case general = "通用", windows = "窗口", shortcuts = "快捷键", about = "关于"
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .windows: "macwindow.on.rectangle"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }
}

extension SettingsPage {
    var tint: Color {
        switch self {
        case .general: .gray
        case .windows: .blue
        case .shortcuts: .purple
        case .about: .blue
        }
    }
    var subtitle: String {
        switch self {
        case .general: "设置窗口切换、启动方式和列表外观。"
        case .windows: "选择哪些窗口出现在切换列表中。"
        case .shortcuts: "用键盘切换、搜索和管理窗口。"
        case .about: "原生 macOS 窗口切换器"
        }
    }
    var keywords: String {
        switch self {
        case .general: "启动 开机 登录 行距 紧凑 外观 深色 浅色 亮色 跟随系统 权限 辅助功能 暂停"
        case .windows: "最小化 隐藏 排除 规则 标题 过滤"
        case .shortcuts: "键盘 cmd command tab 关闭 退出 搜索"
        case .about: "版本 GitHub 开源 隐私 扫描 刷新 更新 下载 安装"
        }
    }
}

struct SettingsRoot: View {
    let controller: SwitcherController
    @State private var selection: SettingsPage? = .general
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SettingsPage.allCases.filter {
                        search.isEmpty || ($0.rawValue + $0.keywords).localizedStandardContains(search)
                    }) { page in
                        Label {
                            Text(page.rawValue)
                        } icon: {
                            Image(systemName: page.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(page.tint.gradient, in: .rect(cornerRadius: 5))
                        }
                        .padding(.vertical, 0)
                        .tag(page)
                    }
                } header: {
                    HStack(spacing: 9) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable().frame(width: 28, height: 28)
                        Text("WindowPilot").font(.headline).foregroundStyle(.primary)
                    }.padding(.vertical, 6)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "搜索设置")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 240)
        } detail: {
            SettingsPane(controller: controller, page: selection ?? .general)
                .navigationTitle((selection ?? .general).rawValue)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 480)
    }
}

struct SettingsPane: View {
    @Bindable var controller: SwitcherController
    let page: SettingsPage
    @State private var selectedRule: UUID?
    @State private var addingRule = false

    var body: some View {
        @Bindable var recorder = controller.shortcutRecorder
        Form {
            if page == .general || page == .about {
                Section {
                    VStack(spacing: 6) {
                        if page == .about {
                            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                        } else {
                            Image(systemName: page.icon)
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(page.tint.gradient, in: .rect(cornerRadius: 11))
                        }
                        Text(page == .about ? "WindowPilot" : page.rawValue).font(.system(size: 20, weight: .bold))
                        Text(page.subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            switch page {
            case .general: general
            case .windows: windows
            case .shortcuts: shortcuts
            case .about: about
            }
            if let error = controller.lastError {
                Section { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .contentMargins(.top, 12, for: .scrollContent)
        .controlSize(.small)
        .font(.system(size: 13))
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $recorder.action, onDismiss: { recorder.stop() }) { action in
            ShortcutRecordingSheet(recorder: recorder, action: action)
        }
        .sheet(isPresented: $addingRule) {
            ExclusionRuleEditor(apps: controller.availableApps) { controller.preferences.rules.append($0) }
        }
    }

    private var general: some View {
        Group {
            Section("启动与外观") {
                Toggle("启用窗口切换", isOn: Binding(get: { controller.preferences.enabled }, set: { controller.setEnabled($0) })).controlSize(.mini)
                Toggle("登录时自动启动", isOn: Binding(get: { controller.loginEnabled }, set: { controller.setLogin($0) })).controlSize(.mini)
                Toggle("更紧凑的行距", isOn: $controller.preferences.compact).controlSize(.mini)
                Picker("外观", selection: Binding(get: { controller.preferences.appearance }, set: { controller.setAppearance($0) })) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                if controller.loginNeedsApproval {
                    LabeledContent("登录项授权") { SettingsButton("打开系统设置…") { SMAppService.openSystemSettingsLoginItems() } }
                }
            }
            Section {
                LabeledContent("辅助功能", value: controller.trusted ? "已授权" : "未授权")
                if !controller.trusted {
                    LabeledContent("授予权限") { SettingsButton("打开系统设置…") { controller.requestAccessibility() } }
                }
                LabeledContent("状态", value: controller.statusText)
                LabeledContent("预览") { SettingsButton("打开窗口切换器") { controller.begin() }.disabled(!controller.keyboardReady) }
            } footer: {
                Text("关闭设置后继续在菜单栏运行。使用 \(controller.preferences.shortcuts.allWindows.display) 切换窗口，按 \(controller.preferences.shortcuts.search.display) 搜索。")
            }
        }
    }

    private var windows: some View {
        Group {
            Section("显示范围") {
                Toggle("显示最小化窗口", isOn: $controller.preferences.includeMinimized).controlSize(.mini)
                Toggle("显示隐藏应用", isOn: $controller.preferences.includeHidden).controlSize(.mini)
                Toggle("显示无窗口的应用", isOn: $controller.preferences.includeWindowless).controlSize(.mini)
            }
            Section {
                Table(controller.preferences.rules, selection: $selectedRule) {
                    TableColumn("应用", value: \.appName)
                    TableColumn("窗口标题") { rule in Text(rule.titlePattern.isEmpty ? "所有窗口" : rule.titlePattern) }
                }
                .frame(height: 120)
                HStack(spacing: 8) {
                    Button {
                        addingRule = true
                    } label: { Image(systemName: "plus").frame(width: 16, height: 16) }
                    .accessibilityLabel("添加排除规则").help("添加排除规则")
                    Button {
                        controller.preferences.rules.removeAll { $0.id == selectedRule }
                        selectedRule = nil
                    } label: { Image(systemName: "minus").frame(width: 16, height: 16) }
                    .disabled(selectedRule == nil).accessibilityLabel("移除排除规则").help("移除排除规则")
                }
            } header: { Text("不显示的窗口") }
        }
    }

    private var shortcuts: some View {
        Group {
            Section {
                shortcutRow(.allWindows)
                LabeledContent("反向切换", value: controller.preferences.shortcuts.allWindows.reversed.display)
                Toggle("启用同应用窗口切换", isOn: $controller.preferences.sameAppShortcut).controlSize(.mini)
                shortcutRow(.appWindows).disabled(!controller.preferences.sameAppShortcut)
            } header: { Text("全局快捷键") } footer: {
                Text("点击右侧按键组合进行录制；额外按住 ⇧ 可反向切换。松开切换组合中的修饰键即可确认。")
            }
            Section {
                shortcutRow(.closeWindow)
                shortcutRow(.quitApplication)
                shortcutRow(.search)
            } header: { Text("切换列表内") } footer: {
                Text("关闭、退出和进入搜索仅在列表内生效。进入搜索后，字母快捷键变为文字输入，不触发窗口操作。")
            }
            Section {
                LabeledContent("确认", value: "松开修饰键或 Return")
                LabeledContent("取消", value: "Esc")
                LabeledContent("选择", value: "↑ / ↓")
                LabeledContent("默认按键") {
                    SettingsButton("恢复默认快捷键") { controller.preferences.shortcuts = ShortcutConfiguration() }
                        .disabled(controller.preferences.shortcuts == ShortcutConfiguration())
                }
            } footer: {
                Text("搜索忽略大小写，支持不连续字母和多个关键词，并高亮命中文字。")
            }
        }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        LabeledContent(action.title) {
            Button {
                controller.cancel()
                controller.shortcutRecorder.begin(action, preferences: controller.preferences)
            } label: {
                Text(controller.preferences.shortcuts[action].display).monospaced().frame(minWidth: 76)
            }
            .accessibilityLabel("修改" + action.title)
            .help("点击录制快捷键")
        }
    }

    private var about: some View {
        Group {
            Section {
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                LabeledContent("开源项目") { Link(destination: URL(string: "https://github.com/luckyyyyy/WindowPilot")!) { Text("GitHub 源码与反馈").frame(minWidth: 96) } }
                LabeledContent("许可证", value: "MIT")
            }
            UpdateSettings()
            Section {
                LabeledContent("可切换项目", value: "\(controller.items.filter { controller.preferences.accepts($0) }.count)")
                LabeledContent("最近一次扫描", value: String(format: "%.0f ms", controller.lastScanDuration * 1000))
                LabeledContent("窗口列表") { SettingsButton("刷新列表") { controller.refresh() } }
            } header: { Text("运行状态") } footer: { Text("窗口标题仅在本机处理，不上传窗口信息或遥测。软件更新连接 GitHub。") }
        }
    }

}

/// Equal-sized native text actions in settings rows; icon tools and sheet actions keep their own sizes.
struct SettingsButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View { Button(action: action) { Text(title).frame(minWidth: 96) } }
}

private struct ExclusionRuleEditor: View {
    let apps: [AppChoice]
    let add: (ExclusionRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedApp: String
    @State private var titlePattern = ""

    init(apps: [AppChoice], add: @escaping (ExclusionRule) -> Void) {
        self.apps = apps
        self.add = add
        _selectedApp = State(initialValue: apps.first?.id ?? "")
    }
    private var selected: AppChoice? { apps.first { $0.id == selectedApp } }
    private var patternValid: Bool {
        titlePattern.isEmpty || (try? NSRegularExpression(pattern: titlePattern)) != nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("不显示的窗口").font(.headline)
            Form {
                Picker("应用", selection: $selectedApp) {
                    ForEach(apps) { app in Text(app.name).tag(app.id) }
                }
                TextField("窗口标题", text: $titlePattern, prompt: Text("留空表示所有窗口"))
                Text("按标题匹配；例如“设置”匹配包含设置的标题，“^设置$”只匹配完整标题。")
                    .font(.caption).foregroundStyle(.secondary)
                if !patternValid { Text("标题匹配表达式无效").foregroundStyle(.red).font(.caption) }
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("取消").frame(minWidth: 52) }.keyboardShortcut(.cancelAction)
                Button {
                    guard let selected else { return }
                    add(ExclusionRule(bundleID: selected.id, appName: selected.name, titlePattern: titlePattern))
                    dismiss()
                } label: { Text("添加").frame(minWidth: 52) }
                .keyboardShortcut(.defaultAction).disabled(selected == nil || !patternValid)
            }
        }.controlSize(.small).font(.system(size: 13)).buttonStyle(.bordered).padding(20).frame(width: 380)
    }
}

private struct ShortcutRecordingSheet: View {
    @Bindable var recorder: ShortcutRecorder
    let action: ShortcutAction
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(action.title).font(.headline)
            Text("请按下新的按键组合").foregroundStyle(.secondary)
            Text(recorder.candidate?.display ?? "等待输入…")
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 46)
            if let error = recorder.error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(action.isGlobal ? "需包含 ⌘、⌥ 或 ⌃；⇧ 留给反向切换。" : "仅在窗口切换列表内生效。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button { recorder.stop() } label: { Text("取消").frame(minWidth: 52) }
                Button { recorder.save() } label: { Text("保存").frame(minWidth: 52) }
                    .disabled(recorder.candidate == nil)
            }
        }
        .padding(20).frame(width: 340).font(.system(size: 13))
        .controlSize(.small).buttonStyle(.bordered)
    }
}
