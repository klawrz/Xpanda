import Foundation

protocol LLMProvider {
    func rephrase(text: String, systemPrompt: String?) async throws -> String
}

enum LLMError: Error, LocalizedError {
    case noAPIKey
    case notAuthenticated
    case notSubscribed
    case networkError(Error)
    case invalidResponse
    case serverError(String)
    case timeout
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .noAPIKey:           return "AI not available"
        case .notAuthenticated:   return "Sign in to use AI features"
        case .notSubscribed:      return "Subscribe to Baeside AI to use this feature"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .invalidResponse:    return "Invalid response from server"
        case .serverError(let s): return "Server error: \(s)"
        case .timeout:            return "Request timed out"
        case .rateLimited:        return "Too many requests — please try again shortly"
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
