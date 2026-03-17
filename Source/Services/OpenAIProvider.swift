import Foundation

struct OpenAIProvider: LLMProvider {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = LLMProviderType.openai.defaultModel) {
        self.apiKey = apiKey
        self.model = model
    }

    func rephrase(text: String, systemPrompt: String?) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var messages: [[String: String]] = []

        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }

        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 1024,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw LLMError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw LLMError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let responseText = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return responseText
    }
}
