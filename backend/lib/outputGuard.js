// lib/outputGuard.js
//
// Pure functions backing the "did the model actually translate this"
// check in server.js -- extracted so they can be unit tested without a
// running server or an API key. See docs/decisions/0008.

function normalize(text) {
  return text
    .toLowerCase()
    .replace(/[?.!,"']/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

// True if the model's output is, character-for-character (modulo case
// and punctuation), the same as what was sent in -- i.e. it didn't
// transliterate anything at all.
function isUnchanged(input, output) {
  return normalize(input) === normalize(output);
}

const COMMAND_STARTERS = new Set([
  'npm', 'npx', 'yarn', 'pip', 'pip3', 'git', 'cd', 'ls', 'sudo', 'curl',
  'wget', 'python', 'python3', 'node', 'brew', 'docker', 'kubectl',
  'mkdir', 'rm', 'cp', 'mv', 'chmod', 'chown', 'ssh', 'go', 'cat', 'grep',
  'echo', 'export', 'make', 'cargo', 'gradle',
]);

function looksLikeCommand(text) {
  const firstWord = (text.trim().split(/\s+/)[0] || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  return COMMAND_STARTERS.has(firstWord);
}

function looksLikeURL(text) {
  return /https?:\/\/\S+/i.test(text);
}

// Deliberately narrow -- punctuation clusters that are very rare in
// ordinary chat English but common in code, to keep false positives low.
function looksLikeCode(text) {
  return /[{};]/.test(text) || /=>/.test(text) || /\bfunction\s*\(/.test(text);
}

function looksEmojiOnly(text) {
  const trimmed = text.trim();
  if (trimmed.length === 0) return false;
  // No letters or digits anywhere -- treat non-empty, non-alphanumeric
  // text (emoji, pure punctuation) as having nothing to transliterate.
  return !/[a-zA-Z0-9]/.test(trimmed);
}

// The heuristic used to decide whether an unchanged output is actually
// fine (the input genuinely wasn't a chat message to translate) or a
// real bug (an ordinary sentence the model failed to transliterate).
// Deliberately conservative: a false negative here (missing a real
// command/URL/code case) just means one unnecessary retry, which is
// cheap; a false positive (flagging ordinary text as untranslatable)
// would suppress a retry that should have happened, which is worse.
function isLikelyUntranslatable(text) {
  return looksLikeCommand(text) || looksLikeURL(text) || looksLikeCode(text) || looksEmojiOnly(text);
}

// --- Retry output validation (docs/decisions/0011) ---
//
// The first retry design (a multi-turn conversation showing the model
// its own bad output and asking it to "try again") caused the model to
// occasionally respond with visible self-correction narration instead of
// just the translation -- observed once as a stray Tamil Unicode
// character mixed into otherwise-Latin text, and once as literal "Let me
// redo that properly:" text prepended to the real answer. The retry was
// changed to a fresh single-turn request instead (see server.js), but a
// single-turn request can still produce one of these malformed shapes --
// these functions catch that at the output level, independent of how the
// request was made.

// Reject any character that isn't Latin script, digits/punctuation
// (Unicode "Common" script), or whitespace. Checking by script rather
// than by "is it ASCII" avoids false-flagging benign non-ASCII
// punctuation (smart quotes, em dashes) while still catching the actual
// observed bug: a Tamil (or any other non-Latin) Unicode character
// leaking into what's supposed to be plain Latin-script Tanglish.
function containsNonLatinScript(text) {
  for (const char of text) {
    if (/\s/.test(char)) continue;
    if (/\p{Script=Latin}/u.test(char)) continue;
    if (/\p{Script=Common}/u.test(char)) continue;
    return true;
  }
  return false;
}

const META_COMMENTARY_PATTERNS = [
  /\blet me\b/i,
  /\bhere'?s\b/i,
  /\bhere is\b/i,
  /\btranslation:/i,
  /\bredo\b/i,
  /\bcorrected? (version|output|translation)\b/i,
];

// Catches a model narrating its own process instead of just answering --
// the literal observed bug text ("Let me redo that properly:") matches
// both the "let me" and "redo" patterns.
function containsMetaCommentary(text) {
  return META_COMMENTARY_PATTERNS.some((pattern) => pattern.test(text));
}

function isValidTranslationOutput(text) {
  return !containsNonLatinScript(text) && !containsMetaCommentary(text);
}

module.exports = {
  normalize,
  isUnchanged,
  looksLikeCommand,
  looksLikeURL,
  looksLikeCode,
  looksEmojiOnly,
  isLikelyUntranslatable,
  containsNonLatinScript,
  containsMetaCommentary,
  isValidTranslationOutput,
};
