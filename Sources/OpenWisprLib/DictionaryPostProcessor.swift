import Foundation

public struct DictionaryPostProcessor {
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,!?;:")

    public static func buildPrompt(from entries: [DictionaryEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        let unique = Array(Set(entries.map(\.to))).sorted()
        return "Vocabulary: \(unique.joined(separator: ", "))."
    }

    public static func process(_ text: String, dictionary entries: [DictionaryEntry]) -> String {
        guard !entries.isEmpty, !text.isEmpty else { return text }

        let tokens = text.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return text }

        var lookup: [String: [DictionaryEntry]] = [:]
        for entry in entries {
            let firstWord = entry.from.lowercased().components(separatedBy: " ").first ?? ""
            lookup[firstWord, default: []].append(entry)
        }

        for key in lookup.keys {
            lookup[key]?.sort { phraseTokenCount($0.from) > phraseTokenCount($1.from) }
        }

        var result: [String] = []
        var index = 0

        while index < tokens.count {
            let stripped = stripPunctuation(tokens[index])
            let lowered = stripped.word.lowercased()

            guard let candidates = lookup[lowered] else {
                result.append(tokens[index])
                index += 1
                continue
            }

            var matched = false
            for entry in candidates {
                let phraseTokens = entry.from.lowercased().components(separatedBy: " ")
                let phraseLength = phraseTokens.count
                if index + phraseLength > tokens.count { continue }

                var allMatch = true
                for offset in 0..<phraseLength {
                    let token = offset == phraseLength - 1
                        ? stripPunctuation(tokens[index + offset]).word.lowercased()
                        : tokens[index + offset].lowercased()
                    if token != phraseTokens[offset] {
                        allMatch = false
                        break
                    }
                }

                if allMatch {
                    let trailing = stripPunctuation(tokens[index + phraseLength - 1]).punctuation
                    result.append(entry.to + trailing)
                    index += phraseLength
                    matched = true
                    break
                }
            }

            if !matched {
                result.append(tokens[index])
                index += 1
            }
        }

        return result.joined(separator: " ")
    }

    private static func phraseTokenCount(_ phrase: String) -> Int {
        phrase.components(separatedBy: " ").count
    }

    private static func stripPunctuation(_ token: String) -> (word: String, punctuation: String) {
        var word = token
        var punctuation = ""
        while let last = word.unicodeScalars.last, trailingPunctuation.contains(last) {
            punctuation = String(last) + punctuation
            word = String(word.dropLast())
        }
        return (word, punctuation)
    }
}
