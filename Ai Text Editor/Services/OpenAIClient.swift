import Foundation

private struct AIRequestBody: Codable {
    let mode: String            // "rewrite" or "continue"
    let prompt: String
    let selection: String?
    let system: String?
    let model: String
    let stream: Bool
}

final class OpenAIClient {
    static let shared = OpenAIClient()
    private init() {}

    // ⬅️ Your Worker URL (correct)
    private let PROXY_BASE_URL = URL(string: "https://ai-text-editor-proxy.covionstudio.workers.dev")!

    // For immediate success, start with one-shot JSON (no SSE).
    // After you confirm it works, set this to true for live streaming.
    private let USE_STREAM = false
    private let DEBUG_LOG = true

    func streamText(
        mode: String,
        prompt: String,
        selection: String?,
        system: String? = nil,
        model: String = "gpt-4o-mini"
    ) async throws -> AsyncThrowingStream<String, Error> {

        var req = URLRequest(url: PROXY_BASE_URL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept") // helps when streaming
        let body = AIRequestBody(
            mode: mode,
            prompt: prompt,
            selection: selection,
            system: system,
            model: model,
            stream: USE_STREAM
        )
        req.httpBody = try JSONEncoder().encode(body)

        if DEBUG_LOG {
            print("➡️ POST \(PROXY_BASE_URL.absoluteString)")
            if let b = req.httpBody, let s = String(data: b, encoding: .utf8) { print("📦 Body: \(s)") }
        }

        if USE_STREAM {
            // --- Streaming path (SSE) ---
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if DEBUG_LOG { print("⬅️ HTTP \(http.statusCode)") }

            guard (200..<300).contains(http.statusCode) else {
                if DEBUG_LOG {
                    let (data, resp2) = try await URLSession.shared.data(for: req)
                    let status = (resp2 as? HTTPURLResponse)?.statusCode ?? -1
                    let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                    print("❌ HTTP \(status) body:\n\(text)")
                }
                throw URLError(.badServerResponse)
            }

            return AsyncThrowingStream { continuation in
                Task {
                    var finished = false
                    func safeFinish(_ err: Error? = nil) {
                        guard !finished else { return }
                        finished = true
                        if let err { continuation.finish(throwing: err) } else { continuation.finish() }
                    }

                    do {
                        for try await raw in bytes.lines {
                            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard line.hasPrefix("data:") else { continue }
                            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if payload == "[DONE]" { break }
                            guard let data = payload.data(using: .utf8) else { continue }

                            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                if let type = obj["type"] as? String {
                                    if type == "response.output_text.delta",
                                       let delta = obj["delta"] as? [String: Any],
                                       let t = delta["text"] as? String, !t.isEmpty {
                                        if DEBUG_LOG { print("🔵 chunk:", t) }
                                        continuation.yield(t)
                                        continue
                                    }
                                    if type.hasSuffix(".delta"),
                                       let delta = obj["delta"] as? [String: Any],
                                       let content = delta["content"] as? [[String: Any]] {
                                        for part in content {
                                            if (part["type"] as? String) == "output_text",
                                               let t = part["text"] as? String, !t.isEmpty {
                                                if DEBUG_LOG { print("🔵 chunk(content):", t) }
                                                continuation.yield(t)
                                            } else if let t = part["text"] as? String, !t.isEmpty {
                                                if DEBUG_LOG { print("🔵 chunk(text):", t) }
                                                continuation.yield(t)
                                            }
                                        }
                                        continue
                                    }
                                    if type == "response.completed" {
                                        if let outputText = obj["output_text"] as? String, !outputText.isEmpty {
                                            if DEBUG_LOG { print("🟢 completed:", outputText) }
                                            continuation.yield(outputText)
                                        }
                                        continue
                                    }
                                }
                                if let t = obj["output_text"] as? String, !t.isEmpty {
                                    if DEBUG_LOG { print("🟢 output_text:", t) }
                                    continuation.yield(t); continue
                                }
                                if let delta = obj["delta"] as? [String: Any],
                                   let t = delta["text"] as? String, !t.isEmpty {
                                    if DEBUG_LOG { print("🟢 delta.text:", t) }
                                    continuation.yield(t); continue
                                }
                            } else {
                                if DEBUG_LOG { print("⚪️ non-JSON SSE payload:", payload) }
                            }
                        }
                        safeFinish(nil)
                    } catch {
                        if DEBUG_LOG { print("❌ stream error:", error.localizedDescription) }
                        safeFinish(error)
                    }
                }
            }
        } else {
            // --- Non-stream path (debug): plain JSON from Worker, emit once ---
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if DEBUG_LOG { print("⬅️ HTTP \(http.statusCode)") }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                if DEBUG_LOG { print("❌ HTTP \(http.statusCode) body:\n\(text)") }
                throw URLError(.badServerResponse)
            }

            var output = ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let t = obj["output_text"] as? String { output = t }
                else if let outArr = obj["output"] as? [[String: Any]],
                        let first = outArr.first,
                        let content = first["content"] as? [[String: Any]] {
                    for part in content {
                        if (part["type"] as? String) == "output_text",
                           let t = part["text"] as? String { output += t }
                        else if let t = part["text"] as? String { output += t }
                    }
                }
            }
            if DEBUG_LOG { print("🟢 one-shot:", output) }

            return AsyncThrowingStream { cont in
                cont.yield(output)
                cont.finish()
            }
        }
    }
}
