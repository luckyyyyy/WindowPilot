import SwiftUI

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
