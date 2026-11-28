// Source contracts only; no Swift, document picker, native storage, races or restart execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '85ee31c9c';
const history = app + 'GalaxySSIHealthBackupHistory.swift', view = app + 'GalaxySSIHealthBackupView.swift';
const model = app + 'GalaxySSIHealthBackupOperation.swift', fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthBackupOperationTests.swift';
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
function retainedView(source) {
  if (!source.includes('@State private var generationRequest:')) { assert(!source.includes('GalaxySSIHealthBackupOperation')); return source; }
  const expected = show(approved, view), previous = show(base, view);
  for (const [start, end] of [
    ['    .onAppear {\n', '    .onDisappear { reset() }'],
    ['  private func save(_ entry:', '  private var passwordForm:'],
    ['  private func generate() {', '  private func restore() {'],
    ['  private func reset() {', '    task?.cancel(); task = nil; token = nil']
  ]) {
    const block = between(expected, start, end);
    assert.equal(between(source, start, end), block, 'Exact backup operation hook: ' + start);
    source = once(source, block, between(previous, start, end));
  }
  const pairs = [
    ['@State private var generationRequest: GalaxySSIHealthBackupOperation.Request?', '@State private var generationID: UUID?'],
    ['@State private var saveAttempt: GalaxySSIHealthBackupOperation.Request?', '@State private var saveAttempt: GalaxySSIHealthBackupHistory.Entry?'],
    ['  private var generationID: UUID? { generationRequest?.entry.id }\n\n', ''],
    ['            Button(t("dismiss_save", "Dismiss unverified save")) {\n              if let attempt = saveAttempt { finishSave(attempt, result: .failure(CancellationError())) }\n            }',
      '            Button(t("dismiss_save", "Dismiss unverified save")) { finishSave(.failure(CancellationError())) }'],
    ['          if entry.latestSave == .pending { Text(t("save_pending", "Saving backup")) }\n', ''],
    ['.disabled(task != nil || saveAttempt != nil || history.isSaving(entry))', '.disabled(task != nil || saveAttempt != nil)'],
    ['guard let generationRequest else { throw GalaxySSIHealthPortableBackup.Failure.stale }', 'guard let generationID else { throw GalaxySSIHealthPortableBackup.Failure.stale }'],
    ['try history.publish(data, request: generationRequest)', 'try history.publish(data, id: generationID)'],
    ['        if generationID != nil {\n          if let generationRequest { GalaxySSIHealthBackupOperation.release(generationRequest) }\n', '        if generationID != nil {\n'],
    ['        guard token == request else { return }\n        guard scene != .background else { reset(); return }\n        switch result {', '        guard token == request, scene != .background else { return }\n        switch result {'],
    ['      } catch {\n        guard token == request else { return }\n        guard scene != .background else { reset(); return }', '      } catch {\n        guard token == request, scene != .background else { return }']
  ];
  for (const [from, to] of pairs) source = once(source, from, to);
  const presenter = between(expected, '@MainActor\nprivate struct BackupSavePresenter:', 'private struct BackupFile:');
  assert.equal(between(source, '@MainActor\nprivate struct BackupSavePresenter:', 'private struct BackupFile:'), presenter);
  source = once(source, presenter, '');
  const newExport = between(expected, '    .background {\n      if let attempt = saveAttempt, let document = exportDocument {', '\n  }\n\n  private var historySection:');
  const oldExport = between(previous, '    .fileExporter(isPresented: $exporting, document: exportDocument,', '\n  }\n\n  private var historySection:');
  return once(source, newExport, oldExport);
}
function validate(file, source) {
  if (file === view) {
    source = retainedView(source);
    const receipts = path.join(__dirname, 'check-restore-receipts.cjs');
    if (fs.existsSync(receipts)) source = require(receipts).retainedView(source);
    const recovery = path.join(__dirname, 'check-restore-file-finalization.cjs');
    if (fs.existsSync(recovery)) source = require(recovery).retained(file, source);
    assert.equal(source, show(base, file), 'All unrelated generation/restore/verification presentation retained');
  } else assert.equal(source, show(approved, file), 'Exact owned backup operation source: ' + file);
}
module.exports = {retainedView};
if (require.main === module) {
  for (const file of [history, view, model, fixture]) validate(file, read(file));
  const current = read(history), previous = show(base, history), tail = '  func entries() throws -> [Entry]';
  assert.equal(current.slice(current.indexOf(tail)), previous.slice(previous.indexOf(tail)), 'Private-copy checking, byte/hash destination verifier, crypto/key/context/storage/prune kernel retained verbatim');
  let publish = between(current, '  private func publishData(', '  func recover() throws {');
  publish = once(publish, '  private func publishData(_ data: Data, id: UUID, generationToken: UUID?) throws {', '  func publish(_ data: Data, id: UUID) throws {');
  publish = once(publish, ' && $0.generationToken == generationToken', '');
  publish = once(publish, '    notify()\n', '');
  assert.equal(publish, between(previous, '  func publish(', '  func recover() throws {'), 'Generation publish write sequence retained outside exact producer guard/notification');
  const ui = read(view);
  assert(!ui.includes('history.beginSave(') && !ui.includes('history.finishSave(attempt.id') && !ui.includes('history.publish(data, id:'));
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const lines = show(approved, project).split('\n').filter(line => [model, fixture].some(file => line.includes(path.basename(file))));
  assert.equal(lines.length, 8); for (const line of lines) assert.equal(read(project).split(line).length, 2, line);
  const resource = app + 'zh-Hans.lproj/Localizable.strings';
  const owned = s => s.split('\n').filter(line => line.startsWith('"galaxyssi.health.backup.save_pending" = '));
  assert.equal(owned(read(resource)).length, 1); assert.deepEqual(owned(read(resource)), owned(show(approved, resource)));
  const android = show('d1f717577', 'apps/android/app/src/main/java/com/galaxyssi/chat/HealthBackupRepository.kt');
  for (const token of ['private fun <T> exclusive(', 'if (!active.add(observed.id)) return observed', 'save = HealthBackupSave.INTERRUPTED']) assert(android.includes(token), token);
  const mutations = [
    [model, 'weak var value: Request?', 'var value: Request?'],
    [model, 'guard owns(request) else { return }', ''],
    [model, 'left.bytes == right.bytes && left.sha256 == right.sha256', 'true'],
    [model, 'return request.entry.id == entry', 'return true'],
    [history, 'request.scope == scope, request.kind == .save,', 'request.kind == .save,'],
    [history, 'request.kind == .generation, GalaxySSIHealthBackupOperation.owns(request)', 'request.kind == .generation'],
    [history, '$0.saveToken == request.token', 'true'],
    [history, ' && $0.generationToken == generationToken', ''],
    [history, 'entries[index].generationToken == nil, entries[index].saveToken == nil,', ''],
    [history, 'if entries[index].latestSave == .pending && !isSaving(entries[index])', 'if entries[index].latestSave == .pending'],
    [history, '!GalaxySSIHealthBackupOperation.isActive(entries[index].generationToken,\n        kind: .generation, entry: entries[index].id, scope: scope)', 'true'],
    [history, 'let data = try checkedPackage(entries[index])', 'let data = Data()'],
    [history, 'if verified { entries[index].lastVerifiedAt = Date() }', 'entries[index].lastVerifiedAt = Date()'],
    [view, 'current === attempt, !verifyingSave', '!verifyingSave'],
    [view, 'guard let current = saveAttempt, current === attempt else { return }', 'guard saveAttempt != nil else { return }'],
    [view, '.id(attempt.token)', '.id(UUID())'],
    [view, 'completed: finishSave', 'completed: { _, result in if let latest = saveAttempt { finishSave(latest, result: result) } }'],
    [view, 'try targetHistory.finishSave(attempt, verified: verified)', 'try history.finishSave(attempt, verified: verified)'],
    [view, 'private func reset() {\n    if let generationRequest { GalaxySSIHealthBackupOperation.release(generationRequest) }', 'private func reset() {'],
    [view, 'guard scene == .active, task == nil, let plan', 'guard scene == .active, let plan'],
    [view, 'clearSavePresentation(); reset(); entries = []; historyLoaded = false', 'reset(); entries = []; historyLoaded = false'],
    [view, 'guard scene != .background else { reset(); return }', 'guard scene != .background else { return }'],
    [fixture, 'XCTAssertEqual(recovered.latestSave, .interrupted)', 'XCTAssertEqual(recovered.latestSave, .verified)']
  ];
  for (const [file, from, to] of mutations) {
    assert(read(file).includes(from), from); assert.throws(() => validate(file, read(file).replace(from, to)), undefined, from);
  }
  console.log(`Backup generation/save ownership and fixed picker callback source, seven authored Swift fixtures, registrations, localization and ${mutations.length} negative mutations passed; native NOT executed.`);
}
