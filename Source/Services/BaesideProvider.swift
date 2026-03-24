import Foundation

// MARK: - BaesideProvider
// Sends rephrase requests to the Baeside AI Edge Function.
// Attaches the Supabase session JWT — the function validates it
// and checks the support_safari_pro entitlement server-side.

struct BaesideProvider: LLMProvider {
    private static let endpointURL = URL(
        string: "https://lhrsxckcqwjwmyajtxyi.supabase.co/functions/v1/ai-rephrase"
    )!

    func rephrase(text: String, systemPrompt: String?) async throws -> String {
        let isSignedIn = await MainActor.run { AuthManager.shared.isSignedIn }
        guard isSignedIn else {
            throw LLMError.notAuthenticated
        }

        let session = try await supabase.auth.session
        let jwt = session.accessToken

        var request = URLRequest(url: Self.endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        var body: [String: String] = ["text": text]
        if let sp = systemPrompt { body["systemPrompt"] = sp }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            struct RephraseResponse: Decodable { let result: String }
            let decoded = try JSONDecoder().decode(RephraseResponse.self, from: data)
            return decoded.result
        case 401:
            throw LLMError.notAuthenticated
        case 403:
            throw LLMError.notSubscribed
        case 429:
            throw LLMError.rateLimited
        default:
            throw LLMError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }
}
