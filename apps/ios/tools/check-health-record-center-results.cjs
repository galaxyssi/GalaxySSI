// Source contracts only; no Swift compilation or UI/locale execution.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447';
const approved = '5f5a2f7b4a8808fa037bb5a5523a4baea4efccbb';
const file = app + 'GalaxySSIHealthRecordCenterView.swift';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function validate(source) { assert.equal(source, show(approved, file), 'Exact typed result row and locale formatting'); }
function retainedView(source) {
  if (source === show(base, file)) return source;
  validate(source); return show(base, file);
}
module.exports = {retainedView};
if (require.main === module) {
  const source = read(file); validate(source);
  const helper = '  private func summary(_ reading: GalaxySSIHealthReading) -> String {\n' +
    '    let value = reading.reported?.raw ?? reading.value?.formatted(.number.locale(locale)) ?? ""\n' +
    '    let lower = reading.diastolic.map { "/" + $0.formatted(.number.locale(locale)) } ?? ""\n' +
    '    return value + lower + (reading.unit.isEmpty ? "" : " " + reading.unit)\n  }\n\n';
  let expected = once(show(base, file), '  @Environment(\\.galaxySSIInterfaceLanguage) private var language\n',
    '  @Environment(\\.galaxySSIInterfaceLanguage) private var language\n  @Environment(\\.locale) private var locale\n');
  expected = once(expected, 'Text((reading.value?.formatted() ?? "") + " " + reading.unit)', 'Text(summary(reading))');
  expected = once(expected, '  private func reload() {', helper + '  private func reload() {');
  assert.equal(source, expected, 'All navigation, draft guards, grouping, reload and lifecycle retained');
  const unindent = s => s.split('\n').map(line => line.trimStart()).join('\n');
  assert(unindent(read(app + 'GalaxySSIHealthMetricCatalogView.swift')).includes(unindent(helper)), 'Reuse catalog result semantics');
  const reference = show('7c98635fab8b5c0e27ec0f19c95b94acf0432a61',
    'apps/android/app/src/main/java/com/galaxyssi/chat/HealthRecordCenterView.kt');
  assert(reference.includes('healthDisplayValue(record.draft)'));
  for (const name of ['GalaxySSIHealthRecords', 'GalaxySSIHealthMetricCatalog', 'GalaxySSIHealthReportReview'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ': unchanged data boundary');
  const mutations = [
    ['reading.reported?.raw ?? ', ''],
    ['reading.value?.formatted(.number.locale(locale))', 'reading.value?.formatted()'],
    ['reading.diastolic.map { "/" + $0.formatted(.number.locale(locale)) }', 'reading.pulse.map { "/" + $0.formatted(.number.locale(locale)) }'],
    ['return value + lower +', 'return value +'],
    ['reading.unit.isEmpty ? "" : " " + reading.unit', '" " + reading.metric.unit'],
    ['Text(summary(reading))', 'Text(reading.value?.formatted() ?? "")'],
    ['.disabled(snapshot.draft != nil)', '.disabled(false)'],
    ['guard scene == .active else { return }', 'guard true else { return }']
  ];
  for (const [from, to] of mutations) {
    assert(source.includes(from), from);
    assert.throws(() => validate(source.replace(from, to)));
    assert.throws(() => retainedView(source.replace(from, to)));
  }
  console.log('Record center typed result source contract and 8 negative mutations passed; no native/UI execution.');
}
