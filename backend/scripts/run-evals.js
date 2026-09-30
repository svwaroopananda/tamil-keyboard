// scripts/run-evals.js
//
// Runs every entry in an eval file (default evals/tanglish.json; pass
// --file evals/tanglish-holdout.json for the holdout set) against the
// live backend, grades each scored case two ways -- exact/variant string
// match, and a separate "LLM as judge" call to a larger model grading
// against a rubric -- and writes the full results to
// evals/results/<timestamp>.md and .json. Only the summary scores and the
// saved file path are printed to the console; earlier per-case console
// output got garbled in a narrow terminal, so the full detail now lives
// in the saved files instead, which can be opened in an editor.
//
// Entries marked "reviewed": true count toward both scores. Entries
// marked "inPrompt": true are excluded from both scores even if
// reviewed -- they appear verbatim as few-shot examples in
// backend/server.js's SYSTEM_PROMPT, so scoring them would measure
// memorization, not generalization. They're still run and saved to the
// results file, labeled, for visibility.
//
// The translation model is read from TRANSLATION_MODEL the same way
// server.js reads it, so the label in the results file always matches
// whatever the running backend is actually using -- run this against a
// server started with TRANSLATION_MODEL=claude-sonnet-5 to eval that
// model instead of the default.

const fs = require('fs');
const path = require('path');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const Anthropic = require('@anthropic-ai/sdk');

const BASE_URL = process.env.BACKEND_URL || 'http://localhost:3000';
const RESULTS_DIR = path.join(__dirname, '..', 'evals', 'results');

const fileArgIndex = process.argv.indexOf('--file');
const EVALS_PATH =
  fileArgIndex !== -1 && process.argv[fileArgIndex + 1]
    ? path.resolve(process.argv[fileArgIndex + 1])
    : path.join(__dirname, '..', 'evals', 'tanglish.json');

// Must match server.js's own resolution exactly, or the label in the
// results file would misrepresent which model actually produced them.
const TRANSLATION_MODEL = process.env.TRANSLATION_MODEL || 'claude-haiku-4-5-20251001';
// Bump this whenever SYSTEM_PROMPT changes meaningfully, so a saved
// results file records which prompt version produced it.
const PROMPT_VERSION = 'v5-output-guard-retry';
// Deliberately a larger model than the one being graded -- a grader
// shouldn't share the translator's blind spots.
const JUDGE_MODEL = 'claude-sonnet-5';

// $ per 1M tokens. Source: claude-api skill, cached 2026-06-24, checked
// against today's date -- Sonnet 5's intro rate ($2/$10) expired
// 2026-08-31, so the standard rate applies. Update if pricing changes.
const PRICING_PER_MILLION_TOKENS = {
  'claude-haiku-4-5-20251001': { input: 1.0, output: 5.0 },
  'claude-haiku-4-5': { input: 1.0, output: 5.0 },
  'claude-sonnet-5': { input: 3.0, output: 15.0 },
};

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

function median(numbers) {
  if (numbers.length === 0) return null;
  const sorted = [...numbers].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
}

function estimateCostPer1000(usages) {
  const pricing = PRICING_PER_MILLION_TOKENS[TRANSLATION_MODEL];
  if (!pricing || usages.length === 0) return null;
  const avgInput = usages.reduce((sum, u) => sum + u.inputTokens, 0) / usages.length;
  const avgOutput = usages.reduce((sum, u) => sum + u.outputTokens, 0) / usages.length;
  const costPerMessage = (avgInput * pricing.input + avgOutput * pricing.output) / 1_000_000;
  return costPerMessage * 1000;
}

async function translate(text) {
  const startedAt = Date.now();
  const response = await fetch(`${BASE_URL}/translate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
  });
  const latencyMs = Date.now() - startedAt;
  const body = await response.json();
  return { status: response.status, body, latencyMs };
}

// Tightened after the first version of this rubric let some questionable
// output through: Hindi loanwords (e.g. "kal" for tomorrow, common in
// North Indian Hindi-Urdu but not Tamil) were passing as if they were
// valid Tanglish, and "close enough" meaning was being accepted as PASS.
const JUDGE_RUBRIC = `You are grading a Tamil-transliteration (Tanglish) system. Judge whether OUTPUT meets every one of these criteria, given the ORIGINAL English chat message it was supposed to transliterate:

1. Meaning preserved -- OUTPUT conveys the same meaning as ORIGINAL, closely. Minor omissions or additions of meaning are a FAIL, not just wildly wrong meaning.
2. Written in Tanglish using Tamil vocabulary specifically, not left in plain English. Loanwords from other Indian languages (e.g. Hindi "kal" for tomorrow, "accha" for good/ok) are NOT Tanglish and are a FAIL, even though they might appear in casual Indian-English texting generally -- this system transliterates into Tamil, not a generic Hindi-English mix.
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
    // A transient judge failure shouldn't crash a multi-call run -- record
    // it as ungraded (not a FAIL verdict, which would misrepresent the
    // translation itself as having failed) and keep going.
    return { verdict: null, reason: `judge request failed: ${err.message}` };
  }
}

