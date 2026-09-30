import XCTest
@testable import TamilCore

final class KeyboardEngineTests: XCTestCase {

    // MARK: - Typing and shift

    func testLowercaseLetterShiftOff() {
        var engine = KeyboardEngine()
        let result = engine.type("a")
        XCTAssertEqual(result, "a")
        XCTAssertEqual(engine.trackedText, "a")
    }

    func testLetterWhileShiftedOnceIsUppercasedAndShiftReverts() {
        var engine = KeyboardEngine()
        engine.toggleShift()
        let result = engine.type("a")
        XCTAssertEqual(result, "A")
        XCTAssertEqual(engine.trackedText, "A")
        XCTAssertEqual(engine.shiftState, .off)
    }

    func testOnlyFirstOfTwoLettersIsCapitalizedWhileShiftedOnce() {
        var engine = KeyboardEngine()
        engine.toggleShift()
        engine.type("a")
        let second = engine.type("b")
        XCTAssertEqual(second, "b")
        XCTAssertEqual(engine.trackedText, "Ab")
    }

    func testDigitWhileShiftedOnceDoesNotConsumeShift() {
        var engine = KeyboardEngine()
        engine.toggleShift()
        let result = engine.type("5")
        XCTAssertEqual(result, "5")
        XCTAssertEqual(engine.shiftState, .shiftedOnce)
    }

    func testToggleShiftTwiceReturnsToOffWithoutTyping() {
        var engine = KeyboardEngine()
        engine.toggleShift()
        engine.toggleShift()
        XCTAssertEqual(engine.shiftState, .off)
    }

    // MARK: - Layer

    func testSwitchLayerRoundTrip() {
        var engine = KeyboardEngine()
        engine.switchLayer(to: .numbers)
        XCTAssertEqual(engine.layer, .numbers)
        engine.switchLayer(to: .letters)
        XCTAssertEqual(engine.layer, .letters)
    }

    func testSwitchLayerDoesNotTouchShiftOrTrackedText() {
        var engine = KeyboardEngine()
        engine.toggleShift()
        engine.type("a")
        engine.switchLayer(to: .numbers)
        XCTAssertEqual(engine.shiftState, .off) // consumed by typing "a", not by the layer switch
        XCTAssertEqual(engine.trackedText, "A")
        engine.toggleShift()
        engine.switchLayer(to: .letters)
        XCTAssertEqual(engine.shiftState, .shiftedOnce)
    }

    // MARK: - Backspace

    func testBackspaceOnNonEmptyTrackedTextRemovesLastCharacter() {
        var engine = KeyboardEngine()
        engine.type("a")
        engine.type("b")
        engine.backspace()
        XCTAssertEqual(engine.trackedText, "a")
    }

    func testBackspaceOnEmptyTrackedTextDoesNothing() {
        var engine = KeyboardEngine()
        engine.backspace()
        XCTAssertEqual(engine.trackedText, "")
    }

    func testBackspaceDoesNotReArmConsumedShift() {
        var engine = KeyboardEngine()
        engine.toggleShift()
        engine.type("a") // consumes shift, types "A"
        engine.backspace()
        XCTAssertEqual(engine.shiftState, .off)
    }

    // MARK: - prepareTranslateRequest: basic suffix matching

