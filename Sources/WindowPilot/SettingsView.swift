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
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "WindowPilotSettingsToolbar")
        window.setContentSize(NSSize(width: 780, height: 660))
        window.minSize = NSSize(width: 720, height: 520)
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
        case .general: "启动 开机 登录 行距 紧凑 外观 权限 辅助功能 暂停"
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 25, height: 25)
                                .background(page.tint.gradient, in: .rect(cornerRadius: 6))
                        }
                        .padding(.vertical, 3)
                        .tag(page)
                    }
                } header: {
                    HStack(spacing: 9) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable().frame(width: 32, height: 32)
                        Text("WindowPilot").font(.headline).foregroundStyle(.primary)
                    }.padding(.vertical, 10)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "搜索设置")
            .navigationSplitViewColumnWidth(min: 185, ideal: 205, max: 235)
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
        Form {
            Section {
                VStack(spacing: 9) {
                    if page == .about {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    } else {
                        Image(systemName: page.icon)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(page.tint.gradient, in: .rect(cornerRadius: 15))
                    }
                    Text(page == .about ? "WindowPilot" : page.rawValue).font(.title2.bold())
                    Text(page.subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
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
        .controlSize(.regular)
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $addingRule) {
            ExclusionRuleEditor(apps: controller.availableApps) { controller.preferences.rules.append($0) }
        }
    }

    private var general: some View {
        Group {
            Section("启动与外观") {
                Toggle("启用 ⌘Tab 窗口切换", isOn: Binding(get: { controller.preferences.enabled }, set: { controller.setEnabled($0) }))
                Toggle("登录时自动启动", isOn: Binding(get: { controller.loginEnabled }, set: { controller.setLogin($0) }))
                Toggle("更紧凑的行距", isOn: $controller.preferences.compact)
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
                Text("关闭设置后继续在菜单栏运行。松开 ⌘ 切换，按 X 搜索，Esc 取消。")
            }
        }
    }

    private var windows: some View {
        Group {
            Section("显示范围") {
                Toggle("显示最小化窗口", isOn: $controller.preferences.includeMinimized)
                Toggle("显示隐藏应用", isOn: $controller.preferences.includeHidden)
                Toggle("显示无窗口的应用", isOn: $controller.preferences.includeWindowless)
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
                LabeledContent("下一个窗口", value: "⌘ Tab")
                LabeledContent("上一个窗口", value: "⌘ ⇧ Tab")
                LabeledContent("关闭选中的窗口（非搜索时）", value: "⌘ W")
                LabeledContent("退出选中窗口所属应用（非搜索时）", value: "⌘ Q")
                LabeledContent("确认", value: "松开 ⌘ 或 Return")
                LabeledContent("取消", value: "Esc")
                LabeledContent("选择", value: "↑ / ↓")
                LabeledContent("进入搜索", value: "先按 X，再输入关键词")
                LabeledContent("搜索时 ⌘W / ⌘Q", value: "输入 w / q")
            }
            Section {
                Toggle("⌘ ` 切换当前应用的窗口", isOn: $controller.preferences.sameAppShortcut)
            }
        }
    }

    private var about: some View {
        Group {
            Section {
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                LabeledContent("开源项目") { Link(destination: URL(string: "https://github.com/luckyyyyy/WindowPilot")!) { Text("GitHub 源码与反馈").frame(minWidth: 112) } }
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
    var body: some View { Button(action: action) { Text(title).frame(minWidth: 112) } }
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
        }.controlSize(.regular).buttonStyle(.bordered).padding(20).frame(width: 380)
    }
}