function renderMarkdown({ timestamp, matchRateStr, judgeRateStr, medianLatencyMs, costPer1000, scored, inPromptEntries, disagreements }) {
  const lines = [];
  lines.push(`# Eval run: ${timestamp}`, '');
  lines.push(`- Eval file: ${path.relative(process.cwd(), EVALS_PATH)}`);
  lines.push(`- Translation model: ${TRANSLATION_MODEL}`);
  lines.push(`- Judge model: ${JUDGE_MODEL}`);
  lines.push(`- Prompt version: ${PROMPT_VERSION}`);
  lines.push(`- Exact/variant match rate: ${matchRateStr}`);
  lines.push(`- Judge pass rate: ${judgeRateStr}`);
  lines.push(`- Median latency: ${medianLatencyMs !== null ? `${medianLatencyMs}ms` : 'n/a'}`);
  lines.push(`- Estimated cost per 1,000 messages: ${costPer1000 !== null ? `$${costPer1000.toFixed(3)}` : 'n/a'}`, '');

  lines.push('## Scored cases', '');
  lines.push('| # | Category | Input | Expected | Acceptable | Actual | Match | Judge | Judge reason |');
  lines.push('|---|---|---|---|---|---|---|---|---|');
  scored.forEach((r, i) => {
    lines.push(
      `| ${i + 1} | ${r.category} | ${r.input} | ${r.expected} | ${(r.acceptable || []).join('; ')} | ${r.actual} | ${r.matched ? 'MATCH' : 'MISMATCH'} | ${r.judgeVerdict || ''} | ${r.judgeReason || ''} |`
    );
  });

  lines.push('', '## Judge PASS but exact/variant match FAIL (spot-check these)', '');
  if (disagreements.length === 0) {
    lines.push('None.');
  } else {
    lines.push('| Input | Expected | Acceptable | Actual | Judge reason |');
    lines.push('|---|---|---|---|---|');
    disagreements.forEach((r) => {
      lines.push(`| ${r.input} | ${r.expected} | ${(r.acceptable || []).join('; ')} | ${r.actual} | ${r.judgeReason} |`);
    });
  }

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
    const { status, body, latencyMs } = await translate(input);
    const actual = status === 200 ? body.tamil : `[HTTP ${status}] ${body.error}`;
    const usage = status === 200 && body.usage ? { inputTokens: body.usage.inputTokens, outputTokens: body.usage.outputTokens } : null;
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
      input, category, expected, acceptable: acceptable || [], actual, status, latencyMs, usage,
      inPrompt: Boolean(inPrompt), scored: isScored, matched, judgeVerdict, judgeReason, looksLikeReply,
    });
  }

  const scored = results.filter((r) => r.scored);
  const inPromptEntries = results.filter((r) => r.inPrompt);

  const matchCount = scored.filter((r) => r.matched).length;
  const judgedResults = scored.filter((r) => r.judgeVerdict !== null);
  const judgePassCount = judgedResults.filter((r) => r.judgeVerdict === 'PASS').length;
  const disagreements = scored.filter((r) => r.judgeVerdict === 'PASS' && r.matched === false);

  const medianLatencyMs = median(results.map((r) => r.latencyMs).filter((v) => v !== null));
  const costPer1000 = estimateCostPer1000(results.map((r) => r.usage).filter((u) => u !== null));

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
        evalFile: path.relative(process.cwd(), EVALS_PATH),
        translationModel: TRANSLATION_MODEL,
        judgeModel: JUDGE_MODEL,
        promptVersion: PROMPT_VERSION,
        matchRate: { matched: matchCount, total: scored.length },
        judgePassRate: { passed: judgePassCount, total: judgedResults.length },
        medianLatencyMs,
        estimatedCostPer1000Messages: costPer1000,
        cases: results,
      },
      null,
      2
    )
  );

  fs.writeFileSync(
    mdPath,
    renderMarkdown({ timestamp, matchRateStr, judgeRateStr, medianLatencyMs, costPer1000, scored, inPromptEntries, disagreements })
  );

  console.log(`Exact/variant match rate: ${matchRateStr}`);
  console.log(`Judge pass rate: ${judgeRateStr}`);
  console.log(`Median latency: ${medianLatencyMs !== null ? `${medianLatencyMs}ms` : 'n/a'}`);
  console.log(`Estimated cost per 1,000 messages: ${costPer1000 !== null ? `$${costPer1000.toFixed(3)}` : 'n/a'}`);
  console.log(`Full results: ${path.relative(process.cwd(), mdPath)}`);
}

main();
