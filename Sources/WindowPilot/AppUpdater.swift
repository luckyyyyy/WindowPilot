import Combine
import Sparkle
import SwiftUI

/// Sparkle owns scheduling and persisted preferences. Tests never start a network session.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    @Published private(set) var lastCheck: Date?
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
        updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticDownloads)
        updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastCheck)
        controller.startUpdater()
    }

    func check() {
        guard canCheck else { return }
        controller?.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
    func setAutomaticDownloads(_ enabled: Bool) { controller?.updater.automaticallyDownloadsUpdates = enabled }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = AppUpdater.shared
    var inSettings = false
    var body: some View {
        Button { updater.check() } label: { Text("检查更新…").frame(minWidth: inSettings ? 112 : nil) }.disabled(!updater.canCheck)
    }
}

struct UpdateSettings: View {
    @ObservedObject private var updater = AppUpdater.shared
    var body: some View {
        Section {
            Toggle("自动检查更新", isOn: Binding(get: { updater.automaticChecks }, set: { updater.setAutomaticChecks($0) }))
            Toggle("自动下载并安装更新", isOn: Binding(get: { updater.automaticDownloads }, set: { updater.setAutomaticDownloads($0) }))
                .disabled(!updater.automaticChecks)
            LabeledContent("上次检查") {
                if let date = updater.lastCheck {
                    Text(date, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary)
                } else { Text("尚未检查").foregroundStyle(.secondary) }
            }
            LabeledContent("软件更新") { CheckForUpdatesButton(inSettings: true) }
        } header: { Text("更新") } footer: {
            Text("每天从 GitHub 检查新版本。开启自动安装后，更新在后台下载，并在退出时安装。窗口信息始终留在本机。")
        }
    }
}