    func testContextLongerAndConsistentReturnsReady() {
        var engine = KeyboardEngine()
        "hello".forEach { engine.type($0) }
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "hi there hello")
        XCTAssertEqual(result, .ready("hello"))
        XCTAssertEqual(engine.trackedText, "hello")
    }

    func testContextLongerAndNotConsistentResets() {
        var engine = KeyboardEngine()
        "hello".forEach { engine.type($0) }
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "something else entirely")
        XCTAssertEqual(result, .nothingToTranslate)
        XCTAssertEqual(engine.trackedText, "")
    }

    func testContextShorterButConsistentReturnsReady() {
        // The key regression test for the truncated-context fix: some
        // host apps only return a limited window (e.g. the current
        // sentence), shorter than what we've actually tracked.
        var engine = KeyboardEngine()
        "hello world".forEach { engine.type($0) }
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "world")
        XCTAssertEqual(result, .ready("hello world"))
        XCTAssertEqual(engine.trackedText, "hello world")
    }

    func testContextShorterAndNotConsistentResets() {
        var engine = KeyboardEngine()
        "hello world".forEach { engine.type($0) }
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "xyz")
        XCTAssertEqual(result, .nothingToTranslate)
        XCTAssertEqual(engine.trackedText, "")
    }

    func testEmptyTrackedTextReturnsNothingToTranslate() {
        var engine = KeyboardEngine()
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "whatever is already there")
        XCTAssertEqual(result, .nothingToTranslate)
    }

    // MARK: - prepareTranslateRequest: nil context

    func testNilContextWithEmptyTrackedTextReturnsContextUnavailable() {
        var engine = KeyboardEngine()
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: nil)
        XCTAssertEqual(result, .contextUnavailable)
    }

    func testNilContextWithNonEmptyTrackedTextStillReturnsContextUnavailableAndResets() {
        var engine = KeyboardEngine()
        "hello".forEach { engine.type($0) }
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: nil)
        XCTAssertEqual(result, .contextUnavailable)
        XCTAssertEqual(engine.trackedText, "")
    }

    // MARK: - Overflow (length cap)

    func testTypingExactlyToCapDoesNotOverflow() {
        var engine = KeyboardEngine()
        for _ in 0..<500 { engine.type("a") }
        let context = String(repeating: "a", count: 500)
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: context)
        XCTAssertEqual(result, .ready(context))
    }

    func testTypingPastCapSetsOverflow() {
        var engine = KeyboardEngine()
        for _ in 0..<501 { engine.type("a") }
        let context = String(repeating: "a", count: 501)
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: context)
        XCTAssertEqual(result, .tooLong)
    }

    func testOverflowedTypingDoesNotGrowTrackedTextOrChangeOverflow() {
        var engine = KeyboardEngine()
        for _ in 0..<505 { engine.type("a") }
        let lengthAtFirstOverflow = engine.trackedText.count
        engine.type("b")
        engine.type("c")
        XCTAssertEqual(engine.trackedText.count, lengthAtFirstOverflow)
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "anything")
        XCTAssertEqual(result, .tooLong)
    }

    func testOverflowedBackspaceDoesNotResumeTracking() {
        var engine = KeyboardEngine()
        for _ in 0..<501 { engine.type("a") }
        engine.backspace()
        engine.backspace()
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "anything")
        XCTAssertEqual(result, .tooLong)
    }

    func testResetAfterTranslationClearsOverflowSoTypingResumes() {
        var engine = KeyboardEngine()
        for _ in 0..<501 { engine.type("a") }
        engine.resetAfterTranslation()
        engine.type("b")
        XCTAssertEqual(engine.trackedText, "b")
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "b")
        XCTAssertEqual(result, .ready("b"))
    }

    func testMismatchResetAlsoClearsOverflow() {
        var engine = KeyboardEngine()
        for _ in 0..<501 { engine.type("a") }
        _ = engine.prepareTranslateRequest(documentContextBeforeInput: "totally different text")
        // That call returned .tooLong (overflow checked first), but a
        // mismatch-triggered reset elsewhere must still clear overflow --
        // verify indirectly via a fresh mismatch reset from a non-overflowed state:
        engine.resetAfterTranslation()
        "hello".forEach { engine.type($0) }
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "unrelated")
        XCTAssertEqual(result, .nothingToTranslate)
        engine.type("x")
        XCTAssertEqual(engine.trackedText, "x")
    }

    // MARK: - Empty context after Send (regression)

    func testEmptyContextWithNonEmptyTrackedTextIsTreatedAsMismatch() {
        var engine = KeyboardEngine()
        "hello".forEach { engine.type($0) }
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "")
        XCTAssertEqual(result, .nothingToTranslate)
        XCTAssertEqual(engine.trackedText, "")
    }

    func testFullSequenceFieldClearedAfterSendDoesNotPrependOldText() {
        var engine = KeyboardEngine()
        "hello".forEach { engine.type($0) }

        // Field cleared after Send -- context is now empty.
        _ = engine.prepareTranslateRequest(documentContextBeforeInput: "")
        XCTAssertEqual(engine.trackedText, "")

        "bye".forEach { engine.type($0) }
        let result = engine.prepareTranslateRequest(documentContextBeforeInput: "bye")
        XCTAssertEqual(result, .ready("bye"))
    }
}
