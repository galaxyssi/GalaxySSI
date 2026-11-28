// Source contracts only. No Swift, document picker, native storage or restart execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '591101db3';
const store = app + 'GalaxySSIHealthOriginalStore.swift', view = app + 'GalaxySSIHealthOriginalsView.swift';
const model = app + 'GalaxySSIHealthOriginalExportSave.swift', control = app + 'GalaxySSIHealthOriginalExportSaveControl.swift';
const fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthOriginalExportSaveTests.swift';
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
function retained(file, source) {
  assert([store, view].includes(file));
  const marker = file === store ? '  private var exportSaveScope:' : '  @State private var savingExport = false';
  if (!source.includes(marker)) {
    assert(!source.includes('GalaxySSIHealthOriginalExportSave') && !source.includes('finishExportSave(')); return source;
  }
  if (file === store) {
    source = once(source, '    var latestSave: GalaxySSIHealthOriginalExportSave.Receipt?\n    var lastVerifiedAt: Date?\n', '');
    source = once(source, '    pruneArtifacts(history)\n    NotificationCenter.default.post(name: Self.indexChanged, object: owner)\n', '    pruneArtifacts(history)\n');
    const start = '  func finishExport(id:', end = '  nonisolated static func verifyDestination(';
    const block = between(show(approved, file), start, end);
    assert.equal(between(source, start, end), block, 'Exact token completion/recovery and legacy exclusion hooks');
    source = once(source, block, between(show(base, file), start, end));
  } else {
    const pairs = [
      ['@State private var exportAttempt: GalaxySSIHealthOriginalExportSave.Request?', '@State private var exportAttempt: GalaxySSIHealthOriginalStore.ExportAttempt?'],
      ['store.finishExportSave(attempt, verified: false)', 'store.finishExport(id: attempt.id, verified: false)'],
      ['      let (_, prepared) = try store.prepareExport(selected)\n      let (data, attempt) = try store.beginExportSave(prepared)', '      let (data, attempt) = try store.prepareExport(selected)'],
      ['private func verify(_ url: URL, attempt: GalaxySSIHealthOriginalExportSave.Request)', 'private func verify(_ url: URL, attempt: GalaxySSIHealthOriginalStore.ExportAttempt)'],
      ['verifyDestination(url, for: attempt.export)', 'verifyDestination(url, for: attempt)'],
      ['store.finishExportSave(attempt, verified: verified)', 'store.finishExport(id: attempt.id, verified: verified)'],
      ['  @State private var savingExport = false\n', ''],
      ['    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) {\n      if $0.object as? String == store.owner { reload() }\n    }\n', ''],
      ['      else {\n        if !savingExport { selected = nil }\n        history = []; singleHistory = []; confirmShare = false; sharing = nil\n      }', '      else { selected = nil; history = []; singleHistory = []; confirmShare = false; sharing = nil }'],
      ['            GalaxySSIHealthOriginalExportSaveControl(store: store, attempt: entry) { savingExport = $0 }\n', ''],
      ['              .disabled(savingExport)\n', ''],
      ['Button(t("close", "Close")) { selected = nil }.disabled(savingExport)', 'Button(t("close", "Close")) { selected = nil }'],
      ['    do {\n      try store.recoverExportSaves()\n      history = try store.exportHistory()\n      if let selected { self.selected = history.first(where: { $0.id == selected.id }) }\n      unavailable = false\n    }', '    do { history = try store.exportHistory(); unavailable = false }']
    ];
    for (const [from, to] of pairs) source = once(source, from, to);
  }
  return source;
}
function validate(file, source) {
  if ([model, control, fixture].includes(file)) { assert.equal(source, show(approved, file)); return; }
  source = retained(file, source);
  if (file === store) {
    const paper = path.join(__dirname, 'check-photo-paper-hints.cjs');
    if (fs.existsSync(paper)) source = require(paper).retained(file, source);
    const retention = path.join(__dirname, 'check-photo-original-retention.cjs');
    if (fs.existsSync(retention)) source = require(retention).retained(file, source);
  }
  assert.equal(source, show(base, file), 'All unrelated original storage, manifests, verification, sharing, single saves and UI retained');
}
module.exports = {retained};
if (require.main === module) {
  for (const file of [store, view, model, control, fixture]) validate(file, read(file));
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const lines = show(approved, project).split('\n').filter(line => [model, control, fixture].some(file => line.includes(path.basename(file))));
  assert.equal(lines.length, 12); for (const line of lines) assert.equal(read(project).split(line).length, 2, line);
  const resource = app + 'zh-Hans.lproj/Localizable.strings';
  for (const key of ['last_verified', 'save_again', 'save_plain_zip', 'save_pending', 'save_interrupted', 'save_receipt_failed']) {
    const owned = s => s.split('\n').filter(line => line.startsWith('"galaxyssi.health.originals.' + key + '" = '));
    assert.equal(owned(read(resource)).length, 1); assert.deepEqual(owned(read(resource)), owned(show(approved, resource)));
  }
  const android = show('eba1a449e', 'apps/android/app/src/main/java/com/galaxyssi/chat/HealthOriginalLibraryStore.kt');
  for (const text of ['fun beginSave(', 'latest.pendingSave == token', 'verifiedSaveAt = System.currentTimeMillis()', 'saveFailed = true']) assert(android.includes(text), text);
  const mutations = [
    [store, 'let data = try readShareArtifact(attempt)', 'let data = Data()'],
    [store, 'request.scope == exportSaveScope', 'true'],
    [store, 'receipt.id == request.token, receipt.outcome == .pending', 'receipt.outcome == .pending'],
    [store, 'receipt.id == request.token, receipt.outcome == .pending', 'receipt.id == request.token'],
    [store, 'history[index].outcome != .verified', 'true'],
    [store, 'guard history[index].latestSave == nil else { throw Failure.stale }', ''],
    [store, '!GalaxySSIHealthOriginalExportSave.isActive(receipt.id, scope: exportSaveScope)', 'true'],
    [store, 'try persistExportHistory(history)\n    let request = GalaxySSIHealthOriginalExportSave.Request', 'let request = GalaxySSIHealthOriginalExportSave.Request'],
    [model, 'weak var value: Request?', 'var value: Request?'],
    [model, 'left.bytes == right.bytes && left.sha256 == right.sha256', 'true'],
    [model, 'left.at == right.at && left.originals == right.originals', 'true'],
    [view, 'if !savingExport { selected = nil }', 'selected = nil'],
    [view, 'if $0.object as? String == store.owner { reload() }', 'reload()'],
    [view, 'verifyDestination(url, for: attempt.export)', 'verifyDestination(url, for: attempt.export) || true'],
    [control, 'verifyDestination(url, for: request.export)', 'verifyDestination(url, for: request.export) || true'],
    [control, 'Save this unencrypted ZIP?', 'Save this encrypted ZIP?'],
    [control, 'if !exporting && !verifying, let request', 'if let request'],
    [control, 'request != nil || liveSave', 'request != nil'],
    [control, 'document = nil\n    verifying = true', 'verifying = true'],
    [fixture, 'XCTAssertEqual(final.lastVerifiedAt, verifiedAt)', 'XCTAssertNil(final.lastVerifiedAt)']
  ];
  for (const [file, from, to] of mutations) {
    assert(read(file).includes(from), from); assert.throws(() => validate(file, read(file).replace(from, to)), undefined, from);
  }
  console.log(`Original ZIP resave/token receipt source scope, six authored Swift fixtures, registrations, localization and ${mutations.length} negative mutations passed; native NOT executed.`);
}
