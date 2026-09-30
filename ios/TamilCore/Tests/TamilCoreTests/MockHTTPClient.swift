import Foundation
@testable import TamilCore

/// An actor (not a plain class) so its state can be safely touched from
/// both the code under test and the test itself, even when they run
/// concurrently.
actor MockHTTPClient: HTTPClient {
    enum Behavior {
        case success(status: Int, body: Data)
        case failure(Error)
        /// Suspends data(for:) on a real continuation instead of returning
        /// immediately or sleeping for a fixed duration -- the test decides
        /// exactly when this call is allowed to complete, by calling
        /// release(). This makes "is a request currently in flight" tests
        /// deterministic instead of timing-dependent.
        case gated(status: Int, body: Data)
    }

    private(set) var callCount = 0
    private var behavior: Behavior

    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var calledContinuation: CheckedContinuation<Void, Never>?
    private var hasBeenCalled = false

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        markCalled()

        switch behavior {
        case .success(let status, let body):
            return (body, makeResponse(status: status, url: request.url!))
        case .failure(let error):
            throw error
        case .gated(let status, let body):
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                releaseContinuation = continuation
            }
            return (body, makeResponse(status: status, url: request.url!))
        }
    }

    /// Suspends until data(for:) has actually been entered at least once.
    /// Lets a test wait for "the request has genuinely started" without
    /// guessing how long that takes.
    func waitUntilCalled() async {
        guard !hasBeenCalled else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            calledContinuation = continuation
        }
    }

    /// Lets a call parked in the `.gated` case of data(for:) complete.
    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    /// Switches behavior for subsequent calls -- e.g. from `.gated` to
    /// `.success` once a test is done exercising the gate, so a later call
    /// doesn't suspend forever waiting for a release() that isn't coming.
    func setBehavior(_ newBehavior: Behavior) {
        behavior = newBehavior
    }

    private func markCalled() {
        hasBeenCalled = true
        calledContinuation?.resume()
        calledContinuation = nil
    }

    private func makeResponse(status: Int, url: URL) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}
