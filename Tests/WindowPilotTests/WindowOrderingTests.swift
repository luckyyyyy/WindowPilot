import Testing
@testable import WindowPilot

private func window(_ id: String, pid: Int32 = 1, app: String = "Editor", title: String = "Document", focused: Bool = false, used: UInt64 = 0) -> WindowItem {
    WindowItem(id: id, pid: pid, appName: app, bundleID: "test.\(app)", title: title,
               minimized: false, hidden: false, isAppOnly: false, focused: focused, lastUsed: used)
}

@Test func putsActualFrontWindowBeforeHistory() {
    let items = [window("old", pid: 2, used: 50), window("current", focused: true, used: 2), window("settings", title: "Settings", used: 3)]
    #expect(WindowOrdering.sorted(items, frontPID: 1).map(\.id) == ["current", "old", "settings"])
}

@Test func retainsSeparateSettingsWindow() {
    let items = [window("document", focused: true, used: 4), window("settings", title: "Settings", used: 3)]
    #expect(WindowOrdering.sorted(items, frontPID: 1).count == 2)
    #expect(WindowOrdering.filter(items, query: "editor settings").map(\.id) == ["settings"])
}

@Test func searchesChineseAndCaseInsensitiveMultiword() {
    let items = [window("a", app: "系统设置", title: "辅助功能"), window("b", app: "Code", title: "WindowPilot.swift")]
    #expect(WindowOrdering.filter(items, query: "设置 辅助").map(\.id) == ["a"])
    #expect(WindowOrdering.filter(items, query: "CODE swift").map(\.id) == ["b"])
    #expect(WindowOrdering.filter(items, query: " \n ") == items)
    #expect(WindowOrdering.filter(items, query: "不存在").isEmpty)
}

@Test func wrapsInBothDirectionsAndHandlesEmptyResults() {
    #expect(WindowOrdering.nextIndex(0, count: 4, delta: -1) == 3)
    #expect(WindowOrdering.nextIndex(3, count: 4, delta: 1) == 0)
    #expect(WindowOrdering.nextIndex(0, count: 0, delta: -1) == 0)
    #expect(WindowOrdering.nextIndex(0, count: 1, delta: 1) == 0)
    #expect(WindowOrdering.nextIndex(0, count: 4, delta: -9) == 3)
}

@Test func tiesAreStableAcrossRefreshes() {
    let items = [window("c"), window("b"), window("a")]
    #expect(WindowOrdering.sorted(items, frontPID: nil).map(\.id) == ["a", "b", "c"])
    #expect(WindowOrdering.sorted(items.reversed(), frontPID: nil).map(\.id) == ["a", "b", "c"])
}
