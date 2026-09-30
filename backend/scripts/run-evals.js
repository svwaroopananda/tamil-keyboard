// scripts/run-evals.js
//
// Runs every entry in evals/tanglish.json against the live backend,
// grades each scored case two ways -- exact/variant string match, and a
// separate "LLM as judge" call to a larger model grading against a
// rubric -- and writes the full results to evals/results/<timestamp>.md
// and .json. Only the two summary scores and the saved file path are
// printed to the console; earlier per-case console output got garbled in
// a narrow terminal, so the full detail now lives in the saved files
// instead, which can be opened in an editor.
//
// Entries marked "reviewed": true count toward both scores. Entries
// marked "inPrompt": true are excluded from both scores even if
// reviewed -- they appear verbatim as few-shot examples in
// backend/server.js's SYSTEM_PROMPT, so scoring them would measure
// memorization, not generalization. They're still run and saved to the
// results file, labeled, for visibility.

const fs = require('fs');
const path = require('path');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const Anthropic = require('@anthropic-ai/sdk');

const BASE_URL = process.env.BACKEND_URL || 'http://localhost:3000';
const EVALS_PATH = path.join(__dirname, '..', 'evals', 'tanglish.json');
const RESULTS_DIR = path.join(__dirname, '..', 'evals', 'results');

// Kept as labels only -- run-evals.js doesn't call Claude to translate
// (it hits the running backend over HTTP), so this must be updated by
// hand if backend/server.js's MODEL constant changes.
const TRANSLATION_MODEL = 'claude-haiku-4-5-20251001';
// Bump this whenever SYSTEM_PROMPT changes meaningfully, so a saved
// results file records which prompt version produced it.
const PROMPT_VERSION = 'v4-narrow-english-passthrough';
// Deliberately a larger model than the one being graded -- a grader
// shouldn't share the translator's blind spots.
const JUDGE_MODEL = 'claude-sonnet-5';

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

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

const JUDGE_RUBRIC = `You are grading a Tamil-transliteration (Tanglish) system. Judge whether OUTPUT meets every one of these criteria, given the ORIGINAL English chat message it was supposed to transliterate:

1. Meaning preserved -- OUTPUT conveys the same meaning as ORIGINAL.
2. Written in Tanglish (Tamil words transliterated into English/Latin letters), not left in plain English.
3. Casual register by default -- respectful register only if ORIGINAL is addressed to someone like amma, appa, sir, madam, aunty, or uncle.
4. OUTPUT is a rewrite of the sender's message, not a reply or answer to it -- a question in ORIGINAL must still be a question in OUTPUT.

Respond with exactly one line: "PASS: <one-sentence reason>" or "FAIL: <one-sentence reason>". Nothing else.`;

async function judgeCase(input, actual) {
  try {
    const message = await anthropic.messages.create({
      model: JUDGE_MODEL,
      // Generous headroom, not just for the one-line answer -- this model
      // can spend part of its output budget on internal reasoning before
      // the final text, and too tight a cap hits max_tokens before any
      // PASS/FAIL line is emitted at all.
      max_tokens: 300,
      system: JUDGE_RUBRIC,
      messages: [{ role: 'user', content: `ORIGINAL: ${input}\nOUTPUT: ${actual}` }],
    });

    const textBlock = message.content.find((block) => block.type === 'text');
    if (!textBlock) {
      return { verdict: null, reason: `judge returned no text block (stop_reason: ${message.stop_reason})` };
    }

    const responseText = textBlock.text.trim();
    const match = responseText.match(/^(PASS|FAIL):\s*(.*)$/is);
    if (match) {
      return { verdict: match[1].toUpperCase(), reason: match[2].trim() };
    }
    return { verdict: null, reason: `unparseable judge response: ${responseText}` };
  } catch (err) {
    // A transient judge failure shouldn't crash a 40-call run -- record
    // it as ungraded (not a FAIL verdict, which would misrepresent the
    // translation itself as having failed) and keep going.
    return { verdict: null, reason: `judge request failed: ${err.message}` };
  }
}

