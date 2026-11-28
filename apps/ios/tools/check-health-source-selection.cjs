// Source contracts only. No SwiftUI, persistence faults, HealthKit, native or device execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '5d091c0a33897229551fedfa897d538143a0ff4e';
const android = 'b7e20fb12e39c4d0566e7e2a16bebbb6bd810b25', file = app + 'GalaxySSIHealthKitImportView.swift';
const clean = s => s.replace(/\r\n/g, '\n'), read = f => clean(fs.readFileSync(path.join(root, f), 'utf8')), memo = new Map();
function show(ref, name) {
  const key = ref + ':' + name;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key],
    {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function validate(source) { assert.equal(source, show(approved, file), 'Exact saved-source selection and metadata retry'); }
function retainedView(source) {
  if (source === show(base, file)) return source;
  validate(source); return show(base, file);
}
module.exports = {retainedView};
if (require.main === module) {
  const source = read(file); validate(source);
  let expected = once(show(base, file), '                    scopes = updated\n', '');
  expected = once(expected, '            .disabled(task != nil)\n          }\n          Picker(t("period",',
    '            .disabled(task != nil || sourceLedger == nil)\n          }\n          Picker(t("period",');
  expected = once(expected, '              clear()\n              scopes = []\n              saveSourceState', '              clear()\n              saveSourceState');
  const failure = '          Text(t("recovery_unavailable", "Source recovery information is unavailable.")).foregroundColor(.secondary)\n';
  const retry = '          Button(GalaxySSILocalization.string("galaxyssi.health.sources_retry", fallback: "Retry sources", language: language)) {\n' +
    '            loadSourceState()\n            loadImportHistory()\n          }.disabled(task != nil)\n';
  expected = once(expected, failure, failure + retry);
  expected = once(expected, '  private func saveSourceState(_ update: (inout GalaxySSIHealthSourceAttention) -> Void) {\n',
    '  private func saveSourceState(_ update: (inout GalaxySSIHealthSourceAttention) -> Void) {\n    guard scene == .active else { return }\n');
  expected = once(expected, '    } catch {\n      sourceStateUnavailable = true\n',
    '    } catch {\n      loadSourceState()\n      sourceStateUnavailable = true\n');
  assert.equal(source, expected, 'Every other UI, read/import, cancellation and recovery line retained');
  const reference = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/HealthConnectActivity.kt');
  for (const token of ['val previous = selection(context)', 'if (previous == selected) return',
    'context.contentResolver.notifyChange(changes(context), null)']) assert(reference.includes(token), token);
  for (const name of ['GalaxySSIHealthRecords', 'GalaxySSIHealthSourceAttention', 'GalaxySSIHealthKitImport', 'GalaxySSIHealthCenterView'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ': unchanged storage/query/overview');
  assert(read(app + 'zh-Hans.lproj/Localizable.strings').includes('"galaxyssi.health.sources_retry" = "'));
  assert(!source.includes('scopes = updated'), 'A toggle cannot publish an uncommitted selection');
  const mutations = [
    ['saveSourceState { $0.selected = updated }', 'scopes = updated; saveSourceState { $0.selected = updated }'],
    ['clear()\n              saveSourceState { $0.selected.removeAll() }', 'clear()\n              scopes = []\n              saveSourceState { $0.selected.removeAll() }'],
    ['} catch {\n      loadSourceState()\n      sourceStateUnavailable = true', '} catch {\n      sourceStateUnavailable = true'],
    ['try records.updateSourceAttention(update)\n      loadSourceState()', 'loadSourceState()\n      try records.updateSourceAttention(update)'],
    ['private func saveSourceState(_ update: (inout GalaxySSIHealthSourceAttention) -> Void) {\n    guard scene == .active else { return }',
      'private func saveSourceState(_ update: (inout GalaxySSIHealthSourceAttention) -> Void) {'],
    ['.disabled(task != nil || sourceLedger == nil)', '.disabled(task != nil)'],
    [retry, retry.replace('loadSourceState()', 'prepare()')],
    [retry, retry.replace('.disabled(task != nil)', '.disabled(false)')]
  ];
  for (const [from, to] of mutations) {
    assert(source.includes(from), from); const changed = source.replace(from, to);
    assert.throws(() => validate(changed), undefined, from); assert.throws(() => retainedView(changed));
  }
  console.log('Health source selection persistence/order and 8 negative source mutations checked; no native fault/UI execution.');
}
