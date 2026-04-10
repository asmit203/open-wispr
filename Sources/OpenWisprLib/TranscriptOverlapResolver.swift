import Foundation

struct TranscriptOverlapResolver {
    private struct Token {
        let raw: String
        let normalized: String
    }

    static func trimCurrentText(previousText: String?, currentText: String, maxWindowTokens: Int = 32) -> String {
        let currentTokens = tokenize(currentText)
        guard !currentTokens.isEmpty else { return "" }

        let previousTokens = tokenize(previousText ?? "")
        guard !previousTokens.isEmpty else {
            return join(tokens: currentTokens)
        }

        let maxOverlap = min(maxWindowTokens, previousTokens.count, currentTokens.count)
        guard maxOverlap > 0 else {
            return join(tokens: currentTokens)
        }

        for overlapCount in stride(from: maxOverlap, through: 1, by: -1) {
            let previousSlice = previousTokens.suffix(overlapCount).map(\.normalized)
            let currentSlice = currentTokens.prefix(overlapCount).map(\.normalized)
            if previousSlice == currentSlice {
                let trimmed = Array(currentTokens.dropFirst(overlapCount))
                return join(tokens: trimmed)
            }
        }

        return join(tokens: currentTokens)
    }

    private static func tokenize(_ text: String) -> [Token] {
        text.split(whereSeparator: \.isWhitespace).compactMap { component in
            let raw = String(component)
            let normalized = normalize(raw)
            guard !normalized.isEmpty else { return nil }
            return Token(raw: raw, normalized: normalized)
        }
    }

    private static func normalize(_ token: String) -> String {
        token
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
    }

    private static func join(tokens: [Token]) -> String {
        tokens.map(\.raw).joined(separator: " ")
    }
}
