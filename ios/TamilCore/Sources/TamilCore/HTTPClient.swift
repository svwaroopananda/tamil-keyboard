import Foundation

/// A minimal seam over networking so tests can substitute a mock instead of
/// hitting a real server. URLSession already implements this exact method
/// signature, so it conforms for free (see extension below) -- production
/// code needs no special wiring to use the real network.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}
