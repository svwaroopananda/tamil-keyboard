import XCTest
@testable import TamilCore

final class TranslationClientTests: XCTestCase {

    private let baseURL = URL(string: "http://localhost:3000")!

    // MARK: - Success

    func testSuccessReturnsTamilText() async throws {
        let mock = MockHTTPClient(behavior: .success(
            status: 200,
            body: #"{"tamil": "vanakkam da"}"#.data(using: .utf8)!
        ))
        let client = TranslationClient(baseURL: baseURL, httpClient: mock)

        let result = try await client.translate("hello")

        XCTAssertEqual(result, "vanakkam da")
    }

    // MARK: - Empty input (rejected before any network call)

    func testEmptyInputThrowsWithoutNetworkCall() async throws {
        let mock = MockHTTPClient(behavior: .success(status: 200, body: Data()))
        let client = TranslationClient(baseURL: baseURL, httpClient: mock)

        do {
            _ = try await client.translate("   ")
            XCTFail("expected emptyInput to be thrown")
        } catch TranslationError.emptyInput {
            // expected
        }

        let callCount = await mock.callCount
        XCTAssertEqual(callCount, 0, "must not touch the network for empty input")
    }

    // MARK: - Backend unreachable

    func testBackendUnreachableWrapsUnderlyingError() async throws {
        let mock = MockHTTPClient(behavior: .failure(URLError(.cannotConnectToHost)))
        let client = TranslationClient(baseURL: baseURL, httpClient: mock)

        do {
            _ = try await client.translate("hello")
            XCTFail("expected backendUnreachable to be thrown")
        } catch TranslationError.backendUnreachable {
            // expected
        }
    }

    // MARK: - Non-200 status

    func testBadRequestStatusSurfacesServerMessage() async throws {
        let mock = MockHTTPClient(behavior: .success(
            status: 400,
            body: #"{"error": "Request body must include a non-empty string \"text\" field."}"#.data(using: .utf8)!
        ))
        let client = TranslationClient(baseURL: baseURL, httpClient: mock)

        do {
            _ = try await client.translate("hello")
            XCTFail("expected unexpectedStatusCode to be thrown")
        } catch TranslationError.unexpectedStatusCode(let code, let message) {
            XCTAssertEqual(code, 400)
            XCTAssertEqual(message, "Request body must include a non-empty string \"text\" field.")
        }
    }

    func testUpstreamFailureStatusSurfacesServerMessage() async throws {
        let mock = MockHTTPClient(behavior: .success(
            status: 502,
            body: #"{"error": "Translation failed. Please try again."}"#.data(using: .utf8)!
        ))
        let client = TranslationClient(baseURL: baseURL, httpClient: mock)

        do {
            _ = try await client.translate("hello")
            XCTFail("expected unexpectedStatusCode to be thrown")
        } catch TranslationError.unexpectedStatusCode(let code, let message) {
            XCTAssertEqual(code, 502)
            XCTAssertEqual(message, "Translation failed. Please try again.")
        }
    }

    // MARK: - Malformed / empty response

    func testInvalidJSONIsMalformedResponse() async throws {
        let mock = MockHTTPClient(behavior: .success(status: 200, body: "not json".data(using: .utf8)!))
        let client = TranslationClient(baseURL: baseURL, httpClient: mock)

        do {
            _ = try await client.translate("hello")
            XCTFail("expected malformedResponse to be thrown")
        } catch TranslationError.malformedResponse {
            // expected
        }
    }

    func testMissingTamilKeyIsMalformedResponse() async throws {
        let mock = MockHTTPClient(behavior: .success(
            status: 200,
            body: #"{"unexpected": "field"}"#.data(using: .utf8)!
        ))
        let client = TranslationClient(baseURL: baseURL, httpClient: mock)

        do {
            _ = try await client.translate("hello")
            XCTFail("expected malformedResponse to be thrown")
        } catch TranslationError.malformedResponse {
            // expected
        }
    }

