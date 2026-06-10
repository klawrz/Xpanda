import Foundation
import AppKit

class LLMRephraseService {
    static let shared = LLMRephraseService()

    private static let defaultSystemPrompt = "Rephrase the following text into a fresh version. Rules: (1) Preserve the grammatical person, voice, and tone of the original exactly — do not switch from second person to first person, or from active to passive, or change the formality level. (2) Preserve every factual claim and commitment — do not drop or weaken anything. (3) Match the word count closely — stay within 3 words of the original length. (4) Vary the wording and sentence structure so it does not sound like the previous versions. (5) Use only commas, periods, and apostrophes — no dashes of any kind. Return only the rephrased text with no explanation."

    private static let historyKey = "llm-rephrase-history"
    private static let maxHistoryPerXP = 3

    private init() {}

    // MARK: - Settings

    var customSystemPrompt: String? {
        get { UserDefaults.standard.string(forKey: "llm-custom-prompt") }
        set { UserDefaults.standard.set(newValue, forKey: "llm-custom-prompt") }
    }

    // MARK: - Per-XP Rephrase History

    private func recentRephrases(for xpId: UUID) -> [String] {
        let all = UserDefaults.standard.dictionary(forKey: Self.historyKey) as? [String: [String]] ?? [:]
        return all[xpId.uuidString] ?? []
    }

    private func saveRephrase(_ text: String, for xpId: UUID) {
        var all = UserDefaults.standard.dictionary(forKey: Self.historyKey) as? [String: [String]] ?? [:]
        var history = all[xpId.uuidString] ?? []
        history.append(text)
        if history.count > Self.maxHistoryPerXP {
            history = Array(history.suffix(Self.maxHistoryPerXP))
        }
        all[xpId.uuidString] = history
        UserDefaults.standard.set(all, forKey: Self.historyKey)
    }

    /// True when the user is signed in and has AI access.
    /// TODO: also check RevenueCat ai_access entitlement once RevenueCat is integrated.
    var isConfigured: Bool {
        #if DEBUG
        return true
        #else
        return AuthManager.cachedHasAIAccess
        #endif
    }

    // MARK: - System Prompt

    private func effectiveSystemPrompt(for xpId: UUID?) -> String {
        var prompt = Self.defaultSystemPrompt
        if let xpId {
            let recent = recentRephrases(for: xpId)
            if !recent.isEmpty {
                let listed = recent.map { "- \($0)" }.joined(separator: "\n")
                prompt += "\n\nAvoid these recent versions you have already produced for this phrase:\n\(listed)"
            }
        }
        if let custom = customSystemPrompt, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n\nAdditional instructions: \(custom)"
        }
        return prompt
    }

    // MARK: - Plain Text Rephrase

    func rephrasePlainText(_ text: String, xpId: UUID? = nil) async throws -> String {
        let provider = BaesideProvider()
        let result = try await provider.rephrase(text: text, systemPrompt: effectiveSystemPrompt(for: xpId))
        if let xpId { saveRephrase(result, for: xpId) }
        return result
    }

    // MARK: - Rich Text Rephrase (Format-Preserving)

    func rephraseAttributedString(_ attrStr: NSAttributedString, xpId: UUID? = nil) async throws -> NSAttributedString {
        // Extract segments: text runs and attachments
        struct Segment {
            let text: String
            let attributes: [NSAttributedString.Key: Any]
            let range: NSRange
            let isAttachment: Bool
        }

        var segments: [Segment] = []
        attrStr.enumerateAttributes(in: NSRange(location: 0, length: attrStr.length), options: []) { attrs, range, _ in
            let isAttachment = attrs[.attachment] != nil
            let text = (attrStr.string as NSString).substring(with: range)
            segments.append(Segment(text: text, attributes: attrs, range: range, isAttachment: isAttachment))
        }

        // Build plain text from non-attachment segments
        let textSegments = segments.filter { !$0.isAttachment }
        let plainText = textSegments.map { $0.text }.joined()

        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return attrStr
        }

        // Send to LLM
        let rephrasedText = try await rephrasePlainText(plainText, xpId: xpId)

        // Re-apply formatting using proportional mapping
        let totalOriginalLength = textSegments.reduce(0) { $0 + $1.text.count }
        let result = NSMutableAttributedString()
        var rephrasedIndex = rephrasedText.startIndex

        for segment in segments {
            if segment.isAttachment {
                // Preserve attachments at their original positions
                let attachmentStr = attrStr.attributedSubstring(from: segment.range)
                result.append(attachmentStr)
            } else {
                // Find which text segment index this is among text-only segments
                let textSegmentIndex = textSegments.firstIndex(where: { $0.range == segment.range })!
                let isLastTextSegment = textSegmentIndex == textSegments.count - 1

                if isLastTextSegment {
                    // Last text segment gets whatever remains
                    let remaining = String(rephrasedText[rephrasedIndex...])
                    var cleanAttrs = segment.attributes
                    cleanAttrs.removeValue(forKey: .attachment)
                    result.append(NSAttributedString(string: remaining, attributes: cleanAttrs))
                    rephrasedIndex = rephrasedText.endIndex
                } else {
                    // Proportional chunk — snap to word boundary so we never split a
                    // word across two attribute runs (e.g. a hyperlink). Walk backward
                    // from rawEnd to the start of the current word; that word then belongs
                    // to the NEXT segment (the hyperlink), keeping plain text clean.
                    let proportion = totalOriginalLength > 0 ? Double(segment.text.count) / Double(totalOriginalLength) : 0
                    let rawLength = max(1, Int(round(proportion * Double(rephrasedText.count))))
                    let rawEnd = rephrasedText.index(rephrasedIndex, offsetBy: rawLength, limitedBy: rephrasedText.endIndex) ?? rephrasedText.endIndex

                    var wordEnd = rawEnd
                    if wordEnd < rephrasedText.endIndex && rephrasedText[wordEnd] != " " {
                        // rawEnd is mid-word. Walk BACKWARD to the start of this word
                        // (right after the preceding space) so the word belongs to the
                        // NEXT attribute run (e.g. hyperlink), not this plain-text chunk.
                        // This avoids the forward-search problem where rawEnd lands in
                        // the last word (no trailing space) and eats the whole remainder.
                        var bwd = wordEnd
                        while bwd > rephrasedIndex {
                            let prev = rephrasedText.index(before: bwd)
                            if rephrasedText[prev] == " " { break }
                            bwd = prev
                        }
                        if bwd > rephrasedIndex {
                            // Cut right before this word; the space stays in this chunk
                            wordEnd = bwd
                        }
                        // If bwd == rephrasedIndex, no preceding space — keep rawEnd
                    }
                    let endIndex = wordEnd
                    let chunk = String(rephrasedText[rephrasedIndex..<endIndex])

                    var cleanAttrs = segment.attributes
                    cleanAttrs.removeValue(forKey: .attachment)
                    result.append(NSAttributedString(string: chunk, attributes: cleanAttrs))
                    rephrasedIndex = endIndex
                }
            }
        }

        // Append any excess rephrased text with default formatting
        if rephrasedIndex < rephrasedText.endIndex {
            let excess = String(rephrasedText[rephrasedIndex...])
            let defaultAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
            result.append(NSAttributedString(string: excess, attributes: defaultAttrs))
        }

        return result
    }
}