function renderMarkdown({ timestamp, matchRateStr, judgeRateStr, scored, inPromptEntries }) {
  const lines = [];
  lines.push(`# Eval run: ${timestamp}`, '');
  lines.push(`- Translation model: ${TRANSLATION_MODEL}`);
  lines.push(`- Judge model: ${JUDGE_MODEL}`);
  lines.push(`- Prompt version: ${PROMPT_VERSION}`);
  lines.push(`- Exact/variant match rate: ${matchRateStr}`);
  lines.push(`- Judge pass rate: ${judgeRateStr}`, '');

  lines.push('## Scored cases', '');
  lines.push('| # | Category | Input | Expected | Acceptable | Actual | Match | Judge | Judge reason |');
  lines.push('|---|---|---|---|---|---|---|---|---|');
  scored.forEach((r, i) => {
    lines.push(
      `| ${i + 1} | ${r.category} | ${r.input} | ${r.expected} | ${(r.acceptable || []).join('; ')} | ${r.actual} | ${r.matched ? 'MATCH' : 'MISMATCH'} | ${r.judgeVerdict || ''} | ${r.judgeReason || ''} |`
    );
  });

  lines.push('', '## In-prompt examples (excluded from scoring)', '');
  lines.push('| Input | Expected | Actual |');
  lines.push('|---|---|---|');
  inPromptEntries.forEach((r) => {
    lines.push(`| ${r.input} | ${r.expected} | ${r.actual} |`);
  });

  return lines.join('\n') + '\n';
}

async function main() {
  const cases = JSON.parse(fs.readFileSync(EVALS_PATH, 'utf8'));

  const results = [];

  for (const testCase of cases) {
    const { input, expected, category, reviewed, inPrompt, acceptable } = testCase;
    const { status, body } = await translate(input);
    const actual = status === 200 ? body.tamil : `[HTTP ${status}] ${body.error}`;
    const looksLikeReply = status === 200 && looksLikeQuestion(input) && !looksLikeQuestion(actual);

    const isScored = Boolean(reviewed) && !inPrompt;
    let matched = null;
    if (isScored) {
      const candidates = [expected, ...(acceptable || [])];
      matched = status === 200 && candidates.some((candidate) => normalize(actual) === normalize(candidate));
    }

    let judgeVerdict = null;
    let judgeReason = null;
    if (isScored && status === 200) {
      const judged = await judgeCase(input, actual);
      judgeVerdict = judged.verdict;
      judgeReason = judged.reason;
    }

    results.push({
      input, category, expected, acceptable: acceptable || [], actual, status,
      inPrompt: Boolean(inPrompt), scored: isScored, matched, judgeVerdict, judgeReason, looksLikeReply,
    });
  }

  const scored = results.filter((r) => r.scored);
  const inPromptEntries = results.filter((r) => r.inPrompt);

  const matchCount = scored.filter((r) => r.matched).length;
  const judgedResults = scored.filter((r) => r.judgeVerdict !== null);
  const judgePassCount = judgedResults.filter((r) => r.judgeVerdict === 'PASS').length;

  const matchRateStr = `${matchCount}/${scored.length}`;
  const judgeRateStr = `${judgePassCount}/${judgedResults.length}`;

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  fs.mkdirSync(RESULTS_DIR, { recursive: true });
  const mdPath = path.join(RESULTS_DIR, `${timestamp}.md`);
  const jsonPath = path.join(RESULTS_DIR, `${timestamp}.json`);

  fs.writeFileSync(
    jsonPath,
    JSON.stringify(
      {
        timestamp,
        translationModel: TRANSLATION_MODEL,
        judgeModel: JUDGE_MODEL,
        promptVersion: PROMPT_VERSION,
        matchRate: { matched: matchCount, total: scored.length },
        judgePassRate: { passed: judgePassCount, total: judgedResults.length },
        cases: results,
      },
      null,
      2
    )
  );

  fs.writeFileSync(mdPath, renderMarkdown({ timestamp, matchRateStr, judgeRateStr, scored, inPromptEntries }));

  console.log(`Exact/variant match rate: ${matchRateStr}`);
  console.log(`Judge pass rate: ${judgeRateStr}`);
  console.log(`Full results: ${path.relative(process.cwd(), mdPath)}`);
}

main();
