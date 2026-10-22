import Foundation

/// Raycast's menu search (`menu.namespace`: `pe` scores, `fe(…, "high")` decides a match,
/// `Wi` ranks): a subsequence match where each matched character scores 4 at the start of
/// the text, 3 at a word start, 2 elsewhere and 1 for a separator standing in for another,
/// minus 1 for every gap. Ported as is, including how skipped rows reuse old columns.
enum MenuSearch {
    enum Score: Equatable {
        case unmatched
        case exact
        case scored(Int, skipped: Int)

        /// `me`: the value `Wi` sorts by.
        var rank: Int {
            switch self {
            case .unmatched: -sentinel
            case .exact: sentinel
            case let .scored(score, _): score
            }
        }

        /// `fe(score, queryLength, "high")`.
        func isMatch(queryLength: Int) -> Bool {
            switch self {
            case .unmatched: false
            case .exact: true
            case let .scored(score, skipped): score > 2 * (queryLength - skipped)
            }
        }
    }

    private static let sentinel = 9_007_199_254_740_991
    /// `U`: the characters that separate words.
    private static func isLimiter(_ c: UInt16) -> Bool {
        c == 9 || c == 10 || c == 32 || c == 45 || c == 46 || c == 47 || c == 40 || c == 41 || c == 91 || c == 93
    }

    /// `de` + `pe`: scores `text` against an already lowercased `query`.
    static func score(_ text: String, query: String) -> Score {
        let original = Array(text.utf16)
        let r = Array(text.lowercased().utf16)
        let a = Array(query.utf16)
        if r == a { return .exact }
        // `ue`: camelCase boundaries in the original text.
        var boundaries = [Bool](repeating: false, count: r.count)
        if original.count == r.count {
            for n in 1..<max(1, original.count) {
                let previous = original[n - 1], current = original[n]
                if (97...122).contains(previous) || (48...57).contains(previous), (65...90).contains(current) { boundaries[n] = true }
            }
        }
        let s = r.count, c = a.count
        let u = c - a.filter(isLimiter).count
        if u > s { return .unmatched }
        if u > 2 {
            var e = 0
            for t in 0..<c {
                let n = a[t]
                if isLimiter(n) {
                    if e < s, isLimiter(r[e]) { e += 1 }
                    continue
                }
                var found = false
                while e < s {
                    if r[e] == n { e += 1; found = true; break }
                    e += 1
                }
                if !found { return .unmatched }
            }
        }

        // `he`: a word start follows a separator or a camelCase boundary.
        func positional(_ index: Int) -> Int {
            (boundaries[index] || isLimiter(r[index - 1])) && !isLimiter(r[index]) ? 3 : 2
        }

        // `ce`: two alternating rows of `s` columns.
        var storage = [Int](repeating: -sentinel, count: 2 * s)
        var rows = -1
        func rowIndex(_ row: Int) -> Int? { row < 0 ? nil : (row % 2) * s }

        var d = -1, skipped = 0, matched = 0
        for e in 0..<c {
            rows += 1
            let t = a[e]
            let n = isLimiter(t)
            let remaining = u - 1 - matched
            var m = -1
            // Matched separators count too, so this can pass the end; JavaScript's
            // `charCodeAt` reads NaN there and never matches.
            let upper = min(s, s - remaining)
            if d + 1 < upper {
                for column in (d + 1)..<upper {
                    let character = r[column]
                    let same = character == t
                    let limiter = !same && n && isLimiter(character)
                    guard same || limiter else { continue }
                    let row = rowIndex(rows)!
                    if d < 0 {
                        storage[row + column] = limiter ? 1 : column == 0 ? 4 : positional(column)
                    } else {
                        let value = limiter ? 1 : positional(column)
                        var best = -sentinel
                        if let previous = rowIndex(rows - 1) {
                            for p in d..<column {
                                let score = storage[previous + p]
                                if score <= -sentinel { continue }
                                best = max(best, score + value - (p == column - 1 ? 0 : 1))
                            }
                        }
                        storage[row + column] = best
                    }
                    if m < 0 { m = column }
                }
            }
            if m >= 0 {
                d = m
                matched += 1
            } else if n {
                skipped += 1
                if e < c - 1 { rows -= 1 }
            } else {
                return .unmatched
            }
        }
        guard let row = rowIndex(rows), s > 0 else { return .scored(-sentinel, skipped: skipped) }
        return .scored(storage[row..<(row + s)].max() ?? -sentinel, skipped: skipped)
    }

    /// `Hi` + `Ui` + `Wi`: the items whose title or a keyword matches, ranked by title score
    /// (exact titles first once the query is longer than three characters), stable otherwise.
    static func rank(_ items: [MenuItem], query raw: String) -> [MenuItem] {
        let query = String(raw.drop { $0.isWhitespace }).lowercased()
        guard !query.isEmpty else { return items }
        let length = query.utf16.count
        let scored = items.enumerated().compactMap { index, item -> (Int, MenuItem, Score)? in
            let title = score(item.title, query: query)
            let keywords = item.keywords.filter { $0.lowercased() != item.title.lowercased() }
            guard title.isMatch(queryLength: length) || keywords.contains(where: { score($0, query: query).isMatch(queryLength: length) }) else { return nil }
            return (index, item, title)
        }
        return scored.sorted { lhs, rhs in
            if length > 3, (lhs.2 == .exact) != (rhs.2 == .exact) { return lhs.2 == .exact }
            if lhs.2.rank != rhs.2.rank { return lhs.2.rank > rhs.2.rank }
            return lhs.0 < rhs.0
        }.map(\.1)
    }
}
