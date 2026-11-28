// Source checks only. No Swift, persistence faults, camera, cleanup or device execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '1645b58ce70900d1ecf84078a53edcb009be1e62';
const fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthRecordsTests.swift';
const names = ['GalaxySSIHealthPhotoDraft', 'GalaxySSIHealthPhotoCaptureView', 'GalaxySSIHealthRecords',
  'GalaxySSIHealthOriginalStore', 'GalaxySSIHealthReportQuickImport'];
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
const fixtureStart = '  @MainActor\n  func testPhotoRetentionFreezesDefaultAcrossRetakeAndRejectsChangedChoice() throws {\n';
const fixtureEnd = '  @MainActor\n  func testHealthPhotoDraftSubmitsOnlyVerifiedPagesInFinalOrder() throws {\n';
function fixtureBlock(s) {
  assert.equal(s.split(fixtureStart).length, 2); assert.equal(s.split(fixtureEnd).length, 2);
  const start = s.indexOf(fixtureStart), end = s.indexOf(fixtureEnd, start);
  assert(end > start); return s.slice(start, end);
}
function retainedFixtures(source) {
  if (!source.includes(fixtureStart)) return source;
  const block = fixtureBlock(show(approved, fixture));
  assert.equal(fixtureBlock(source), block, 'Exact seven authored retention fixtures');
  return once(source, block, '');
}
function retained(file, source) {
  if (file === fixture) return retainedFixtures(source);
  assert(names.some(name => file === app + name + '.swift'), file);
  source = normalizeCompanions(file, source);
  if (source === show(base, file)) return source;
  assert.equal(source, show(approved, file), 'Exact retention integration: ' + file);
  return show(base, file);
}
function normalizeCompanions(file, source) {
  const tool = path.join(__dirname, 'check-restore-receipts.cjs');
  if (file === app + 'GalaxySSIHealthRecords.swift' && fs.existsSync(tool)) source = require(tool).retainedRecords(source);
  const paper = path.join(__dirname, 'check-photo-paper-hints.cjs');
  if (['GalaxySSIHealthPhotoDraft', 'GalaxySSIHealthPhotoCaptureView', 'GalaxySSIHealthOriginalStore'].some(name => file === app + name + '.swift') && fs.existsSync(paper))
    source = require(paper).retained(file, source);
  return source;
}
module.exports = {retained, retainedFixtures};
if (require.main === module) {
  for (const name of names) {
    const file = app + name + '.swift';
    assert.equal(normalizeCompanions(file, read(file)), show(approved, file), name);
    assert.equal(retained(file, read(file)), show(base, file));
  }
  const recordsFile = app + 'GalaxySSIHealthRecords.swift';
  assert.equal(normalizeCompanions(recordsFile, read(recordsFile)), once(show(base, recordsFile), '    var photoCaptureDraft: GalaxySSIHealthPhotoDraft.Batch?\n',
    '    var photoCaptureDraft: GalaxySSIHealthPhotoDraft.Batch?\n    var photoReviewOriginals: [UUID: GalaxySSIHealthOriginalStore.Original]?\n'),
    'Only one additive optional archive field; all prior records, transactions and permissions retained');
  let tests = retainedFixtures(read(fixture));
  const recordCheck = path.join(__dirname, 'check-health-record-center-results.cjs');
  if (fs.existsSync(recordCheck)) {
    const normalize = require(recordCheck).retainedTests;
    assert.equal(typeof normalize, 'function', 'Record-center fixture composition must remain explicit');
    tests = normalize(tests);
  }
  const restoreCheck = path.join(__dirname, 'check-restore-file-finalization.cjs');
  if (fs.existsSync(restoreCheck)) tests = require(restoreCheck).retainedFixtures(tests);
  assert.equal(tests, show(base, fixture), 'All preexisting native fixture source retained');
  const translations = app + 'zh-Hans.lproj/Localizable.strings';
  for (const key of ['take', 'album', 'retention_keep', 'retention_review', 'discard_review']) {
    const prefix = '"galaxyssi.health.photo_capture.' + key + '" = ';
    const lines = s => s.split('\n').filter(line => line.startsWith(prefix));
    assert.equal(lines(read(translations)).length, 1, key);
    assert.deepEqual(lines(read(translations)), lines(show(approved, translations)), key);
  }
  const android = show(base, 'apps/android/app/src/main/java/com/galaxyssi/chat/HealthCaptureActivity.kt');
  assert(android.includes('private fun camera() = withRetention { keepOriginal ->'));
  assert(android.includes('.putExtra(HEALTH_KEEP_ORIGINAL, keepOriginal)'));
  const batch = show(base, 'apps/android/app/src/main/java/com/galaxyssi/chat/HealthPhotoDraft.kt');
  assert(batch.includes('val keepOriginal: Boolean = true'));
  const mutations = [
    ['GalaxySSIHealthPhotoDraft', 'retainOriginal ?? true', 'retainOriginal ?? false'],
    ['GalaxySSIHealthPhotoCaptureView', 'acquisition: acquisition, retainOriginal: retain', 'acquisition: acquisition, retainOriginal: true'],
    ['GalaxySSIHealthPhotoCaptureView', 'archive.photoCaptureDraft?.keepsOriginals ?? retentionChoice.resolve', 'retentionChoice.resolve'],
    ['GalaxySSIHealthPhotoCaptureView', 'archive.photoCaptureDraft?.version == draft?.version', 'true'],
    ['GalaxySSIHealthPhotoCaptureView', 'retainOriginal: request.retainOriginal', 'retainOriginal: true'],
    ['GalaxySSIHealthPhotoCaptureView', 'scene == .active, originals.owner == records.owner', 'scene == .active'],
    ['GalaxySSIHealthPhotoCaptureView', 'cleanup(); reload()', 'reload()'],
    ['GalaxySSIHealthOriginalStore', 'preserveReviewOnly: true', 'preserveReviewOnly: false'],
    ['GalaxySSIHealthOriginalStore', 'retainOriginal: retainOriginal ?? archive.keepsNewImportOriginals', 'retainOriginal: true'],
    ['GalaxySSIHealthOriginalStore', 'retainOriginal.map({ $0 == batch.keepsOriginals }) != false', 'true'],
    ['GalaxySSIHealthOriginalStore', 'temporary.contains(original.id) || archive.originalIndex?.originals[original.id] == nil', 'true'],
    ['GalaxySSIHealthOriginalStore', 'photos[original.id] = original', ''],
    ['GalaxySSIHealthOriginalStore', 'guard id == original.id, original.kind == .image,\n                archive.photoReviewOriginals?[id] == original else { return }', ''],
    ['GalaxySSIHealthOriginalStore', 'guard id == original.id, original.kind == .image,', 'guard original.kind == .image,'],
    ['GalaxySSIHealthOriginalStore', 'guard id == original.id, original.kind == .image,', 'guard id == original.id,'],
    ['GalaxySSIHealthOriginalStore', 'guard try records.canReleaseReviewOriginal(id, in: archive) else { return }', ''],
    ['GalaxySSIHealthOriginalStore', 'if archive.reviewOnlyReportOriginals?.contains(id) != true', 'if false'],
    ['GalaxySSIHealthOriginalStore', 'let preview = try previewRemoval(original, lease: lease)', 'let preview = try previewRemoval(original)'],
    ['GalaxySSIHealthOriginalStore', 'if !final.pending.contains(id)', 'if true'],
    ['GalaxySSIHealthOriginalStore', '!reportUpdate && !preserveReviewOnly', '!reportUpdate'],
    ['GalaxySSIHealthReportQuickImport', 'archive.photoCaptureDraft?.pages.contains(where: { $0.original.id == original }) != true', 'true'],
    ['GalaxySSIHealthReportQuickImport', 'archive.reportReview?.contains(where: { $0.source.original == original }) != true', 'true'],
    ['GalaxySSIHealthReportQuickImport', 'if job.phase == .cancelled { continue }', 'if job.phase == .cancelled { return true }'],
    ['GalaxySSIHealthReportQuickImport', 'job.reportVision?.partial == false', 'true'],
    ['GalaxySSIHealthReportQuickImport', 'job.reportImportOutcome?.pendingConfirmation != true', 'true'],
    ['GalaxySSIHealthReportQuickImport', '(job.reportImportOutcome?.skipped ?? 0) == 0', 'true'],
    ['GalaxySSIHealthReportQuickImport', 'guard try canReleaseReviewOriginal(original, in: archive) else { return false }', ''],
    ['GalaxySSIHealthReportQuickImport', 'archive.photoReviewOriginals?.removeValue(forKey: original)', '']
  ];
  for (const [name, from, to] of mutations) {
    const file = app + name + '.swift', source = read(file);
    assert(source.includes(from), name + ': ' + from);
    assert.throws(() => retained(file, source.replace(from, to)), undefined, name + ': ' + from);
  }
  const changedFixture = read(fixture).replace('XCTAssertFalse(initial.keepsOriginals)', 'XCTAssertTrue(initial.keepsOriginals)');
  assert.notEqual(changedFixture, read(fixture)); assert.throws(() => retainedFixtures(changedFixture));
  console.log('Photo retention source contracts, five resources, seven authored Swift fixtures and 29 negative source mutations checked; no native execution.');
}
