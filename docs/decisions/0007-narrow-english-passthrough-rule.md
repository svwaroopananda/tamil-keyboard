# 0007: Narrow the "Leave in English" Rule to Loanwords, Not Whole Sentences

## Context

Running the eval set (`docs/decisions/0006`) surfaced a bug the earlier
manual spot-checks hadn't caught: several ordinary casual messages came
back completely untranslated, in plain English -- `"movie tonight?"` came
back as `"Movie tonight?"`, `"so sorry for the trouble"` came back
unchanged, `"lol that's so funny"` came back unchanged.

`SYSTEM_PROMPT` had two separate rules that were getting blended by the
model into one over-broad behavior:

1. Keep individual loanwords Tamil speakers normally leave in English
   when texting (hey, macha, bro, ok, sorry, thanks, names).
2. Leave genuinely untranslatable *content* unchanged (terminal commands,
   URLs, code).

Both rules mention "leave in English," and nothing in the prompt stated
explicitly that rule 1 applies to individual words *within* a sentence
while rule 2 applies to *entire inputs* that aren't chat messages at all.
The model appears to have generalized: "this message contains an English
loanword (sorry, movie, lol) → treat the whole thing like rule 2 and leave
it unchanged."

## Options Considered

1. **Remove the loanword-preservation rule entirely**, transliterating
   every word including "hey," "bro," "ok." Rejected — that produces
   stiff, unnatural Tanglish; real Tamil texting keeps these words in
   English, and losing that was the reason the rule existed in the first
   place (see the original prompt in `docs/decisions/0005`'s context).
2. **State explicitly that loanword-preservation is word-level, not
   sentence-level**, and restrict "leave completely unchanged" to a
   narrow, explicit list of non-chat-message content types. Add a
   few-shot example specifically demonstrating a short fragment being
   translated (short inputs were disproportionately represented among the
   failures).

## Decision

Chose option 2. `SYSTEM_PROMPT`'s two relevant rules are now:

- Loanwords stay in English *in place*, with everything else in the
  sentence around them transliterated -- explicitly stated as "a message
  containing some English words is not the same as an untranslatable
  message."
- The unchanged-passthrough rule is narrowed to five explicit categories:
  terminal/shell commands, URLs, code, file paths, and emoji-only
  messages. "English technical terms" was removed from this list
  entirely -- that concept now only exists at the loanword level, not as
  a reason to leave a whole message unchanged.

Added one new few-shot example (`"coming?"` → `"Varra?"`) specifically
because short fragments were where the bug showed up most -- a one- or
two-word question is a stronger test of "does the model still transliterate
under sentence pressure" than a full sentence is. Deliberately not drawn
from the eval set, to avoid the eval set overlapping with the prompt's own
training examples (see `docs/decisions/0006` on why `inPrompt` cases are
excluded from scoring).

## Consequences

- This is the kind of bug that's very hard to catch from a handful of
  manual `curl` checks — it only showed up once the eval set forced
  running a broad, varied batch of ordinary sentences through the prompt
  at once. Reinforces the eval set's value beyond just tracking the
  headline "reply vs. translate" bug it was originally built for.
- The loanword list (hey, macha, bro, ok, sorry, thanks, movie, meeting)
  is still an incomplete, hand-picked set — a word not on it may still get
  transliterated when a real user would expect it left in English. This
  is a known, accepted limitation of prompt-based rules rather than a
  proper lexicon; revisit if the eval set surfaces a pattern here.
