import Foundation

/// Tracks what this keyboard has typed since the last translation (or
/// reset), plus shift/layer state -- everything needed to type correctly
/// and to safely replace exactly the English it wrote with Tamil later.
/// A plain struct, not an actor: every mutation happens synchronously on
/// the main thread, driven by a single finger tapping keys one at a time.
/// There's no concurrent access to protect against here.
public struct KeyboardEngine {
    public enum Layer {
        case letters
        case numbers
    }

    public enum ShiftState {
        case off
        case shiftedOnce
    }

    /// What a tap on Translate should actually do, decided here (not by
    /// the view controller) so the "why nothing happened" logic lives in
    /// one pure, testable place.
    public enum TranslateAvailability: Equatable {
        case ready(String)
        case nothingToTranslate
        case tooLong
        case contextUnavailable
    }

    public private(set) var layer: Layer = .letters
    public private(set) var shiftState: ShiftState = .off
    public private(set) var trackedText: String = ""
    private var isOverflowed = false

    // Many host apps truncate what documentContextBeforeInput returns
    // (sometimes just the current sentence). 500 comfortably covers a real
    // chat message; typing past it disables tracking entirely rather than
    // silently sliding-window-truncating, which would translate only part
    // of what the user actually typed and look like a bug.
    private static let maxTrackedLength = 500

    public init() {}

    /// Handles letters, digits, punctuation, space, and "\n" uniformly.
    /// Shift only applies to (and is only consumed by) letters -- tapping
    /// a digit/punctuation/space while shiftedOnce leaves shift armed.
    @discardableResult
    public mutating func type(_ character: Character) -> Character {
        let output: Character
        if shiftState == .shiftedOnce, character.isLetter {
            output = Character(character.uppercased())
            shiftState = .off
        } else {
            output = character
        }

        guard !isOverflowed else {
            return output
        }

        if trackedText.count + 1 > Self.maxTrackedLength {
            isOverflowed = true
        } else {
            trackedText.append(output)
        }

        return output
    }

    public mutating func toggleShift() {
        shiftState = (shiftState == .off) ? .shiftedOnce : .off
    }

    public mutating func switchLayer(to newLayer: Layer) {
        layer = newLayer
    }

    /// Pops the last tracked character. Does nothing while overflowed --
    /// tracking stays disabled regardless of how much is deleted; only an
    /// explicit reset (resetAfterTranslation, or a validation mismatch)
    /// re-enables it.
    public mutating func backspace() {
        guard !isOverflowed, !trackedText.isEmpty else { return }
        trackedText.removeLast()
    }

    /// The single entry point the view controller calls both at tap-time
    /// and again, authoritatively, right before delete/insert (using a
    /// freshly-read documentContextBeforeInput) -- textDidChange alone is
    /// only a soft signal, not trusted as the sole gate, since some
    /// WebView-backed text fields don't fire it reliably.
    public mutating func prepareTranslateRequest(documentContextBeforeInput: String?) -> TranslateAvailability {
        guard !isOverflowed else {
            return .tooLong
        }

        guard let context = documentContextBeforeInput else {
            resetTracking()
            return .contextUnavailable
        }

        guard !trackedText.isEmpty else {
            return .nothingToTranslate
        }

        guard isConsistent(trackedText: trackedText, context: context) else {
            resetTracking()
            return .nothingToTranslate
        }

        return .ready(trackedText)
    }

    public mutating func resetAfterTranslation() {
        resetTracking()
    }

    private mutating func resetTracking() {
        trackedText = ""
        isOverflowed = false
    }

    /// documentContextBeforeInput isn't guaranteed to return the full
    /// preceding text, so a straight "trackedText is a suffix of context"
    /// check breaks the moment a host app returns a truncated context for
    /// a longer message. The comparison instead goes by whichever string
    /// is shorter: if context is at least as long as trackedText,
    /// trackedText must be a suffix of context (the normal case); if
    /// context is shorter, context must itself be a suffix of trackedText
    /// (the truncated-but-still-consistent case) -- both are anchored at
    /// the cursor, so a shorter one should equal the tail of the longer
    /// one when tracking is genuinely valid.
    ///
    /// One case is carved out first: an empty context is always a
    /// mismatch here (trackedText is already known non-empty by the only
    /// caller). "" is a trivial suffix of every string, so the general
    /// rule above would otherwise treat a cleared field as perfectly
    /// consistent -- exactly what happens right after the user taps the
    /// host app's Send button. Without this carve-out, the next message
    /// typed would get the already-sent English silently prepended to it.
    private func isConsistent(trackedText: String, context: String) -> Bool {
        guard !context.isEmpty else { return false }

        if context.count >= trackedText.count {
            return context.hasSuffix(trackedText)
        } else {
            return trackedText.hasSuffix(context)
        }
    }
}
