import Foundation

enum LLMProviderType: String, Codable, CaseIterable {
    case claude = "Claude"
    case openai = "OpenAI"

    var defaultModel: String {
        switch self {
        case .claude: return "claude-haiku-4-5-20251001"
        case .openai: return "gpt-4o-mini"
        }
    }

    var keychainKey: String {
        switch self {
        case .claude: return "claude-api-key"
        case .openai: return "openai-api-key"
        }
    }
}

protocol LLMProvider {
    func rephrase(text: String, systemPrompt: String?) async throws -> String
}

enum LLMError: Error, LocalizedError {
    case noAPIKey
    case networkError(Error)
    case invalidResponse
    case timeout
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .invalidResponse: return "Invalid response from API"
        case .timeout: return "Request timed out"
        case .rateLimited: return "Rate limited by API"
        }
    }
}

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw LLMError.timeout
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
