# 0001: Extract TamilCore as a Shared Swift Package

## Context

Translation networking logic (building the `/translate` request, parsing
the response, error handling) originally lived entirely inside
`KeyboardViewController`, part of the `KeyboardExtension` target. The host
app (`TamilKeyboardApp`) currently has no networking of its own, but future
work — an App Intent, or translation UI in the host app itself — will need
the same logic.

A keyboard extension and its containing app are separate binaries that run
in separate processes. There is no way for one Xcode target to "borrow"
another target's source files at compile time by reference; code shared
between them has to live somewhere both can depend on.

## Options Considered

1. **Leave the logic in `KeyboardViewController` and copy-paste it** into
   any future call site. Fastest short-term, but guarantees drift: a fix or
   behavior change in one copy silently doesn't apply to the other.
2. **Put the shared logic in the host app target and have the extension
   depend on it.** Not viable — an app extension cannot depend on its
   containing app target in Xcode; the dependency only runs the other
   direction (app embeds extension, not the reverse).
3. **Extract a local Swift Package** that both targets declare a dependency
   on.

## Decision

Extract a local Swift Package, `TamilCore` (`ios/TamilCore/`), containing
`TranslationClient` and its supporting types (`TranslationError`,
`HTTPClient`). Both `TamilKeyboardApp` and `KeyboardExtension` depend on it,
wired via `packages:`/`dependencies:` entries in `ios/project.yml` and
resolved by XcodeGen. `TamilCore` has no UIKit dependency, so it stays
usable from any future context, including one that isn't a view controller
at all (e.g. an App Intent).

## Consequences

- One implementation, one set of tests. `swift test` runs the package's
  test suite directly, without needing Xcode or a simulator.
- Enforces a real separation between UI code (stays in each target) and
  translation/networking logic (lives in the package) — UI code can't
  reach for `URLSession` directly anymore without going through the shared
  client.
- Adds a moving part to the build: `ios/project.yml`'s `packages:` section
  and each target's `dependencies:` entry must be kept in sync, and
  `xcodegen generate` re-run after package changes.
- The package now needs its own versioning/compatibility discipline as it
  gains more than one consumer.
