// Source contracts and synthetic extracted grammar only, not Swift/ICU or app execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), file = 'apps/ios/GalaxySSI/AgentExecutionPolicy.swift';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447';
const clean = s => s.replace(/\r\n/g, '\n'), read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
const before = clean(cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8'}));
function once(s, from, to = '') { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
const inference = String.raw`      let inferenceSuffix = before == "\u{63a8}" && ["\u{5bfc}\u{51fa}", "\u{5c0e}\u{51fa}"].contains(term)`;
const forms = String.raw`    "\u{5c0e}\u{51fa}", "\u{532f}\u{51fa}",`;
const oldPDF = String.raw`|\u{5bfc}\u{51fa}|\u{8f6c}\u{6362}|`;
const newPDF = String.raw`|(?<!\u{63a8})[\u{5bfc}\u{5c0e}]\u{51fa}|\u{532f}\u{51fa}|\u{8f6c}\u{6362}|`;
function retained(source) {
  source = once(source, forms + '\n');
  source = once(source, inference + '\n');
  source = once(source, 'if !inferenceSuffix && !embedded && !quotedField', 'if !embedded && !quotedField');
  return once(source, newPDF, oldPDF);
}
const source = read(file);
assert.equal(retained(source), before, 'Only occurrence-aware Chinese export classification changes; artifact verification and other profile behavior retained');
function section(s, start, end) {
  const a = s.indexOf(start), b = s.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return s.slice(a + start.length, b);
}
// These expressions contain ordinary, noninterpolated Swift string literals only.
function literals(s) {
  return [...s.matchAll(/"(?:\\.|[^"\\])*"/g)].map(m => JSON.parse(m[0].replace(/\\u\{([0-9a-f]+)\}/gi,
    (_, hex) => String.fromCodePoint(Number.parseInt(hex, 16)))));
}
const terms = literals(section(source, 'private static let artifactTerms = [', '  private static let researchTerms'));
const pdfPattern = literals(section(source, 'private static let pdfRequest = try? NSRegularExpression(pattern:', ', options: .caseInsensitive)')).join('');
const negative = literals(section(source, 'private static let negativePrefix =', '\n}\n')).join('');
const pdf = new RegExp(pdfPattern, 'giu'), negated = new RegExp(negative, 'iu');
const infer = ['\u63a8\u5bfc\u51fa', '\u63a8\u5c0e\u51fa'], exportVerbs = ['\u5bfc\u51fa', '\u5c0e\u51fa', '\u532f\u51fa'];
function positive(text, term) {
  text = text.toLowerCase(); term = term.toLowerCase();
  for (let i = text.indexOf(term); i >= 0; i = text.indexOf(term, i + term.length)) {
    const left = text[i - 1] || '', right = text[i + term.length] || '';
    const word = c => /^[a-z0-9_]$/.test(c);
    const suffix = left === '\u63a8' && exportVerbs.slice(0, 2).includes(term);
    const embedded = (word(term[0]) && word(left)) || (word(term.at(-1)) && word(right));
    const field = ['"', "'"].includes(left) && right === left && /^\s*:/.test(text.slice(i + term.length + 1));
    if (!suffix && !embedded && !field && !negated.test(text.slice(Math.max(0, i - 80), i))) return true;
  }
  return false;
}
function pdfRequested(text) {
  return [...text.matchAll(pdf)].some(m => !negated.test(text.slice(Math.max(0, m.index - 80), m.index)));
}
const required = text => terms.some(t => positive(text, t)) || pdfRequested(text);
let cases = 0;
function check(text, expected) { assert.equal(required(text), expected, JSON.stringify(text)); cases++; }
for (const verb of infer) for (const format of ['PDF', 'Excel', 'CSV', 'bus timetable']) {
  check(`${verb} ${format} \u73ed\u8ddd`, false);
  assert.equal(pdfRequested(`${verb} ${format}`), false);
}
for (const verb of exportVerbs) {
  for (const format of ['PDF', 'Excel', 'CSV']) check(`${verb} ${format}`, true);
  check(`{"${verb}":true}`, false);
  check(`\u4e0d\u8981${verb} PDF`, false);
  check(`\u4e0d\u8981\u5bfc\u51fa CSV; ${verb} PDF`, true);
  assert.equal(pdfRequested(`${verb} PDF`), true);
  for (const inference of infer) {
    check(`${inference} \u73ed\u8ddd; ${verb} CSV`, true);
    check(`${inference} \u73ed\u8ddd; \u4e0d\u8981${verb} PDF`, false);
  }
}
for (const [text, expected] of [['Explain PDF', false], ['An exporter reads CSV', false], ['Do not export PDF', false],
  ['Export CSV', true], ['Do not generate Word; export PDF instead.', true], ['Generate a PDF', true],
  ['\u63a8\u5bfc\u51fa\u73ed\u8ddd; return the file', true], ['\u63a8\u5c0e\u51fa\u73ed\u8ddd; generate image', true]]) check(text, expected);
let negatives = 0;
for (const token of [forms, inference, '!inferenceSuffix &&', newPDF]) {
  assert.throws(() => retained(source.replace(token, 'REMOVED_EXPORT_BOUNDARY')), assert.AssertionError); negatives++;
}
const tests = read('apps/ios/GalaxySSITests/AgentChineseExportIntentTests.swift');
assert.equal((tests.match(/  func test/g) || []).length, 8);
for (const token of ['executionMode: .planOnly', 'testInferenceOccurrenceCannotOverrideLaterNegatedExport',
  'testExportElsewhereInInferenceSentenceIsNotSuppressed', 'hasAttachments: true']) assert(tests.includes(token), token);
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
assert.equal(project.split('AgentChineseExportIntentTests.swift in Sources').length - 1, 2);
assert.equal(project.split('\n').filter(line => line.includes('AgentChineseExportIntentTests.swift')).length, 4);
assert(!/\p{Script=Han}/u.test(tests + source));
console.log(`Chinese inference/export classification: exact four-part source delta, ${cases} synthetic extracted grammar cases and ${negatives} negative source mutations checked. Eight Swift fixtures authored, not executed; no Swift/ICU or file-delivery acceptance claimed.`);
