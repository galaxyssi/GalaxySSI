// Source checks only; no SwiftUI, SceneStorage or native health execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'f89405aa845882dceab8fe4ec8dba61103f3dbab';
const file = app + 'GalaxySSIHealthSleepReminderView.swift', clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function validate(source) { assert.equal(source, show(approved, file), 'Exact latest-by-default evidence selection'); }
function retainedView(source) {
  if (source === show(base, file)) return source;
  validate(source); return show(base, file);
}
module.exports = {retainedView};
if (require.main === module) {
  const source = read(file); validate(source);
  let expected = once(show(base, file),
    '@SceneStorage("galaxyssi.health.sleep.latest-evidence-episode") private var latestEvidenceEpisode = ""',
    '@SceneStorage("galaxyssi.health.sleep.initial-evidence-episode") private var initialEvidenceEpisode = ""');
  expected = once(expected, 'hasLatest && latestEvidenceEpisode == id.uuidString', 'hasLatest && initialEvidenceEpisode != id.uuidString');
  expected = once(expected, 'latestEvidenceEpisode = $0 ? id.uuidString : ""', 'initialEvidenceEpisode = $0 ? "" : id.uuidString');
  assert.equal(source, expected, 'Only scene-local selection polarity changes; all evidence and consent routing retained');
  const android = show('009d2f5b07e625c36dbd8a046e7f080482e7376f',
    'apps/android/app/src/main/java/com/galaxyssi/chat/HealthReminderActivity.kt');
  assert(android.includes('private var showSleepTrigger = false'));
  assert(android.includes('val evidence = if (showSleepTrigger) alert.trigger else alert.evidence'));
  for (const name of ['GalaxySSIHealthSleepReminder', 'GalaxySSIWeeklyHealthReport'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ': unchanged saved-evidence validation');
  const mutations = [
    ['hasLatest && initialEvidenceEpisode != id.uuidString', 'hasLatest && initialEvidenceEpisode == id.uuidString'],
    ['initialEvidenceEpisode = $0 ? "" : id.uuidString', 'initialEvidenceEpisode = $0 ? id.uuidString : ""'],
    ['galaxyssi.health.sleep.initial-evidence-episode', 'galaxyssi.health.sleep.latest-evidence-episode'],
    ['let selected = showLatest ? episode.latest : episode.first', 'let selected = showLatest ? episode.first : episode.latest'],
    ['evidenceRoute = .init(kind: .recent, snapshot: selected)', 'evidenceRoute = .init(kind: .recent, snapshot: episode.first)'],
    ['evidenceRoute = .init(kind: .baseline, snapshot: selected)', 'evidenceRoute = .init(kind: .baseline, snapshot: episode.latest)'],
    ['evidenceRoute = .init(kind: .report, snapshot: selected)', 'evidenceRoute = .init(kind: .report, snapshot: episode.latest)'],
    ['.onChange(of: allowed) { if !$0 { evidenceRoute = nil } }', '']
  ];
  for (const [from, to] of mutations) {
    assert(source.includes(from), from); assert.throws(() => retainedView(source.replace(from, to)), undefined, from);
  }
  console.log('Sleep evidence default/explicit selection source and 8 negative source mutations passed; no native UI execution.');
}
