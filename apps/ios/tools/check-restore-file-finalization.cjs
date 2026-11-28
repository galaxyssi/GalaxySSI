// Source contracts only; no Swift/native restore, file faults or UI execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'af99e9807fa6f501f646eef58a92dad10f0f58c4';
const backup = app + 'GalaxySSIHealthPortableBackup.swift', view = app + 'GalaxySSIHealthBackupView.swift';
const fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthRecordsTests.swift';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function between(s, start, end) {
  assert.equal(s.split(start).length, 2, start); const offset = s.indexOf(start), finish = s.indexOf(end, offset + start.length);
  assert(finish > offset, end); return s.slice(offset, finish);
}
const fixtureStart = '  @MainActor\n  func testRestoreFinalizationVerifiesOriginalsWithoutReplayingCommittedRecords() throws {\n';
const fixtureEnd = '  @MainActor\n  func testCommittedHealthRestoreAuthenticatesStagedOriginalBeforePublishing() throws {\n';
function retainedFixtures(source) {
  if (!source.includes(fixtureStart)) return source;
  const block = between(show(approved, fixture), fixtureStart, fixtureEnd);
  assert.equal(between(source, fixtureStart, fixtureEnd), block, 'Exact four authored finalization fixture methods');
  return once(source, block, '');
}
function normalizeConflictSources(source) {
  const tool = path.join(__dirname, 'check-restore-conflict-sources.cjs');
  return fs.existsSync(tool) ? require(tool).retainedBackup(source) : source;
}
function retained(file, source) {
  if (file === fixture) return retainedFixtures(source);
  assert([backup, view].includes(file), file);
  if (file === backup) source = normalizeConflictSources(source);
  if (source === show(base, file)) return source;
  assert.equal(source, show(approved, file), 'Exact restore completion/ownership source: ' + file);
  return show(base, file);
}
module.exports = {retained, retainedFixtures};
if (require.main === module) {
  const source = normalizeConflictSources(read(backup)), ui = read(view);
  for (const file of [backup, view]) {
    const current = file === backup ? source : ui;
    assert.equal(current, show(approved, file)); retained(file, current);
  }
  let old = once(source, between(source, '  struct RestoreResult: Equatable {\n', '  @MainActor\n  static func previewRestore('), '');
  const end = '  @MainActor\n  private static func restoreWork(';
  old = once(old, between(source, '  @MainActor\n  @discardableResult\n  static func restore(', end),
    between(show(base, backup), '  @MainActor\n  static func restore(', end));
  assert.equal(old, show(base, backup), 'All encryption, key derivation, validation, planning, replacement and source mapping retained');
  const retry = between(source, '  static func resumeRestore(', '  @MainActor\n  private static func finalizeRestore(');
  for (const prohibited of ['commitRestore(', 'restoreWork(', 'stageRestore(', 'write(', 'seal(', 'unlock('])
    assert(!retry.includes(prohibited), 'Retry cannot replay restore: ' + prohibited);
  const finalize = between(source, '  private static func finalizeRestore(', end);
  assert(finalize.indexOf('archive.restoreReceipts?.contains(result.receipt)') < finalize.indexOf('originals.reconcileRestores(lease: lease)'),
    'Unowned receipt cannot start recovery');
  let tests = retainedFixtures(read(fixture));
  for (const [name, method] of [['check-photo-original-retention', 'retainedFixtures'], ['check-health-record-center-results', 'retainedTests']]) {
    const tool = path.join(__dirname, name + '.cjs');
    if (fs.existsSync(tool)) { const normalize = require(tool)[method]; assert.equal(typeof normalize, 'function'); tests = normalize(tests); }
  }
  assert.equal(tests, show(base, fixture), 'All prior native fixture source retained');
  const translations = app + 'zh-Hans.lproj/Localizable.strings';
  for (const key of ['originals_pending', 'originals_pending_note', 'originals_retry', 'originals_retry_failed']) {
    const prefix = '"galaxyssi.health.backup.' + key + '" = ';
    const lines = s => s.split('\n').filter(line => line.startsWith(prefix));
    assert.equal(lines(read(translations)).length, 1, key);
    assert.deepEqual(lines(read(translations)), lines(show(approved, translations)), key);
  }
  const reference = show('bbaf3337a479b98eadae272bb797d37d417e37f7',
    'apps/android/app/src/main/java/com/galaxyssi/chat/HealthRestoreRepository.kt');
  assert(reference.includes('HealthRestoreReceipts.committed'));
  assert(reference.includes('leases.tryAcquire'));
  const mutations = [
    [backup, 'try finalizeRestore(result, records: records, originals: originals, lease: lease)\n        result.originalsReady = true', 'result.originalsReady = true'],
    [backup, 'fileprivate(set) var originalsReady = false', 'fileprivate(set) var originalsReady = true'],
    [backup, 'guard result.owner == records.owner, originals.owner == records.owner,', 'guard originals.owner == records.owner,'],
    [backup, 'originals.restoreRecordsFile == records.isolatedFile', 'true'],
    [backup, 'archive.restoreReceipts?.contains(result.receipt) == true', 'true'],
    [backup, 'result.originals.allSatisfy({ archive.originalIndex?.originals[$0.id] == $0 })', 'true'],
    [backup, 'for original in result.originals { _ = try originals.read(original, lease: lease) }', ''],
    [backup, 'try finalizeRestore(result, records: records, originals: originals, lease: lease)\n    }', 'try records.commitRestore(records.load(), receipt: UUID())\n    }'],
    [view, 'restored = result.originalsReady', 'restored = true'],
    [view, 'pendingRestore = result.originalsReady ? nil : result', 'pendingRestore = nil'],
    [view, 'guard scene == .active, task == nil, let pendingRestore else { return }', 'guard let pendingRestore else { return }'],
    [view, 'try GalaxySSIHealthPortableBackup.resumeRestore(pendingRestore, records: records, originals: originals)', 'restore()'],
    [view, 'self.pendingRestore = nil\n      restored = true\n      error = false', 'self.pendingRestore = nil\n      restored = true\n      error = true'],
    [view, '} catch { error = true }\n  }\n\n  private func run(', '} catch { self.pendingRestore = nil; error = true }\n  }\n\n  private func run('],
    [view, '    pendingRestore = nil\n    replacements = []', '    replacements = []'],
    [view, 'Button(t("originals_retry", "Retry original file recovery"), action: resumeRestore)', 'Button(t("originals_retry", "Retry original file recovery"), action: restore)']
  ];
  for (const [file, from, to] of mutations) {
    const text = read(file); assert(text.includes(from), from); assert.throws(() => retained(file, text.replace(from, to)), undefined, from);
  }
  const changed = read(fixture).replace('XCTAssertFalse(pending.originalsReady)', 'XCTAssertTrue(pending.originalsReady)');
  assert.notEqual(changed, read(fixture)); assert.throws(() => retainedFixtures(changed));
  console.log('Restore file completion/owned retry source, four resources and 17 negative source mutations checked; Swift fixtures NOT executed.');
}
