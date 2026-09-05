import Foundation

/// Shared measurements for the native panel and its SwiftUI content.
struct SwitcherLayout: Equatable {
    let rowCount: Int
    let compact: Bool
    let searching: Bool

    static let verticalPadding: CGFloat = 8
    static let searchHeight: CGFloat = 28
    static let emptyHeight: CGFloat = 44

    var rowHeight: CGFloat { compact ? 28 : 34 }
    var contentHeight: CGFloat {
        (rowCount > 0 ? CGFloat(rowCount) * rowHeight : Self.emptyHeight)
            + (searching ? Self.searchHeight : 0) + Self.verticalPadding * 2
    }

    func frame(in visibleScreen: CGRect) -> CGRect {
        let width = min(640, visibleScreen.width - 60)
        let height = min(contentHeight, floor(visibleScreen.height * 0.8))
        let y = min(max(visibleScreen.midY - height / 2 + 25, visibleScreen.minY), visibleScreen.maxY - height)
        return CGRect(x: visibleScreen.midX - width / 2, y: y, width: width, height: height)
    }
}
