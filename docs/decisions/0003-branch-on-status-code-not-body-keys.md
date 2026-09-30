# 0003: Branch on HTTP Status Code, Not Response Body Keys

## Context

The original inline networking code in `KeyboardViewController` inspected
the JSON response body for a `"tamil"` key (success) or an `"error"` key
(failure) to decide the outcome, regardless of the HTTP status code
returned. The backend (`backend/server.js`) actually communicates outcome
primarily through status code: `200` with `{"tamil": "..."}` on success,
`400` with `{"error": "..."}` for invalid input, `502` with `{"error":
"..."}` when the upstream Claude API call fails. Status code and body shape
are not independent in this contract — a 200 never lacks `tamil`, and a
non-200 never has it.

## Options Considered

1. **Keep inspecting body keys only**, as the original code did, ignoring
   the status code entirely.
2. **Branch on HTTP status code first**, and only parse the body according
   to what that status code implies.

## Decision

`TranslationClient` checks `response.statusCode` first. Any non-200 status
throws `TranslationError.unexpectedStatusCode(code, message:)`, attempting
to read an `"error"` field from the body for a human-readable message, but
not depending on it being present. Only a `200` status attempts to parse
`{"tamil": "..."}`; if that key is missing, empty, or the body isn't valid
JSON at all, it's `TranslationError.malformedResponse`.

## Consequences

- Matches how the backend's contract is actually documented, and how most
  HTTP APIs communicate outcome: status code is the primary signal, the
  body is supplementary detail.
- Distinguishes two previously-conflated failure modes that used to fall
  into the same "no `tamil` key found" path: a well-formed error response
  from the server (`unexpectedStatusCode`) versus a genuinely malformed
  200 response — an actual bug or contract drift (`malformedResponse`).
  These now produce different, more accurate error cases.
- If the backend ever returned a non-200 status with a 200-shaped body (or
  vice versa) due to a bug, `TranslationClient` trusts the status code over
  the body. This is the intended, correct behavior here, not a risk —
  status code is the contractual source of truth for this API.
