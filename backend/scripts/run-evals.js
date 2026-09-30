// scripts/run-evals.js
//
// Runs every entry in evals/tanglish.json against the live backend and
// prints input/expected/actual side by side. Flags outputs that look
// like a reply instead of a translation (e.g. a question in the input
// that isn't a question in the output) -- this is a heuristic, not
// proof; it's meant to catch obvious regressions of the "how are you?"
// -> "I'm fine" bug, not to judge translation quality.
//
// Only entries marked "reviewed": true count toward the match score --
// the rest have draft expected values that haven't been corrected by a
// Tamil speaker yet, so scoring against them would be meaningless.

const fs = require('fs');
const path = require('path');

const BASE_URL = process.env.BACKEND_URL || 'http://localhost:3000';
const EVALS_PATH = path.join(__dirname, '..', 'evals', 'tanglish.json');

const QUESTION_STARTERS = [
  'did', 'do', 'does', 'what', 'where', 'when', 'why', 'how',
  'can', 'could', 'will', 'would', 'are', 'is', 'have', 'has',
];

function normalize(text) {
  return text
    .toLowerCase()
    .replace(/[?.!,"']/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function looksLikeQuestion(text) {
  const trimmed = text.trim();
  if (trimmed.endsWith('?')) return true;
  const firstWord = (trimmed.split(/\s+/)[0] || '').toLowerCase().replace(/[^a-z]/g, '');
  return QUESTION_STARTERS.includes(firstWord);
}

async function translate(text) {
  const response = await fetch(`${BASE_URL}/translate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
  });
  const body = await response.json();
  return { status: response.status, body };
}

async function main() {
  const cases = JSON.parse(fs.readFileSync(EVALS_PATH, 'utf8'));
  console.log(`Running ${cases.length} evals against ${BASE_URL}/translate\n`);

  let matchCount = 0;
  let reviewedCount = 0;
  let replyFlagCount = 0;

  for (const testCase of cases) {
    const { input, expected, category, reviewed } = testCase;
    const { status, body } = await translate(input);
    const actual = status === 200 ? body.tamil : `[HTTP ${status}] ${body.error}`;

    const looksLikeReply = status === 200 && looksLikeQuestion(input) && !looksLikeQuestion(actual);
    if (looksLikeReply) replyFlagCount++;

    let matched = null;
    if (reviewed) {
      reviewedCount++;
      matched = status === 200 && normalize(actual) === normalize(expected);
      if (matched) matchCount++;
    }

    const label = reviewed ? (matched ? 'MATCH' : 'MISMATCH') : 'unreviewed';
    console.log(`[${category}] ${label}`);
    console.log(`  input:    ${input}`);
    console.log(`  expected: ${expected}`);
    console.log(`  actual:   ${actual}`);
    if (looksLikeReply) {
      console.log('  ⚠ looks like a REPLY, not a translation -- input is a question but output isn\'t');
    }
    console.log('');
  }

  console.log('---');
  console.log(`${matchCount}/${reviewedCount} reviewed cases matched`);
  console.log(`${replyFlagCount}/${cases.length} outputs flagged as possibly reply-shaped`);
}

main();
