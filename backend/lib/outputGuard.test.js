const test = require('node:test');
const assert = require('node:assert/strict');
const {
  isUnchanged,
  looksLikeCommand,
  looksLikeURL,
  looksLikeCode,
  looksEmojiOnly,
  isLikelyUntranslatable,
  containsNonLatinScript,
  containsMetaCommentary,
  isValidTranslationOutput,
} = require('./outputGuard');

test('isUnchanged: identical text matches', () => {
  assert.equal(isUnchanged('movie tonight?', 'movie tonight?'), true);
});

test('isUnchanged: differs only by case/punctuation still matches', () => {
  assert.equal(isUnchanged('Movie Tonight?', 'movie tonight'), true);
});

test('isUnchanged: genuinely different text does not match', () => {
  assert.equal(isUnchanged('movie tonight?', 'Innaiku night movie ah?'), false);
});

test('isUnchanged: partially transliterated text does not match', () => {
  assert.equal(isUnchanged("let's meet at 7pm", 'Lets meet at 7pm nu solren'), false);
});

test('looksLikeCommand: recognizes common command starters', () => {
  assert.equal(looksLikeCommand('npm install'), true);
  assert.equal(looksLikeCommand('git commit -m "fix bug"'), true);
});

test('looksLikeCommand: does not flag ordinary sentences', () => {
  assert.equal(looksLikeCommand('hey macha how are you'), false);
  assert.equal(looksLikeCommand('movie tonight?'), false);
});

test('looksLikeURL: recognizes URLs', () => {
  assert.equal(looksLikeURL('check this out https://example.com/page'), true);
});

test('looksLikeURL: does not flag text without a URL', () => {
  assert.equal(looksLikeURL('no link here'), false);
});

test('looksLikeCode: recognizes code punctuation', () => {
  assert.equal(looksLikeCode('const x = () => x + 1;'), true);
  assert.equal(looksLikeCode('function add(a, b) { return a + b; }'), true);
});

test('looksLikeCode: does not flag ordinary punctuation', () => {
  assert.equal(looksLikeCode('hello there, how are you?'), false);
});

test('looksEmojiOnly: recognizes emoji/symbol-only text', () => {
  assert.equal(looksEmojiOnly('😂😂😂🔥🔥'), true);
  assert.equal(looksEmojiOnly('???'), true);
});

test('looksEmojiOnly: does not flag text with any letters', () => {
  assert.equal(looksEmojiOnly('lol 😂'), false);
});

test('looksEmojiOnly: does not flag empty text', () => {
  assert.equal(looksEmojiOnly(''), false);
  assert.equal(looksEmojiOnly('   '), false);
});

test('isLikelyUntranslatable: combines all checks', () => {
  assert.equal(isLikelyUntranslatable('npm install'), true);
  assert.equal(isLikelyUntranslatable('check https://example.com'), true);
  assert.equal(isLikelyUntranslatable('const x = 1;'), true);
  assert.equal(isLikelyUntranslatable('😂😂😂'), true);
});

test('isLikelyUntranslatable: ordinary casual sentences are not flagged', () => {
  assert.equal(isLikelyUntranslatable('movie tonight?'), false);
  assert.equal(isLikelyUntranslatable('lol that\'s so funny'), false);
  assert.equal(isLikelyUntranslatable('good morning!'), false);
});

// MARK: - Retry output validation

test('containsNonLatinScript: catches the actual observed bug (a stray Tamil character)', () => {
  assert.equal(containsNonLatinScript('Rொmba cute'), true);
});

test('containsNonLatinScript: does not flag plain Latin-script Tanglish', () => {
  assert.equal(containsNonLatinScript('Romba cute ah irukku'), false);
});

test('containsNonLatinScript: does not flag ordinary punctuation and digits', () => {
  assert.equal(containsNonLatinScript('7pm ku meet pannalam? "ok"!'), false);
});

test('containsNonLatinScript: does not flag emoji', () => {
  assert.equal(containsNonLatinScript('lol semma funny 😂'), false);
});

test('containsMetaCommentary: catches the actual observed bug ("let me" + "redo")', () => {
  assert.equal(containsMetaCommentary('Let me redo that properly:\n\nRomba cute'), true);
});

test('containsMetaCommentary: catches other given examples', () => {
  assert.equal(containsMetaCommentary("Here's the translation: Saaptiya?"), true);
  assert.equal(containsMetaCommentary('Translation: Saaptiya?'), true);
});

test('containsMetaCommentary: does not flag ordinary Tanglish output', () => {
  assert.equal(containsMetaCommentary('Enga irukka?'), false);
  assert.equal(containsMetaCommentary('Naan unna station la pick pannuren'), false);
});

test('isValidTranslationOutput: rejects either failure mode', () => {
  assert.equal(isValidTranslationOutput('Rொmba cute'), false);
  assert.equal(isValidTranslationOutput('Let me redo that properly:\n\nRomba cute'), false);
});

test('isValidTranslationOutput: accepts ordinary Tanglish output', () => {
  assert.equal(isValidTranslationOutput('Hey macha, eppadi irukka?'), true);
});
