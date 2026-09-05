import Testing
@testable import WindowPilot

@Test func excludesOverlaysEvenWhenTheyClaimToBeStandardWindows() {
    #expect(!WindowPolicy.accepts(.init(subrole: "AXStandardWindow", matchingLayers: [25])))
    #expect(!WindowPolicy.accepts(.init(subrole: "AXStandardWindow", matchingLayers: [3])))
    #expect(!WindowPolicy.accepts(.init(subrole: "AXDialog", matchingLayers: [101])))
    #expect(!WindowPolicy.accepts(.init(subrole: "AXFloatingWindow", matchingLayers: [0])))
    // Real-world accessory controls can be AXSystemDialog on layer zero.
    #expect(!WindowPolicy.accepts(.init(subrole: "AXSystemDialog", closable: false, matchingLayers: [0])))
}

@Test func preservesIndependentSettingsAndOffscreenDocuments() {
    #expect(WindowPolicy.accepts(.init(subrole: "AXDialog", matchingLayers: [0])))
    #expect(WindowPolicy.accepts(.init(subrole: "AXDialog", regularApp: false, matchingLayers: [3])))
    #expect(WindowPolicy.accepts(.init(subrole: "AXStandardWindow", matchingLayers: [])))
    #expect(WindowPolicy.accepts(.init(subrole: "AXSystemDialog", modal: true, closable: false, matchingLayers: [8])))
}

@Test func requiresEvidenceForUnknownWindowTypesAndAvoidsDuplicateSheets() {
    #expect(WindowPolicy.accepts(.init(subrole: "AXUnknown", matchingLayers: [0])))
    #expect(!WindowPolicy.accepts(.init(subrole: "AXUnknown", matchingLayers: [])))
    #expect(!WindowPolicy.accepts(.init(role: "AXSheet", subrole: "AXDialog", modal: true)))
    #expect(!WindowPolicy.accepts(.init(subrole: "AXStandardWindow", closable: false, regularApp: false)))
}

@Test func usesWindowTitleBeforeDocumentNameAndAppFallback() {
    #expect(WindowPolicy.title(axTitle: "  项目设置  ", document: "file:///tmp/File.swift", serverTitle: "Other", appName: "Code") == "项目设置")
    #expect(WindowPolicy.title(axTitle: "", document: "file:///tmp/My%20Draft.txt", serverTitle: "Other", appName: "TextEdit") == "My Draft.txt")
    #expect(WindowPolicy.title(axTitle: "", document: "", serverTitle: "Safari 窗口", appName: "Safari") == "Safari 窗口")
    #expect(WindowPolicy.title(axTitle: "", document: "", serverTitle: "", appName: "QQ音乐") == "QQ音乐")
}

@Test func rulesOnlyExcludeTheChosenAppAndTitle() {
    let item = WindowItem(id: "window", pid: 1, appName: "Editor", bundleID: "test.editor", title: "项目设置", minimized: false, hidden: false, isAppOnly: false, focused: false, lastUsed: 0)
    #expect(ExclusionRule(bundleID: "test.editor", appName: "Editor", titlePattern: "设置").matches(item))
    #expect(!ExclusionRule(bundleID: "test.editor", appName: "Editor", titlePattern: "^设置$").matches(item))
    #expect(!ExclusionRule(bundleID: "test.other", appName: "Other", titlePattern: "").matches(item))
}
