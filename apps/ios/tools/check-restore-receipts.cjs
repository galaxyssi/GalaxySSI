// Source contracts only; no Swift compilation, database, restore or UI execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', prior = '74fa96a50577890353d7a1cea8a51b955e8bf0b8';
const approved = '05a1f4832';
const backup = app + 'GalaxySSIHealthPortableBackup.swift', records = app + 'GalaxySSIHealthRecords.swift';
const view = app + 'GalaxySSIHealthBackupView.swift', model = app + 'GalaxySSIHealthRestoreReceipt.swift';
const history = app + 'GalaxySSIHealthRestoreHistoryView.swift';
const fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthRestoreConflictSourceTests.swift';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function between(s, start, end) {
  assert.equal(s.split(start).length, 2, start); const a = s.indexOf(start), b = s.indexOf(end, a + start.length);
  assert(b > a, end); return s.slice(a, b);
}
function replaceBlock(source, file, start, end, oldStart = start) {
  const block = between(show(approved, file), start, end);
  assert.equal(between(source, start, end), block, 'Exact receipt hook: ' + start);
  return once(source, block, between(show(prior, file), oldStart, end));
}
function retainedBackup(source) {
  if (!source.includes('let (fresh, proposed, files, context)')) {
    assert(!source.includes('receiptDetail: detail') && !source.includes('private struct RestoreContext')); return source;
  }
  source = replaceBlock(source, backup, '      let (fresh, proposed, files, context)', '      do {\n        try originals.stageRestore(',
    '      let (fresh, proposed, files, payload)');
  source = once(source, 'originals: files.map { $0.0 }, receiptDetail: detail, notify: false)', 'originals: files.map { $0.0 }, notify: false)');
  source = replaceBlock(source, backup, '  @MainActor\n  private static func restoreWork(', '  private enum SourceSlot: Hashable {');
  const start = '  private struct SourceRestore {';
  const tail = s => s.slice(s.indexOf(start));
  assert.equal(source.split(start).length, 2); assert.equal(tail(source), tail(show(approved, backup)), 'Exact source counter ownership');
  return once(source, tail(source), tail(show(prior, backup)));
}
function retainedRecords(source) {
  const field = '    var restoreHistory: [GalaxySSIHealthRestoreReceipt]?\n';
  if (!source.includes(field)) { assert(!source.includes('receiptDetail: GalaxySSIHealthRestoreReceipt')); return source; }
  source = once(source, field, '');
  return replaceBlock(source, records, '  func commitRestore(', '  func setOriginalIndex(');
}
function viewBlocks() {
  const approvedView = show(approved, view);
  return [
    '  @State private var latestRestoreReceipt: GalaxySSIHealthRestoreReceipt?\n',
    between(approvedView, '          if let latestRestoreReceipt {', '        }\n        if let outcome {'),
    '      let previousReceipts = try records.load().restoreReceipts ?? []\n',
    '      let receipt = (try? records.load())?.restoreHistory?.first { !previousReceipts.contains($0.id) }\n',
    '      latestRestoreReceipt = receipt\n',
    '    latestRestoreReceipt = nil\n'
  ];
}
function retainedView(source) {
  if (!source.includes('latestRestoreReceipt')) { assert(!source.includes('GalaxySSIHealthRestoreHistoryView')); return source; }
  for (const block of viewBlocks()) source = once(source, block, '');
  return source;
}
function retainedFixture(source) {
  if (!source.includes('testReceiptBoundsRejectOverflowAndConservationFailures')) return source;
  assert.equal(source, show(approved, fixture), 'Seven authored Swift cases, not executed'); return show(prior, fixture);
}
function validate(file, source) {
  if ([model, history, fixture].includes(file)) { assert.equal(source, show(approved, file)); return; }
  if (file === backup) {
    source = retainedBackup(source);
    source = require('./check-restore-conflict-sources.cjs').retainedBackup(source);
    const tool = path.join(__dirname, 'check-restore-file-finalization.cjs');
    if (fs.existsSync(tool)) source = require(tool).retained(file, source);
  } else if (file === records) {
    source = retainedRecords(source);
    const tool = path.join(__dirname, 'check-photo-original-retention.cjs');
    if (fs.existsSync(tool)) source = require(tool).retained(file, source);
  } else if (file === view) {
    source = retainedView(source);
    const tool = path.join(__dirname, 'check-restore-file-finalization.cjs');
    if (fs.existsSync(tool)) source = require(tool).retained(file, source);
  } else assert.fail(file);
  assert.equal(source, show(base, file), 'All unrelated persistence/restore/UI source retained: ' + file);
}
module.exports = {retainedBackup, retainedRecords, retainedView, retainedFixture};
if (require.main === module) {
  for (const file of [backup, records, view, model, history, fixture]) validate(file, read(file));
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const lines = show(approved, project).split('\n').filter(line => ['GalaxySSIHealthRestoreReceipt.swift', 'GalaxySSIHealthRestoreHistoryView.swift'].some(name => line.includes(name)));
  assert.equal(lines.length, 8); for (const line of lines) assert.equal(read(project).split(line).length, 2, line);
  const resource = app + 'zh-Hans.lproj/Localizable.strings';
  const owned = s => s.split('\n').filter(line => line.startsWith('"galaxyssi.health.restore_receipt.'));
  assert.equal(owned(read(resource)).length, 21); assert.deepEqual(owned(read(resource)), owned(show(approved, resource)));
  const mutations = [
    [backup, 'fresh.conflicts.count - replacements.count', 'fresh.conflicts.count'],
    [backup, 'fresh.skippedLinks - selectedSources.added - selectedSources.reused', 'fresh.skippedLinks'],
    [backup, 'context.sourceMissing.union(selectedSources.missingKeys).count', 'context.sourceMissing.count + selectedSources.missingKeys.count'],
    [backup, 'receiptDetail: detail, ', ''],
    [backup, 'originalsReused: payload.originals.count - unavailable - files.count', 'originalsReused: payload.originals.count'],
    [records, 'updated.restoreHistory = current.restoreHistory', 'updated.restoreHistory = nil'],
    [records, 'guard receiptDetail.id == receipt else', 'guard true else'],
    [records, 'receipts.formUnion(updated.restoreReceipts ?? [])', 'receipts = []'],
    [model, 'static let maximumHistory = 100', 'static let maximumHistory = 1000'],
    [model, '!committed.contains(receipt.id)', 'true'],
    [model, '$0.isValid && committed.contains($0.id)', '$0.isValid'],
    [model, '(0...10_000).contains($0)', '$0 >= 0'],
    [model, 'sources == sourcesAdded + sourcesReused + sourcesSkipped', 'true'],
    [history, 'if $0 == .active { reload() } else { clear() }', 'if $0 == .active { reload() }'],
    [history, 'committed: archive.restoreReceipts ?? []', 'committed: Set(history.map(\\.id))'],
    [view, 'latestRestoreReceipt = receipt', 'latestRestoreReceipt = nil'],
    [view, '.first { !previousReceipts.contains($0.id) }', '.first']
  ];
  for (const [file, from, to] of mutations) {
    assert(read(file).includes(from), from); assert.throws(() => validate(file, read(file).replace(from, to)), undefined, from);
  }
  console.log(`Detailed restore receipt/history source scope, registration, localization and ${mutations.length} negative mutations passed; Swift NOT executed.`);
}
