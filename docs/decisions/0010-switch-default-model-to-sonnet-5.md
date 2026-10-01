# 0010: Switch Default Translation Model to Sonnet 5

## Context

`docs/decisions/0009` built the tooling to compare translation models;
this records the actual decision made from running it.

Two bugs in the eval tooling itself were found and fixed before trusting
the numbers below. First: the judge model (`claude-sonnet-5`) spends a
variable amount of its output budget on internal reasoning before its
final PASS/FAIL line; raising `max_tokens` (100 → 300) only made it less
frequent, not gone -- some judge calls still hit `max_tokens` with zero
text emitted, undercounting both models' judged totals (Haiku's eval run
graded 18/20, Sonnet's holdout run graded 8/10). Fixed by passing
`thinking: { type: 'disabled' }` on the judge call -- a one-line verdict
doesn't need reasoning, and removing the variability is more robust than
guessing a higher cap. Second: `server.js` had no way to report whether
the output-guard retry (`docs/decisions/0008`) fired on a given request;
added a `retried` boolean to the response so this is now directly
observable rather than inferred.

## Numbers (all cases graded; re-run after both fixes)

**Eval set** (`backend/evals/tanglish.json`, 20 scored cases):

| | Haiku 4.5 | Sonnet 5 |
|---|---|---|
| Judge pass rate | 10/18 (56%) -- 2 cases ungraded by the since-fixed judge bug | 15/20 (75%) |
| Exact/variant match | 7/20 | 4/20 |
| Median latency | 723ms | 1,533ms |
| p95 latency | not measured | 4,885ms |
| Est. cost / 1,000 msgs | $1.10 | $1.48 (this run; Sonnet has no fixed `temperature`, so token spend on adaptive thinking varies run to run -- an earlier run measured $4.52, see Consequences) |

**Holdout set** (`backend/evals/tanglish-holdout.json`, 10 cases, never
tuned against):

| | Haiku 4.5 | Sonnet 5 |
|---|---|---|
| Judge pass rate | 8/10 (80%) | 5/10 (50%) |
| Median latency | 737ms | 1,794ms |
| p95 latency | not measured | 2,663ms |

**Output guard** (`docs/decisions/0008`): confirmed active on the Sonnet
runs via the new `retried` field -- fired on 2/25 eval-set requests
(`good morning!`, `happy birthday!`) and 2/10 holdout requests (`omg no
way`, `so cute`).

## The holdout result is not treated as contradicting the decision

Sonnet scoring *worse* than Haiku on the holdout set (50% vs 80%) is the
opposite of the eval-set result, and worth stating plainly rather than
explaining away. Looking at the five holdout failures: two are the judge
being quite strict about individual English words left in a sentence that
also found a specific, narrow bug (`"so cute"` → `"Rொmba cute\n\nLet me
redo that properly:\n\nRomba cute"` -- a stray non-Latin character in
"Rொmba" and leaked self-correction commentary, both from the retry path,
not the original translation path), and two are the judge marking a
close-but-not-exact paraphrase as a fail while its own stated reason
calls the gap "borderline" or "minor." At 10 cases, one or two borderline
judge calls swing the rate by 10-20 points -- this is exactly why the
decision below weights the eval set's 20-case result and the consistent
direction across both sets' *quality signal*, not the holdout's absolute
number in isolation. It's also exactly why the holdout set needs to grow
(see Consequences) rather than being trusted at its current size.

## Decision

Switch the default `MODEL` in `server.js` from Haiku 4.5 to Sonnet 5.
`TRANSLATION_MODEL` remains the override, unchanged from 0009. Rationale:
the eval set (the larger, more-tuned sample) shows a 19-point judge-pass
gap in Sonnet's favor, consistent with the earlier partial-data run that
prompted this comparison; the holdout set's reversal is judged more
likely to be judge-rubric strictness and small-sample noise than a real
quality regression, based on reading its actual failure reasons rather
than just its number. The accepted trade-off: roughly 2.1x median latency
and comparable-to-somewhat-higher cost (cost estimates vary run to run
for Sonnet specifically, since it has no fixed `temperature`) for a
meaningfully higher judge-graded pass rate on the larger sample.

## Consequences

- **The retry-path quality bug found during this comparison is a real,
  separate issue, not fixed here.** The output guard (0008) retries by
  showing the model its own unchanged output and asking it to try
  again -- on at least one observed case (`"so cute"`), that retry
  produced a malformed response (a stray Tamil-script character mixed
  into a Latin word, plus visible "let me redo that" self-correction
  text) that would have been inserted into the user's message as-is.
  Flagged for follow-up, not addressed in this ADR.
