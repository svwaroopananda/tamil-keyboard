# 0004: In-Place Translation via Self-Tracked Text, and Why Auto-Send Isn't Possible

## Context

The keyboard needs to replace the English a user just typed with its Tamil
translation, directly in whatever app they're typing in (Messages,
WhatsApp, Notes), so they only have to tap that app's own Send button
afterward. `UITextDocumentProxy` -- the only interface a keyboard extension
has to the host app's text field -- has no positional or indexed replace
API. It offers exactly two mutating operations, both relative to the
cursor: `insertText(_:)` and `deleteBackward()`. There is no "replace
characters 10 through 15" equivalent.

## Options Considered

1. **Trust that the keyboard's own typed text is still exactly what's
   before the cursor, with no verification.** Rejected — this silently
   deletes the wrong text the moment the user repositions the cursor, or
   the host app clears the field programmatically (most commonly: right
   after the user taps Send).
2. **Track everything the keyboard itself has typed since the last
   translation, and validate that tracking against the live document
   before every delete.** Chosen.

## Decision

`KeyboardEngine` accumulates `trackedText` as the user types, and exposes
`prepareTranslateRequest(documentContextBeforeInput:)` as the single entry
point for deciding whether a translate-and-replace is safe to perform.
This method is called twice in the actual flow: once at the moment
Translate is tapped, and again, synchronously, right before the delete/
insert actually happens once the translation comes back — the second call
is the authoritative one, since the system's `textDidChange` notification
(used as an early, soft signal to reset stale tracking sooner) isn't
guaranteed to fire for every host app; some WebView-backed text fields
don't fire it reliably.

Three refinements were needed to make that validation actually correct,
found after the first pass:

1. **`documentContextBeforeInput` isn't guaranteed to return the full
   preceding text.** Some host apps truncate it — to the current sentence,
   for example. A naive "tracked text must be a suffix of the context"
   check breaks the moment a message is longer than whatever window the
   host app returns. The comparison instead goes by whichever string is
   shorter: if the context is at least as long as what's tracked, tracked
   text must be a suffix of it (the normal case); if the context is
   shorter, the context itself must be a suffix of tracked text (the
   truncated-but-still-consistent case) — both are anchored at the cursor,
   so a shorter one should equal the tail of the longer one whenever
   tracking is genuinely valid.
2. **Once tracked text would exceed a length cap (500 characters),
   tracking is disabled outright** rather than sliding-window-truncated to
   the most recent N characters. Truncating would silently translate and
   replace only part of what the user actually typed — a worse, more
   confusing failure than clearly saying the message is too long.
3. **An empty context (`""`) is always treated as a mismatch** when
   tracked text is non-empty, checked ahead of the general shorter/longer
   rule above. `""` is a trivial suffix of every string, so without this
   carve-out the general rule would treat a freshly cleared field as
   perfectly "consistent." This is exactly what happens right after the
   user taps the host app's Send button — the single most common real
   sequence (translate, tap Send, start typing the next message) — and
   without the carve-out, the next message would get the already-sent
   English silently prepended to it.

**Why auto-send isn't possible:** there is no API for a keyboard extension
to invoke an arbitrary host app's own Send action. `UITextDocumentProxy`
only edits text; it has no notion of buttons or actions elsewhere in the
host app's UI. Auto-inserting `"\n"` as a stand-in for Send was considered
and rejected: `UIReturnKeyType.send` isn't universal across apps, and
unconditionally firing Return would insert unwanted newlines (or send
prematurely) in any app that uses Return for line breaks rather than
submission.

## Consequences

- The user always taps the host app's own Send button — an unavoidable
  manual step, not a missing feature.
- This is also the safer design from an App Store review standpoint: a
  keyboard extension silently taking an action on the user's behalf
  (submitting a message) without explicit confirmation is exactly the kind
  of behavior review guidelines are wary of; requiring an explicit tap
  avoids that concern entirely.
- One process note, not code: since Full Access plus off-device
  transmission of typed content is involved, the host app's App Store
  Connect "App Privacy" declaration will need to disclose that typed
  content is sent off-device for translation. A submission-time step,
  flagged here for later.
