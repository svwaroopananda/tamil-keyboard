# 0009: Configurable Translation Model, and a Held-Out Eval Set

## Context

`docs/decisions/0006` built the eval set specifically to enable a future
decision: does a larger model than Haiku actually translate better,
enough to justify its cost and latency for this feature? Answering that
requires running the same eval methodology against more than one model,
which the codebase didn't support -- `MODEL` in `server.js` was a fixed
constant.

There's a second problem with using the *tuning* eval set (`tanglish.json`)
for that comparison, though: its `expected`/`acceptable` values have been
iteratively corrected against Haiku's actual output over several rounds
(`docs/decisions/0006`, `0007`). Scoring a different model against
answers shaped by another model's output pattern risks understating a
model that phrases things differently-but-correctly, or overstating one
that happens to phrase things similarly to what got written down.

## Decision

**Configurable model.** `server.js` reads `MODEL` from
`process.env.TRANSLATION_MODEL`, defaulting to the existing Haiku model.
`backend/scripts/run-evals.js` reads the same environment variable for
its results-file label, so a saved run always records which model
actually produced it. This surfaced two real compatibility issues, fixed
alongside it: newer model families (Sonnet 5, Opus 5, Fable 5) reject the
`temperature` parameter outright (sampling parameters were removed in
favor of adaptive thinking), and don't guarantee the response's first
content block is text (it can lead with an internal reasoning block) --
both are now handled generically (`MODELS_WITHOUT_TEMPERATURE`,
`extractText()`) rather than assuming the one model family used so far.

**A held-out eval set** (`backend/evals/tanglish-holdout.json`, 10 cases)
covers the same weak-spot categories the tuning set does (short
fragments, reactions, greetings, one-line plans) but contains no input
that appears in `tanglish.json` or as a `SYSTEM_PROMPT` few-shot example
-- verified programmatically, not just by eye. It exists specifically to
be scored, never to be tuned against: if a prompt change is made to fix
something the holdout set reveals, that fix should be verified against a
*new* holdout case, not by re-running the same one until it passes.

**Cost and latency, measured, not assumed.** `server.js`'s response now
additionally includes token usage (additive, backward-compatible --
existing clients reading only `tamil` are unaffected). `run-evals.js`
measures wall-clock latency per request client-side and reports median
latency and an estimated cost per 1,000 messages (using
`docs/decisions/...` -- see the pricing table in `run-evals.js`, sourced
from the `claude-api` skill and re-checked against the current date since
Claude Sonnet 5 had a time-limited introductory rate).

## Consequences

- The exact/variant match score is expected to be a *worse* fit for a
  different model than for the one the eval set was tuned against --
  this is by design, not a bug, and is exactly why the judge score
  (which doesn't depend on `expected` at all) is reported alongside it
  rather than replacing it. The holdout set makes this more visible: its
  exact-match rate is near zero for any model, since its `expected`
  values were drafted once and never iterated against real output the
  way the tuning set's were.
- `PROMPT_VERSION` and `TRANSLATION_MODEL` are both manually-maintained
  labels, not derived automatically -- a saved results file is only as
  trustworthy as remembering to keep them in sync with what actually
  changed.
- This does not itself decide whether to switch models -- it only builds
  the tooling and produces one comparison data point. That decision and
  its result belong in a follow-up ADR once the comparison has been
  reviewed, not folded into this one.
