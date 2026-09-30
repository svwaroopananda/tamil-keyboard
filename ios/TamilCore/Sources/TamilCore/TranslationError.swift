import Foundation

public enum TranslationError: Error, Equatable {
    /// Input was empty (or whitespace-only). Rejected before any network call.
    case emptyInput
    /// The network request itself failed (no connection, timed out, DNS
    /// failure, etc.) -- we never got an HTTP response at all.
    case backendUnreachable(String)
    /// Got an HTTP response, but the status code wasn't 200. `message`
    /// carries the backend's "error" field when present.
    case unexpectedStatusCode(Int, message: String?)
    /// Got a 200, but the body wasn't valid JSON, was empty, or didn't
    /// contain a non-empty "tamil" string.
    case malformedResponse
    /// A translate() call was already in progress when this one started.
    case requestInFlight
}