- **The holdout set (10 cases) is too small to reliably separate two
  models** once the gap isn't large and obvious -- this decision leaned
  on the eval set's larger sample and on reading *why* the judge failed
  holdout cases, not just the number. The holdout set should grow over
  time (more cases per existing category, and new weak-spot categories as
  they're found) so a future model comparison has a sample size that
  doesn't flip on one or two borderline judge calls.
- Sonnet 5's lack of a fixed `temperature` (see `docs/decisions/0009`'s
  `MODELS_WITHOUT_TEMPERATURE`) means both its output and its token spend
  (and therefore measured cost) vary run to run more than Haiku's did --
  cost/latency numbers here are a snapshot, not a guarantee repeatable to
  the cent.
- Everyday use is now ~1.5-2s per translation (p95 ~4.9s on the eval set)
  instead of Haiku's sub-second response -- worth keeping an eye on for
  the keyboard extension's UX (the existing spinner-while-translating
  state in `KeyboardViewController` already accounts for a wait, but this
  is a materially longer one than it was tuned against).

## Addendum: the final, fair decision

**The original decision above was based on incompletely graded results**
(the judge-null bug meant Haiku's eval run was scored on 18 cases, not
20) **and on two inconsistencies between how each model was tested**: the
judge rubric at the time penalized common English greetings ("good
morning", "happy birthday") as FAIL even though the product prompt itself
correctly keeps them in English, and the output-guard retry's own bug
(`docs/decisions/0011`) meant a model's score could be dragged down by a
malformed retry response that had nothing to do with its underlying
translation quality. Both were fixed (`docs/decisions/0011`; the judge
rubric's criterion 2 now has an explicit exception for common English
greetings/expressions) before this final comparison, so this addendum
is the one to trust, not the numbers above it.

**Decision rule, set before running this round:** Sonnet 5 stays the
default only if its combined judge pass rate (eval set + holdout set
pooled) is at least 10 percentage points higher than Haiku's. Otherwise,
revert to Haiku, since it is 2-3x faster with a much shorter p95.

**Method:** both models run 3 times each against both the eval set (20
cases) and the holdout set (10 cases) -- 12 runs total, 90 scored
judgments per model. "Mean" rates below are the average of each set's 3
per-run rates; "combined" pools every judged case across all 6 runs (90)
for that model into one ratio, which is what the decision rule is
evaluated against. Latency and cost are pooled across all 105
requests-per-model (90 scored + 15 in-prompt) in each model's 6 runs.

One bug caught while aggregating, worth disclosing: the first aggregation
pass mislabeled the Sonnet runs' saved model name as Haiku's, because
`TRANSLATION_MODEL` was exported for the server process that produced
them but not for the separate `run-evals.js` invocations reading that
same env var for its own label -- the actual HTTP requests went to the
correct server throughout (confirmed by each run's latency distribution
matching that model's behavior everywhere else in this project, ~660ms
median for the Haiku group vs ~1.5s for the Sonnet group, consistent
before and after this round), but the mislabel meant the first cost
calculation priced Sonnet's token usage at Haiku's rate. Recomputed with
the correct per-model pricing before trusting any of the numbers below.

| | Haiku 4.5 | Sonnet 5 |
|---|---|---|
| Eval judge pass rate (mean of 3 runs) | 45.0% | 76.7% |
| Holdout judge pass rate (mean of 3 runs) | 46.7% | 76.7% |
| **Combined judge pass rate (pooled, 90 judgments)** | **45.6% (41/90)** | **76.7% (69/90)** |
| Median latency (pooled, n=105) | 663ms | 1,581ms |
| p95 latency (pooled) | 1,351ms | 3,494ms |
| Est. cost / 1,000 messages | $1.30 | $4.92 |
| Output guard retries | 20/105 | 15/105 |

**Rule applied:** 76.7% − 45.6% = **+31.1 percentage points**, well
above the 10-point bar.

**Outcome: Sonnet 5 stays the default.** The gap is large enough, and
consistent enough across both sets this time (76.7% on eval, 76.7% on
holdout -- no reversal, unlike the earlier incomplete comparison), that
it isn't close to the threshold either way. The accepted trade-off is now
precisely measured rather than approximate: roughly 2.4x median latency,
2.6x p95 latency, and 3.8x cost per 1,000 messages, for 31 points of
judge-graded quality. `server.js`'s default (`claude-sonnet-5`) and the
`TRANSLATION_MODEL` override both remain unchanged by this addendum.
