import Foundation
import AppKit

class LLMRephraseService {
    static let shared = LLMRephraseService()

    private static let defaultSystemPrompt = "Rephrase the following text to add natural variety while preserving the original meaning, tone, and approximate length. Do not add explanations or notes. Return only the rephrased text."

    private init() {}

    // MARK: - Settings

    var selectedProvider: LLMProviderType {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "llm-provider"),
                  let provider = LLMProviderType(rawValue: raw) else {
                return .claude
            }
            return provider
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "llm-provider")
        }
    }

    var customSystemPrompt: String? {
        get { UserDefaults.standard.string(forKey: "llm-custom-prompt") }
        set { UserDefaults.standard.set(newValue, forKey: "llm-custom-prompt") }
    }

    var isConfigured: Bool {
        KeychainHelper.loadString(forKey: selectedProvider.keychainKey) != nil
    }

    // MARK: - System Prompt

    private var effectiveSystemPrompt: String {
        var prompt = Self.defaultSystemPrompt
        if let custom = customSystemPrompt, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n\nAdditional instructions: \(custom)"
        }
        return prompt
    }

    // MARK: - Provider Factory

    private func makeProvider() throws -> LLMProvider {
        let providerType = selectedProvider
        guard let apiKey = KeychainHelper.loadString(forKey: providerType.keychainKey) else {
            throw LLMError.noAPIKey
        }

        switch providerType {
        case .claude:
            return ClaudeProvider(apiKey: apiKey)
        case .openai:
            return OpenAIProvider(apiKey: apiKey)
        }
    }

    // MARK: - Plain Text Rephrase

    func rephrasePlainText(_ text: String) async throws -> String {
        let provider = try makeProvider()
        return try await provider.rephrase(text: text, systemPrompt: effectiveSystemPrompt)
    }

    // MARK: - Rich Text Rephrase (Format-Preserving)

    func rephraseAttributedString(_ attrStr: NSAttributedString) async throws -> NSAttributedString {
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
        let rephrasedText = try await rephrasePlainText(plainText)

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
                    // Proportional chunk
                    let proportion = totalOriginalLength > 0 ? Double(segment.text.count) / Double(totalOriginalLength) : 0
                    let chunkLength = max(1, Int(round(proportion * Double(rephrasedText.count))))
                    let endIndex = rephrasedText.index(rephrasedIndex, offsetBy: chunkLength, limitedBy: rephrasedText.endIndex) ?? rephrasedText.endIndex
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
