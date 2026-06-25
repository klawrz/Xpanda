import Foundation
import AppKit

class LLMRephraseService {
    static let shared = LLMRephraseService()

    private static let defaultSystemPrompt = "Rephrase the following text into a fresh version. Rules: (1) Preserve the grammatical person, voice, and tone of the original exactly — do not switch from second person to first person, or from active to passive, or change the formality level. (2) Preserve every factual claim and commitment — do not drop or weaken anything. (3) Match the word count closely — stay within 3 words of the original length. (4) Vary the wording and sentence structure so it does not sound like the previous versions. (5) Use only commas, periods, and apostrophes — no dashes of any kind. Return only the rephrased text with no explanation."

    private static let linkTokenInstruction = " (6) The text contains hyperlink placeholders in the format [LINK_0], [LINK_1], etc. Treat each placeholder as a single unbreakable word. Preserve them exactly as written — do not rephrase, split, remove, or reorder them."

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
        return AuthManager.cachedHasAIAccess
    }

    // MARK: - System Prompt

    private func effectiveSystemPrompt(for xpId: UUID?, hasLinks: Bool = false) -> String {
        var prompt = Self.defaultSystemPrompt
        if hasLinks {
            prompt += Self.linkTokenInstruction
        }
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

    // MARK: - Rich Text Rephrase (Link-Preserving)

    func rephraseAttributedString(_ attrStr: NSAttributedString, xpId: UUID? = nil) async throws -> NSAttributedString {

        // Collect every linked run in document order, assigning a token to each.
        struct LinkToken {
            let token: String          // e.g. "[LINK_0]"
            let originalText: String   // the visible label, preserved verbatim
            let attributes: [NSAttributedString.Key: Any]
        }

        var linkTokens: [LinkToken] = []
        attrStr.enumerateAttribute(.link, in: NSRange(location: 0, length: attrStr.length), options: []) { value, range, _ in
            guard value != nil else { return }
            let text = (attrStr.string as NSString).substring(with: range)
            let attrs = attrStr.attributes(at: range.location, effectiveRange: nil)
            linkTokens.append(LinkToken(token: "[LINK_\(linkTokens.count)]",
                                        originalText: text,
                                        attributes: attrs))
        }

        // Determine base attributes from the first non-link, non-attachment run so
        // that surrounding rephrased text inherits the correct font/colour.
        var baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        attrStr.enumerateAttributes(in: NSRange(location: 0, length: attrStr.length), options: []) { attrs, _, stop in
            if attrs[.link] == nil && attrs[.attachment] == nil {
                var clean = attrs
                clean.removeValue(forKey: .attachment)
                baseAttributes = clean
                stop.pointee = true
            }
        }

        // Build the tokenized plain string sent to the LLM:
        // replace each linked run with its placeholder in reverse index order
        // so earlier character offsets are not disturbed.
        var tokenized = attrStr.string

        var linkedRanges: [(NSRange, String)] = []
        var tokenIdx = 0
        attrStr.enumerateAttribute(.link, in: NSRange(location: 0, length: attrStr.length), options: []) { value, range, _ in
            guard value != nil else { return }
            linkedRanges.append((range, "[LINK_\(tokenIdx)]"))
            tokenIdx += 1
        }
        for (range, token) in linkedRanges.reversed() {
            let s = tokenized.index(tokenized.startIndex, offsetBy: range.location)
            let e = tokenized.index(s, offsetBy: range.length)
            tokenized.replaceSubrange(s..<e, with: token)
        }

        // Strip attachment characters (U+FFFC) — images are not rephrased.
        tokenized = tokenized.replacingOccurrences(of: "\u{FFFC}", with: "")

        let plainForLLM = tokenized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainForLLM.isEmpty else { return attrStr }

        // Rephrase — pass the link-preservation rule when there are tokens.
        let provider = BaesideProvider()
        let systemPrompt = effectiveSystemPrompt(for: xpId, hasLinks: !linkTokens.isEmpty)
        let rephrased = try await provider.rephrase(text: plainForLLM, systemPrompt: systemPrompt)
        if let xpId { saveRephrase(rephrased, for: xpId) }

        // Reconstruct the attributed string:
        // walk through the rephrased text finding each token in order and
        // replacing it with the original linked text + its original attributes.
        let result = NSMutableAttributedString()
        var pos = rephrased.startIndex

        for linkToken in linkTokens {
            guard let tokenRange = rephrased.range(of: linkToken.token, range: pos..<rephrased.endIndex) else {
                // LLM dropped the token — skip it (link is lost, acceptable edge case).
                continue
            }
            // Plain text before this token gets base formatting.
            let before = String(rephrased[pos..<tokenRange.lowerBound])
            if !before.isEmpty {
                result.append(NSAttributedString(string: before, attributes: baseAttributes))
            }
            // Original linked text restored verbatim with its original attributes.
            var linkAttrs = linkToken.attributes
            linkAttrs.removeValue(forKey: .attachment)
            result.append(NSAttributedString(string: linkToken.originalText, attributes: linkAttrs))
            pos = tokenRange.upperBound
        }

        // Remaining plain text after the last token.
        let tail = String(rephrased[pos...])
        if !tail.isEmpty {
            result.append(NSAttributedString(string: tail, attributes: baseAttributes))
        }

        return result
    }
}
