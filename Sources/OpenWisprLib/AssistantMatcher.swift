import Foundation

struct AssistantMatcher {
    func stripWakePhrase(from transcript: String, wakePhrase: String) -> String? {
        let normalizedTranscript = normalize(transcript)
        let normalizedWakePhrase = normalize(wakePhrase)
        guard !normalizedWakePhrase.isEmpty else { return nil }
        guard normalizedTranscript == normalizedWakePhrase ||
                normalizedTranscript.hasPrefix(normalizedWakePhrase + " ") else {
            return nil
        }

        let originalTokens = transcript.split(whereSeparator: \.isWhitespace)
        let wakeTokens = normalizedWakePhrase.split(separator: " ").count
        let remaining = originalTokens.dropFirst(wakeTokens).joined(separator: " ")
        return remaining.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolve(transcript: String, skills: [SkillDefinition], source: AssistantInvocationSource) -> AssistantResolution {
        let normalizedTranscript = normalize(transcript)
        guard !normalizedTranscript.isEmpty else { return .none }

        var candidates: [(skill: SkillDefinition, trigger: String, input: String)] = []
        for skill in skills where skill.enabled {
            for trigger in skill.normalizedTriggers {
                let normalizedTrigger = normalize(trigger)
                guard !normalizedTrigger.isEmpty else { continue }
                guard normalizedTranscript == normalizedTrigger ||
                        normalizedTranscript.hasPrefix(normalizedTrigger + " ") else {
                    continue
                }
                let consumed = normalizedTrigger.split(separator: " ").count
                let transcriptTokens = transcript.split(whereSeparator: \.isWhitespace)
                let input = transcriptTokens.dropFirst(consumed).joined(separator: " ")
                candidates.append((skill, trigger, input.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }

        guard !candidates.isEmpty else { return .none }

        let sorted = candidates.sorted {
            let lhsLength = normalize($0.trigger).count
            let rhsLength = normalize($1.trigger).count
            if lhsLength != rhsLength {
                return lhsLength > rhsLength
            }
            if $0.skill.id != $1.skill.id {
                return $0.skill.id < $1.skill.id
            }
            return $0.trigger < $1.trigger
        }

        let winner = sorted[0]
        let winnerLength = normalize(winner.trigger).count
        let ambiguous = sorted.dropFirst().contains {
            normalize($0.trigger).count == winnerLength && $0.skill.id != winner.skill.id
        }

        return .matched(
            SkillExecutionRequest(
                skill: winner.skill,
                input: winner.input,
                matchedTrigger: winner.trigger,
                source: source
            ),
            ambiguous: ambiguous
        )
    }

    func normalize(_ text: String) -> String {
        text
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
