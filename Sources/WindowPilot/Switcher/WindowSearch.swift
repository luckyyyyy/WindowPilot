import Foundation

/// Character positions refer to the original text, never to its case-folded representation.
struct FuzzyMatch: Equatable {
    let score: Int
    let positions: Set<Int>
}

struct WindowSearchResult: Identifiable {
    let item: WindowItem
    let score: Int
    let appPositions: Set<Int>
    let titlePositions: Set<Int>
    var id: String { item.id }
}

/// Ordered subsequence matching inspired by editor completion: prefer exact names,
/// prefixes, word/camel-case boundaries and consecutive characters. Query case has
/// no effect on either ranking or inclusion. This is an independent implementation.
enum WindowSearch {
    private struct Unit {
        let character: Character
        let original: Int
        let boundary: Bool
    }

    private static let locale = Locale(identifier: "en_US_POSIX")
    private static func units(_ text: String) -> [Unit] {
        let characters = Array(text)
        var result: [Unit] = []
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let boundary = index == 0 || previous.map { !$0.isLetter && !$0.isNumber } == true
                || (character.isUppercase && previous?.isLowercase == true)
                || (character.isUppercase && previous?.isUppercase == true && next?.isLowercase == true)
                || (character.isNumber && previous?.isLetter == true)
            let folded = String(character).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            for (offset, foldedCharacter) in folded.enumerated() {
                result.append(Unit(character: foldedCharacter, original: index, boundary: offset == 0 && boundary))
            }
        }
        return result
    }

    static func match(_ query: String, in text: String) -> FuzzyMatch? {
        match(units(query), in: units(text))
    }

    private static func match(_ pattern: [Unit], in target: [Unit]) -> FuzzyMatch? {
        guard !pattern.isEmpty else { return FuzzyMatch(score: 0, positions: []) }
        guard pattern.count <= target.count else { return nil }
        // Reject impossible subsequences before allocating the dynamic-programming table.
        var cursor = 0
        for unit in target where unit.character == pattern[cursor].character {
            cursor += 1
            if cursor == pattern.count { break }
        }
        guard cursor == pattern.count else { return nil }

        let width = target.count
        let missing = Int.min / 4
        var previous = [Int](repeating: missing, count: width)
        var parents = [[Int]]()
        parents.reserveCapacity(pattern.count)
        for (row, wanted) in pattern.enumerated() {
            var current = [Int](repeating: missing, count: width)
            var parent = [Int](repeating: -1, count: width)
            var bestGapScore = missing
            var bestGapIndex = -1
            for column in 0..<width {
                // Keep the best preceding non-contiguous path in O(1) per cell.
                if row > 0 && column >= 2 && previous[column - 2] != missing {
                    let candidate = previous[column - 2] + (column - 2)
                    if candidate > bestGapScore {
                        bestGapScore = candidate
                        bestGapIndex = column - 2
                    }
                }
                guard wanted.character == target[column].character else { continue }
                let reward = 16 + (target[column].boundary ? 28 : 0)
                if row == 0 {
                    current[column] = reward + (column == 0 ? 6 : 0) - column
                } else {
                    if column > 0 && previous[column - 1] != missing {
                        current[column] = previous[column - 1] + reward + 16
                        parent[column] = column - 1
                    }
                    if bestGapIndex >= 0 {
                        let candidate = bestGapScore - column + 1 + reward - 10
                        if candidate > current[column] {
                            current[column] = candidate
                            parent[column] = bestGapIndex
                        }
                    }
                }
            }
            previous = current
            parents.append(parent)
        }
        var end = 0
        for index in previous.indices where previous[index] > previous[end] { end = index }
        var score = previous[end]
        var positions: Set<Int> = []
        for row in pattern.indices.reversed() {
            positions.insert(target[end].original)
            end = parents[row][end]
        }
        // A whole consecutive match should beat a long, scattered abbreviation.
        // Evaluate these paths separately so their highlight cannot disagree with the bonus.
        for start in 0...(width - pattern.count) where target[start].character == pattern[0].character {
            var candidate = 64 + (start == 0 ? 38 : 0) - start
            var matches = true
            for offset in pattern.indices {
                let unit = target[start + offset]
                if unit.character != pattern[offset].character { matches = false; break }
                candidate += 16 + (unit.boundary ? 28 : 0) + (offset > 0 ? 16 : 0)
            }
            if matches && candidate > score {
                score = candidate
                positions = Set(target[start..<(start + pattern.count)].map(\.original))
            }
        }
        return FuzzyMatch(score: score + (pattern.count == target.count ? 100 : 0), positions: positions)
    }

    static func results(_ items: [WindowItem], query: String) -> [WindowSearchResult] {
        let words = query.split(whereSeparator: \.isWhitespace).map { units(String($0)) }
        let results = items.enumerated().compactMap { order, item -> (Int, WindowSearchResult)? in
            guard !words.isEmpty else {
                return (order, WindowSearchResult(item: item, score: 0, appPositions: [], titlePositions: []))
            }
            let app = units(item.appName)
            let title = units(item.title)
            var score = 0
            var appPositions: Set<Int> = []
            var titlePositions: Set<Int> = []
            for word in words {
                let appMatch = match(word, in: app)
                let titleMatch = match(word, in: title)
                // Only visible labels participate, so every result has an explainable highlight.
                guard appMatch != nil || titleMatch != nil else { return nil }
                score += max(appMatch?.score ?? Int.min, titleMatch?.score ?? Int.min)
                appPositions.formUnion(appMatch?.positions ?? [])
                titlePositions.formUnion(titleMatch?.positions ?? [])
            }
            return (order, WindowSearchResult(item: item, score: score, appPositions: appPositions, titlePositions: titlePositions))
        }
        return results.sorted {
            $0.1.score == $1.1.score ? $0.0 < $1.0 : $0.1.score > $1.1.score
        }.map(\.1)
    }
}
