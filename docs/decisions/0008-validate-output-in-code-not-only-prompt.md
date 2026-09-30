# 0008: Validate Model Output in Code, Not Only in the Prompt

## Context

`docs/decisions/0007` narrowed the prompt's rules to stop a specific
confusion (loanword-preservation being over-applied to whole sentences).
Re-running the eval set afterward showed the fix was partial: some
previously-broken cases now pass, but others -- mostly short, low-content
fragments and reactions ("hi, long time no see!", "movie tonight?", "lol
that's so funny") -- still come back completely untranslated. This looks
like a different root cause than 0007 addressed, and there's no strong
signal yet for which additional prompt wording would fix it without
risking new regressions elsewhere (0007 itself was a fix for a problem
introduced by an earlier, well-intentioned prompt addition).

## Options Considered

1. **Keep iterating on the prompt** -- add more rules, more few-shot
   examples, hope the next wording change closes the remaining gap.
   Each prior round of this (0005, 0006, 0007) fixed the specific cases
   it targeted but each also either introduced or failed to prevent a
   related failure mode. Diminishing, uncertain returns, and no way to
   *guarantee* a prompt change closes a gap short of re-running the eval
   set and hoping.
2. **Check the actual output in code**, independent of the prompt, and
   retry once with corrective feedback if the check fails.

## Decision

Chose option 2, without abandoning option 1 -- 0007's prompt fix stays,
this adds a second, independent layer on top of it. After calling the
model, `server.js` checks whether the output is unchanged from the input
(case/punctuation-insensitive) using `lib/outputGuard.js`'s `isUnchanged`.
If it's unchanged **and** the input doesn't look like something that's
genuinely supposed to stay unchanged (`isLikelyUntranslatable`: a
terminal command, a URL, code, or an emoji-only message), the request is
retried once, in the same conversation, showing the model its own
unchanged output and stating explicitly what was wrong with it. If the
retry is still unchanged, that response is returned anyway (better a
possibly-untranslated response than none), and the failure is logged
server-side (`console.warn`) so it's visible in the deploy logs rather
than silently swallowed.

`isLikelyUntranslatable` is a deliberately conservative heuristic (a
small set of command-starter words, a URL pattern, narrow code-punctuation
matching, and "no letters or digits at all" for emoji-only) — it doesn't
need to be exhaustive. A false negative (missing a real command/URL/code
case) just costs one unnecessary retry; a false positive (flagging
ordinary text as untranslatable) would suppress a retry that should have
happened, which is the worse failure to risk.

`isUnchanged` and `isLikelyUntranslatable` are pure functions in
`lib/outputGuard.js`, unit tested via `npm test` (Node's built-in test
runner -- no new dependency), independent of a running server or an API
key.

## Consequences

- This is a real safety net, not a full fix: it only catches the
  *unchanged-output* shape of the bug. A case where the model produces
  *some* Tanglish but drops meaning, or mixes English and Tanglish
  mid-sentence, isn't caught by this check at all -- `isUnchanged` only
  fires on an exact (normalized) match.
- Adds one extra API call, and therefore latency and cost, on exactly the
  requests that need it -- the common case (output already differs from
  input) is unaffected.
- Establishes a pattern worth reusing: prompt engineering shapes
  *probability* of correct behavior, but code can enforce a *guarantee*
  for at least the failure shapes it explicitly checks for. Future
  observed failure modes with a clear, checkable signature (not just "the
  translation quality was subtly off") are good candidates for the same
  treatment rather than another prompt-only fix.