    func testEmptyTamilStringIsMalformedResponse() async throws {
        let mock = MockHTTPClient(behavior: .success(status: 200, body: #"{"tamil": ""}"#.data(using: .utf8)!))
        let client = TranslationClient(baseURL: baseURL, httpClient: mock)

        do {
            _ = try await client.translate("hello")
            XCTFail("expected malformedResponse to be thrown")
        } catch TranslationError.malformedResponse {
            // expected
        }
    }

    func testEmptyResponseBodyIsMalformedResponse() async throws {
        let mock = MockHTTPClient(behavior: .success(status: 200, body: Data()))
        let client = TranslationClient(baseURL: baseURL, httpClient: mock)

        do {
            _ = try await client.translate("hello")
            XCTFail("expected malformedResponse to be thrown")
        } catch TranslationError.malformedResponse {
            // expected
        }
    }

    // MARK: - Duplicate in-flight request

    /// Fires two translate() calls at genuinely the same time (no gate, no
    /// sleep deciding who goes first) and checks the *invariant* -- exactly
    /// one is rejected, exactly one succeeds, exactly one network call
    /// happens -- without assuming which of the two literally won the race
    /// to the actor. The mock's gate is what makes this deterministic: the
    /// winner cannot complete (and clear isTranslating) before we've had a
    /// chance to observe that only one network call was made, because it's
    /// parked on a continuation we control.
    func testConcurrentCallsRejectExactlyOneWithRequestInFlight() async throws {
        let mock = MockHTTPClient(behavior: .gated(
            status: 200,
            body: #"{"tamil": "vanakkam"}"#.data(using: .utf8)!
        ))
        let client = TranslationClient(baseURL: baseURL, httpClient: mock)

        async let callA = attempt(client: client, text: "hello")
        async let callB = attempt(client: client, text: "world")

        // Whichever call reaches the actor first sets isTranslating and
        // then suspends inside the mock's gate (the only await in its
        // path). The other call, by actor exclusivity, cannot run its own
        // check-and-set until that happens -- so once the mock has been
        // entered, the loser is guaranteed to see isTranslating == true
        // whenever it does run, with nothing else competing for the
        // actor's attention in between. No sleep needed.
        await mock.waitUntilCalled()

        let callCountWhileGated = await mock.callCount
        XCTAssertEqual(callCountWhileGated, 1, "only the winning call should ever reach the network")

        // Release the gate so the winner can finish, then collect both
        // results -- safe now, neither call can still be blocked on
        // anything by this point.
        await mock.release()
        let resultA = await callA
        let resultB = await callB
        let results = [resultA, resultB]

        let requestInFlightCount = results.filter { result in
            if case .failure(let error) = result, error as? TranslationError == .requestInFlight {
                return true
            }
            return false
        }.count
        XCTAssertEqual(requestInFlightCount, 1, "exactly one of the two concurrent calls must be rejected, regardless of which")

        let successResults = results.compactMap { result -> String? in
            if case .success(let value) = result { return value }
            return nil
        }
        XCTAssertEqual(successResults, ["vanakkam"], "the winning call must still complete successfully")

        let callCountAfterBoth = await mock.callCount
        XCTAssertEqual(callCountAfterBoth, 1, "the rejected call must never have reached the network")

        // The flag must be cleared once the winning call finishes -- a
        // later call should succeed normally, not stay locked out forever.
        // Switch the mock off .gated first: it would otherwise suspend this
        // call on the gate too, waiting for a release() that never comes.
        await mock.setBehavior(.success(
            status: 200,
            body: #"{"tamil": "vanakkam"}"#.data(using: .utf8)!
        ))
        let thirdResult = try await client.translate("again")
        XCTAssertEqual(thirdResult, "vanakkam")

        let finalCallCount = await mock.callCount
        XCTAssertEqual(finalCallCount, 2)
    }

    private func attempt(client: TranslationClient, text: String) async -> Result<String, Error> {
        do {
            return .success(try await client.translate(text))
        } catch {
            return .failure(error)
        }
    }
}
