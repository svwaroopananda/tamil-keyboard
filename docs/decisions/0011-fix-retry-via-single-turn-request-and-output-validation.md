# 0011: Fix the Retry via a Fresh Single-Turn Request, Plus Output Validation

## Context

The output-guard retry (`docs/decisions/0008`) worked by sending a
multi-turn conversation: the original request, the model's own unchanged
output appended as an assistant turn, and a user turn asking it to "try
again." While finalizing the model comparison in `docs/decisions/0010`,
this surfaced a real bug: that conversational framing caused the model to
occasionally narrate its own self-correction instead of just returning
the translation -- observed once as a stray Tamil Unicode character
leaking into otherwise-Latin text (`"Rொmba cute"`), and separately as
literal `"Let me redo that properly:"` text prepended to the real answer.

## Options Considered

1. **Keep the multi-turn retry, add a stronger instruction against
   commentary.** Doesn't address what looks like the actual cause: the
   conversational framing itself seems to invite the model to treat the
   retry as "a conversation about my mistake" rather than "translate this
   text," which is the wrong framing no matter how firmly worded.
2. **Re-issue a fresh single-turn request** (the exact same original user
   message) with one extra system-prompt instruction, and validate the
   result before using it.

## Decision

Chose option 2. The retry (`server.js`) no longer carries any
conversation history -- it's structurally identical to the original
request, with `RETRY_SYSTEM_SUFFIX` appended to `SYSTEM_PROMPT` instead of
a prior turn. This removes the "this is a conversation, my previous
answer was wrong" framing entirely, rather than trying to instruct around
it.

Independently, since even a single-turn request could in principle still
produce commentary or malformed output, the retry's result is now
validated before use. `isValidTranslationOutput` (`lib/outputGuard.js`)
rejects two things: non-Latin-script characters (checked by Unicode
*script* property, not just "non-ASCII," so benign punctuation like smart
quotes or em dashes isn't false-flagged) and a short list of
meta-commentary patterns (`"let me"`, `"here is"`/`"here's"`,
`"translation:"`, `"redo"`, `"corrected version/output/translation"`). If
the retry's output fails validation, the **original** (still-unchanged-
English) output is returned instead, and a warning is logged -- a
known-safe fallback is better than shipping a known-broken one.

Response usage reporting was corrected alongside this: when a retry
happens, `/translate`'s reported token usage now sums both calls, since a
discarded retry still cost real tokens -- needed for `run-evals.js`'s
cost estimates to stay accurate.

## Consequences

- Directly fixes both observed failure modes; verified via unit tests in
  `lib/outputGuard.test.js` built from the actual bad output text (not
  hypothetical cases), and via a live re-run of the exact input that
  originally triggered it.
- The validator is pattern-based, not exhaustive -- a different malformed
  shape not matching these specific patterns could still slip through.
  It's a safety net for the failure modes actually observed, not a
  general output-quality checker (that remains the judge's job in eval
  runs, which production requests don't run).
- Accepted false-positive risk: a retry that happens to produce correct
  Tanglish containing, say, the word "redo" in a legitimate context would
  be wrongly rejected in favor of the original (worse) output. Judged
  acceptable since the patterns are drawn directly from observed real
  bugs, not speculative guesses, and the fallback (original output) is
  never worse than what shipped before this fix existed.
