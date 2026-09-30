import Foundation

/// Calls the backend's POST /translate endpoint to turn English text into
/// conversational Tanglish. An `actor` so its "is a request already in
/// flight" flag can never be raced by two overlapping calls -- the Swift
/// compiler enforces that only one method body runs against this actor's
/// state at a time.
public actor TranslationClient {
    /// The one place the backend's address is defined. Callers that don't
    /// override it (the keyboard extension, today) all point at the same
    /// value -- there's nowhere else in the app a URL gets hardcoded.
    public static let defaultBaseURL = URL(string: "http://localhost:3000")!

    private let baseURL: URL
    private let httpClient: HTTPClient

    // Set/cleared entirely within the synchronous, non-suspending prefix of
    // translate() -- the check, the set, and the eventual clear (via defer)
    // never straddle an `await`. That's what makes this safe under actor
    // reentrancy: an actor only guarantees exclusivity *between* suspension
    // points, not across one, so anything that toggles state on both sides
    // of an `await` can be interleaved by another call. This flag never
    // does that -- it's flipped to true before the first await, and only
    // ever read/flipped back by code that itself has no await before it.
    // An earlier design instead stored the in-flight network call as a
    // `Task` and had a second call `await` that same task's `.value` to
    // "share" the result. That was a genuine bug, not just a style choice:
    // a second call for *different* text would silently receive the first
    // call's translation instead of its own, with no error at all. This
    // flag-based version can't do that -- it never reuses another call's
    // result, it just refuses a second call outright while one is running.
    private var isTranslating = false

    public init(baseURL: URL = TranslationClient.defaultBaseURL, httpClient: HTTPClient = URLSession.shared) {
        self.baseURL = baseURL
        self.httpClient = httpClient
    }

    public func translate(_ englishText: String) async throws -> String {
        let trimmed = englishText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyInput
        }
        guard !isTranslating else {
            throw TranslationError.requestInFlight
        }

        isTranslating = true
        defer { isTranslating = false }

        // No wrapping Task { } here -- we await performRequest directly, so
        // this call's own Task (and its cancellation) propagates straight
        // through, rather than being decoupled from an internally-spawned
        // unstructured task.
        return try await performRequest(trimmed)
    }

    private func performRequest(_ text: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("translate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw TranslationError.backendUnreachable(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.malformedResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw TranslationError.unexpectedStatusCode(httpResponse.statusCode, message: body?["error"] as? String)
        }

        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tamil = json["tamil"] as? String,
              !tamil.isEmpty
        else {
            throw TranslationError.malformedResponse
        }

        return tamil
    }
}
