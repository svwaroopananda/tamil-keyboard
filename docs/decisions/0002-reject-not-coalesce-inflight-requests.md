# 0002: Reject Duplicate In-Flight Requests Instead of Coalescing Them

## Context

The keyboard's Translate button can be tapped again before a prior request
finishes. `TranslationClient` needed a way to prevent a second outgoing
request while one is already running, tracked safely inside an `actor`
(chosen specifically so this state can't be raced by two overlapping
calls).

## Options Considered

1. **No guard in the shared client** — rely on the UI layer (disabling the
   button while a request is in flight) as the only defense. Works for the
   one caller that remembers to do it, but isn't a guarantee the package
   itself provides to any future caller.
2. **Coalesce**: store the in-flight network call as a `Task<String,
   Error>`, and have a second call `await` that same task's `.value`,
   returning the first call's result to both callers.
3. **Reject**: store a `Bool` flag, set synchronously before the first
   `await` and cleared in a `defer`; a second call arriving while it's set
   throws immediately instead of touching the network.

## Decision

We implemented option 2 first. Design review caught a real bug in it, not
just a style concern: Swift actors are only exclusive *between* suspension
points, not across one. The coalescing version set `isTranslating`-style
state and then `await`ed the network call — but a second call arriving
during that `await` would see the stored task and `await` its `.value`
too. If the second call was for *different* input text, it would silently
receive the *first* call's translation instead of its own — wrong output,
no error, nothing to indicate anything had gone wrong. That's worse than no
guard at all: a caller has no way to know the answer it received doesn't
belong to the request it made.

We replaced it with option 3. The flag is checked and set entirely within
the synchronous prefix of `translate(_:)` — before the first `await` — and
cleared in a `defer`. Because the actor guarantees exclusivity for that
whole synchronous stretch, a second call can never observe the flag as
`false` while a request is genuinely in flight. A rejected call throws
`TranslationError.requestInFlight` rather than reusing another call's
in-flight work.

## Consequences

- Correct by construction: a caller either gets its own translation or a
  clear "one is already running" error — never another call's answer.
- No unstructured `Task` is created inside the actor. `translate(_:)`
  `await`s `performRequest(_:)` directly, so the calling `Task`'s own
  cancellation propagates straight through, rather than being decoupled
  from an internally-spawned task that isn't tied to the caller's
  lifetime.
- A second, overlapping call now has to handle `requestInFlight` as a
  normal outcome. In the keyboard, this surfaces as a short "Still
  translating, one sec…" message rather than a scary error — a deliberate,
  friendlier alternative to silently discarding the tap.
