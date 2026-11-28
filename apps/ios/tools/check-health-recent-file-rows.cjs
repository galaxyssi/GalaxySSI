// Source contracts only. No SwiftUI, Foundation date formatting or Health I/O execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'e6cf3a9c62974b04cea75a86011687ba1bb8661d';
const android = 'b687358302662293cd6a648b8ba0b04422572a7b', file = app + 'GalaxySSIHealthDataFilesView.swift';
const clean = s => s.replace(/\r\n/g, '\n'), read = f => clean(fs.readFileSync(path.join(root, f), 'utf8')), memo = new Map();
function show(ref, name) {
  const key = ref + ':' + name;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key],
    {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function section(source) {
  const first = '  private func fileRow(', last = '  private func heading(';
  assert.equal(source.split(first).length, 2);
  const a = source.indexOf(first), b = source.indexOf(last, a);
  assert(b > a); return source.slice(a, b);
}
function validate(source) { assert.equal(source, show(approved, file), 'Complete reviewed native Health file rows'); }
function retainedView(source) {
  if (source === show(base, file)) return source;
  validate(source);
  const environment = '  @Environment(\\.timeZone) private var timeZone\n';
  assert.equal(source.split(environment).length, 2);
  source = source.replace(environment, '');
  return source.replace(section(source), section(show(base, file)));
}
module.exports = {retainedView};
if (require.main === module) {
  const source = read(file); validate(source);
  assert.equal(retainedView(source), show(base, file), 'All navigation/loading/privacy/actions outside the row retained');
  const reference = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/HealthDataFilesActivity.kt');
  for (const token of ['val date = Date(file.added)', 'DateFormat.getMediumDateFormat(', 'DateFormat.getTimeFormat(',
    'R.string.health_data_file_meta', 'maxLines = 2', 'if (file.image) ORANGE else BLUE',
    '!file.available -> R.string.health_data_missing', 'file.linked && file.available']) assert(reference.includes(token), token);
  const row = section(source);
  for (const token of ['fileDate(original.importedAt)', 'Locale(identifier: language)', 'formatter.timeZone = timeZone',
    'formatter.dateStyle = .medium', 'formatter.timeStyle = .short', '[fileDate(original.importedAt), source, size]',
    'Text(status).font(.caption.weight(.semibold))', 'item.status == .linked ? .green : .orange',
    'original.kind == .image ? .orange : .blue', '.lineLimit(2)', '.frame(minHeight: 64)',
    '.fixedSize(horizontal: false, vertical: true)', '.accessibilityElement(children: .combine)']) assert(row.includes(token), token);
  assert(!/Data\(contentsOf:|FileManager|URLSession|\.write\(|\.store\(/.test(row), 'Formatting cannot read/decrypt/export originals');
  for (const name of ['GalaxySSIHealthDataFiles', 'GalaxySSIHealthRecords', 'GalaxySSIHealthOriginalStore'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ': unchanged backing logic');
  const mutations = [
    ['fileDate(original.importedAt)', 'fileDate(Date())'],
    ['formatter.locale = Locale(identifier: language)', 'formatter.locale = Locale.current'],
    ['formatter.timeZone = timeZone', 'formatter.timeZone = TimeZone(secondsFromGMT: 0)'],
    ['formatter.dateStyle = .medium', 'formatter.dateStyle = .none'],
    ['formatter.timeStyle = .short', 'formatter.timeStyle = .none'],
    ['Text(status).font(.caption.weight(.semibold))', 'Text(source).font(.caption.weight(.semibold))'],
    ['item.status == .linked ? .green : .orange', 'item.status == .unlinked ? .green : .orange'],
    ['original.kind == .image ? .orange : .blue', 'original.kind == .image ? .blue : .blue'],
    ['.lineLimit(2)', '.lineLimit(1)'],
    ['.fixedSize(horizontal: false, vertical: true)', '.fixedSize(horizontal: true, vertical: false)']
  ];
  for (const [from, to] of mutations) {
    assert(source.includes(from), from); const changed = source.replace(from, to);
    assert.throws(() => validate(changed), undefined, from);
    assert.throws(() => retainedView(changed), undefined, 'Unknown row edits cannot normalize away');
  }
  console.log('Android #3943 recent-file presentation and 10 negative source mutations checked; no native UI/date execution.');
}
