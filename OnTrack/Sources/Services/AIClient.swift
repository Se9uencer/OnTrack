import Foundation

enum AIError: LocalizedError {
    case rateLimited
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited: return "AI is busy right now — try again shortly."
        case .http(let code): return "AI request failed (\(code)). Try again."
        }
    }
}

/// Talks to the OnTrack AI proxy (a Cloudflare Worker), which injects the Google
/// Gemini API key server-side and forwards to Gemini's OpenAI-compatible endpoint.
/// No AI key is ever shipped in the app. Request/response use OpenAI's chat shape,
/// which Gemini's `/v1beta/openai/` endpoint accepts (including base64 vision).
enum AIClient {
    static let endpoint = URL(string: "https://fittrack-ai.ibrahim-ansari0801.workers.dev")!
    // Optional speed-bump; must match APP_TOKEN set on the Worker.
    // ponytail: extractable from binary — blocks drive-by abuse only; per-IP rate limit on the Worker is the real control
    static let appToken = (Bundle.main.object(forInfoDictionaryKey: "APP_TOKEN") as? String) ?? ""

    struct Message: Codable {
        let role: String
        let content: String
    }

    private static func proxyRequest(timeout: TimeInterval) -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !appToken.isEmpty { req.setValue(appToken, forHTTPHeaderField: "x-app-token") }
        return req
    }

    /// Streaming completion — yields content deltas as they arrive (SSE).
    static func stream(messages: [Message]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = proxyRequest(timeout: 30)
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "temperature": 0.6,
                        "max_tokens": 1024,
                        "stream": true,
                    ])
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        throw http.statusCode == 429 ? AIError.rateLimited : AIError.http(http.statusCode)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        if let data = payload.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                           let delta = chunk.choices.first?.delta.content {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Full completion via the streaming path — avoids idle timeouts on slow
    /// generations since bytes keep flowing while the model writes.
    static func complete(messages: [Message]) async throws -> String {
        var result = ""
        for try await delta in stream(messages: messages) {
            result += delta
        }
        return result
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }

    // MARK: - Photo meal estimation (multimodal)

    struct MealEstimate: Decodable {
        let name: String
        let calories: Double
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
    }

    /// Text-only estimate for a food the local/online search couldn't find at all — the
    /// empty-search-result fallback (not the paywalled photo/coach features; an empty search
    /// is broken core functionality, not an upsell). Caller is responsible for rate limiting.
    static func estimateFood(name: String) async throws -> MealEstimate {
        let prompt = "You are a nutritionist. Estimate the nutrition of a typical single serving of: \(name). Respond with ONLY a JSON object, no other text, in exactly this format: {\"name\": \"short dish name\", \"calories\": 0, \"protein_g\": 0, \"carbs_g\": 0, \"fat_g\": 0}"
        var req = proxyRequest(timeout: 20)
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.2,
            "max_tokens": 150,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? AIError.rateLimited : AIError.http(http.statusCode)
        }
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String }
                let message: Msg
            }
            let choices: [Choice]
        }
        let content = try JSONDecoder().decode(Completion.self, from: data)
            .choices.first?.message.content ?? ""
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              let jsonData = String(content[start...end]).data(using: .utf8),
              let estimate = try? JSONDecoder().decode(MealEstimate.self, from: jsonData)
        else { throw AIError.http(422) }
        return estimate
    }

    static func estimateMeal(imageJPEG: Data, description: String?) async throws -> MealEstimate {
        var prompt = """
        You are a nutritionist. Estimate the nutrition of the ENTIRE visible portion of food in this photo. \
        Respond with ONLY a JSON object, no other text, in exactly this format: \
        {"name": "short dish name", "calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0}
        """
        if let description, !description.trimmingCharacters(in: .whitespaces).isEmpty {
            prompt += "\nThe user describes it as: \(description)"
        }

        var req = proxyRequest(timeout: 60) // image upload + analysis takes longer than text
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url",
                     "image_url": ["url": "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"]],
                ],
            ]],
            "temperature": 0.2,
            "max_tokens": 200,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? AIError.rateLimited : AIError.http(http.statusCode)
        }
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String }
                let message: Msg
            }
            let choices: [Choice]
        }
        let content = try JSONDecoder().decode(Completion.self, from: data)
            .choices.first?.message.content ?? ""

        // Models sometimes wrap JSON in markdown fences or prose — extract the object.
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              let jsonData = String(content[start...end]).data(using: .utf8),
              let estimate = try? JSONDecoder().decode(MealEstimate.self, from: jsonData)
        else { throw AIError.http(422) }
        return estimate
    }
}
