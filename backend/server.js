// server.js
//
// A minimal Express server with one job: accept English text from the
// iOS keyboard extension, ask Claude to transliterate it into casual,
// WhatsApp-style Tamil written in English (Latin) script, and return it.
//
// Why a backend at all, instead of calling Claude directly from the app?
// The Claude API key is a secret. If it were embedded in the iOS app
// binary, anyone could extract it (apps are just zip files you can
// unpack) and rack up usage on your account. Routing through a server
// we control means the key only ever lives here, server-side.

require('dotenv').config(); // reads backend/.env and populates process.env

const express = require('express');
const Anthropic = require('@anthropic-ai/sdk');

const app = express();

// Express doesn't parse JSON request bodies by default. This middleware
// reads the raw request body, parses it as JSON, and attaches the result
// to req.body -- so our route handler can just read req.body.text.
app.use(express.json());

// The Anthropic client reads ANTHROPIC_API_KEY from process.env
// automatically, but we pass it explicitly here so it's obvious where
// it comes from and so the server fails fast (see check below) instead
// of failing confusingly on the first request.
const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey) {
  console.error(
    'Missing ANTHROPIC_API_KEY. Create backend/.env with:\nANTHROPIC_API_KEY=sk-ant-...'
  );
  process.exit(1);
}
const anthropic = new Anthropic({ apiKey });

// The model to call. Haiku is the fastest/cheapest Claude model, which
// matters here: this endpoint sits in the path of someone typing on a
// keyboard, so latency directly affects how usable the extension feels.
// If quality of the Tanglish output isn't good enough, swap this for a
// Sonnet model -- that's a one-line trade-off to discuss in an interview
// (latency/cost vs. quality).
const MODEL = 'claude-haiku-4-5-20251001';

// This system prompt is the actual "product logic" of the app. It's
// worth being deliberate about it: we want natural Tanglish (Tamil
// words, English alphabet, casual chat register), not formal Tamil
// script and not a stiff dictionary translation.
const SYSTEM_PROMPT = `You transliterate English text into casual, conversational Tamil, written using the English (Latin) alphabet -- the way Tamil speakers type Tamil in WhatsApp chats (sometimes called "Tanglish").

Rules:
- Output ONLY the Tanglish text. No explanations, no quotes, no Tamil script (no Unicode Tamil letters), no English translation alongside it.
- Match the casual, spoken register of chat messages, not formal/written Tamil.
- Preserve tone: if the input is a question, keep it a question; if it's short and casual, keep the output short and casual.
- If part of the input has no natural Tamil equivalent (e.g. brand names, English tech terms people commonly leave in English when texting), you may leave that part in English, as a real bilingual chatter would.`;

app.post('/translate', async (req, res) => {
  const { text } = req.body;

  // Basic input validation. Never trust a client-supplied body -- an
  // empty, missing, or wrong-typed field would otherwise reach the
  // Claude API call and fail there with a less clear error, or waste
  // an API call on garbage input.
  if (typeof text !== 'string' || text.trim().length === 0) {
    return res.status(400).json({ error: 'Request body must include a non-empty string "text" field.' });
  }

  try {
    const message = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 500,
      system: SYSTEM_PROMPT,
      messages: [{ role: 'user', content: text }],
    });

    // The SDK returns content as an array of blocks (it can mix text,
    // tool calls, etc.). We only asked for plain text, so we take the
    // first block's text.
    const tamil = message.content[0].text.trim();

    res.json({ tamil });
  } catch (err) {
    // Log the full error server-side for debugging, but don't leak
    // internal details (stack traces, API error bodies) to the client.
    console.error('Claude API error:', err);
    res.status(502).json({ error: 'Translation failed. Please try again.' });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Tamil transliteration backend listening on http://localhost:${PORT}`);
});
