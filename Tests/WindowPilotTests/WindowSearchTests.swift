import SwiftUI
import Testing
@testable import WindowPilot

struct WindowSearchTests {
    private func item(_ id: String, app: String = "Editor", title: String) -> WindowItem {
        WindowItem(id: id, pid: -1, appName: app, bundleID: "hidden.bundle.identifier", title: title,
            minimized: false, hidden: false, isAppOnly: false, focused: false, lastUsed: 0)
    }

    @Test func editorStyleSubsequenceAndCaseInvariantRanking() throws {
        let values = [item("watch", title: "watchOptions"), item("space", title: "Workspace Settings")]
        for query in ["ws", "WS", "wS", "Ws"] {
            let results = WindowSearch.results(values, query: query)
            #expect(results.map(\.id) == ["space", "watch"])
            #expect(results.map(\.score) == WindowSearch.results(values, query: "ws").map(\.score))
            #expect(results.last?.titlePositions == [0, 11])
        }
        #expect(WindowSearch.match("sw", in: "watchOptions") == nil)
        #expect(WindowSearch.match("www", in: "watchOptions") == nil)
    }

    @Test func exactPrefixAndConsecutiveMatchesRankAboveScatteredMatches() {
        let values = [item("scattered", title: "q something q"), item("substring", title: "aqq"),
                      item("prefix", title: "QQ Music"), item("exact", title: "QQ")]
        #expect(WindowSearch.results(values, query: "qq").map(\.id) == ["exact", "prefix", "substring", "scattered"])
        // The best alignment must skip an earlier weak occurrence.
        #expect(WindowSearch.match("ab", in: "a___ab")?.positions == [4, 5])
        #expect(WindowSearch.match("gc", in: "GoogleChrome")?.positions == [0, 6])
    }

    @Test func multipleWordsMatchAcrossVisibleFieldsAndHighlightBoth() {
        let values = [item("settings", app: "WindowPilot", title: "Keyboard Settings"), item("other", title: "Document")]
        let results = WindowSearch.results(values, query: "WiP ks")
        #expect(results.map(\.id) == ["settings"])
        #expect(results.first?.appPositions == [0, 1, 6])
        #expect(results.first?.titlePositions == [0, 9])
        #expect(WindowSearch.results(values, query: "hidden.bundle").isEmpty)
    }

    @Test func unicodeFoldingKeepsOriginalGraphemePositions() {
        #expect(WindowSearch.match("设置", in: "系统设置")?.positions == [2, 3])
        #expect(WindowSearch.match("cafe", in: "👩🏽‍💻 Cafe\u{301}")?.positions == [2, 3, 4, 5])
        #expect(WindowSearch.match("SS", in: "ß")?.positions == [0])
        #expect(WindowSearch.match("qq", in: "ＱＱ音乐")?.positions == [0, 1])
    }

    @Test func emptyQueryAndEqualScoresPreserveSessionOrder() {
        let values = [item("second", title: "Same"), item("first", title: "Same")]
        #expect(WindowSearch.results(values, query: " \n ").map(\.item) == values)
        #expect(WindowSearch.results(values, query: "sa").map(\.item) == values)
        #expect(WindowSearch.results([], query: "ws").isEmpty)
        #expect(WindowSearch.match("long query", in: "tiny") == nil)
    }

    @Test func attributedHighlightsPreserveTextAndOnlyStyleMatchedGraphemes() {
        let original = "👩🏽‍💻 Cafe\u{301}"
        for selected in [false, true] {
            let value = SearchHighlight.text(original, positions: [2, 5], selected: selected)
            #expect(String(value.characters) == original)
            var highlighted = ""
            for run in value.runs where run.inlinePresentationIntent == .stronglyEmphasized {
                highlighted += String(value[run.range].characters)
                #expect(run.foregroundColor != nil)
                #expect(run.underlineStyle == .single)
            }
            #expect(highlighted == "Ce\u{301}")
        }
        #expect(SearchHighlight.text("QQ", positions: [], selected: false).runs.allSatisfy { $0.foregroundColor == nil })
    }

    @Test @MainActor func cachedResultsInvalidateWhenQueryOrWindowTitleChanges() {
        let controller = SwitcherController()
        controller.sessionItems = [item("window", title: "watchOptions")]
        controller.query = "ws"
        #expect(controller.searchResults.first?.titlePositions == [0, 11])
        controller.query = "zz"
        #expect(controller.searchResults.isEmpty)
        controller.sessionItems[0] = item("window", title: "ZZ")
        #expect(controller.searchResults.first?.titlePositions == [0, 1])
        controller.query = ""
        #expect(controller.searchResults.first?.titlePositions.isEmpty == true)
    }

    @Test func longLabelsAndImpossibleQueriesRemainCorrect() {
        let title = String(repeating: "a", count: 4_000) + "WorkspaceSettings"
        #expect(WindowSearch.match("ws", in: title)?.positions == [4_000, 4_009])
        #expect(WindowSearch.match(String(repeating: "z", count: 500), in: title) == nil)
    }
}
