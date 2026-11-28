// Source checks only; no Swift compilation, XCTest, restore faults or device execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..');
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '74fa96a50577890353d7a1cea8a51b955e8bf0b8';
const file = 'apps/ios/GalaxySSI/GalaxySSIHealthPortableBackup.swift';
const fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthRestoreConflictSourceTests.swift';
const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj', fixtureName = path.basename(fixture);
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map(), read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
const helperStart = '  @MainActor\n  private static func restoreSelectedSources(';
const helperEnd = '  private enum SourceSlot: Hashable {\n';
const call = '      try restoreSelectedSources(payload, selected: selected, archive: &archive, staged: files,\n' +
  '                                 originals: originals, lease: lease)\n';
const append = '      archive.revisions.append(contentsOf: replacements)\n';
function helper(source) {
  assert.equal(source.split(helperStart).length, 2); const start = source.indexOf(helperStart), end = source.indexOf(helperEnd, start);
  assert(end > start); return source.slice(start, end);
}
function retainedBackup(source) {
  source = require('./check-restore-receipts.cjs').retainedBackup(source);
  if (!source.includes(helperStart)) { assert(!source.includes('try restoreSelectedSources(')); return source; }
  const block = helper(show(approved, file)); assert.equal(helper(source), block, 'Exact selected-only source binding helper');
  assert(source.includes(append + call + '      let receipt = UUID()'), 'Bind after new revisions, before staging/commit');
  source = once(source, call, ''); source = once(source, block, '');
  source = once(source, 'let (fresh, proposed, files, payload) = try restoreWork(', 'let (fresh, proposed, files) = try restoreWork(');
  source = once(source, '-> (RestorePreview, GalaxySSIHealthRecords.Archive, [(GalaxySSIHealthOriginalStore.Original, Data)], Payload) {',
    '-> (RestorePreview, GalaxySSIHealthRecords.Archive, [(GalaxySSIHealthOriginalStore.Original, Data)]) {');
  source = once(source, 'return (preview, archive, files, payload)', 'return (preview, archive, files)');
  source = once(source, 'columns: source.columns,\n            dateOnlyDecision: source.dateOnlyDecision, excelDate1904: source.excelDate1904)))',
    'columns: source.columns)))');
  source = once(source, 'columns: source.columns, dateOnlyDecision: source.dateOnlyDecision, excelDate1904: source.excelDate1904))',
    'columns: source.columns))');
  return source;
}
function validateSource(source) {
  source = require('./check-restore-receipts.cjs').retainedBackup(source);
  assert(source.includes(helperStart), 'Actual selected-revision binding is installed');
  assert(!helper(source).includes('JSONDecoder'), 'Reuse the already validated decoded payload');
  source = retainedBackup(source);
  const recovery = path.join(__dirname, 'check-restore-file-finalization.cjs');
  if (fs.existsSync(recovery)) source = require(recovery).retained(file, source);
  assert.equal(source, show(base, file), 'All codec/crypto/validation/preview/conflict/source ownership outside exact hooks retained');
}
const ownedProjectLines = () => show(approved, projectFile).split('\n').filter(line => line.includes(fixtureName));
function validateProject(source) {
  const lines = ownedProjectLines(); assert.equal(lines.length, 4);
  for (const line of lines) assert.equal(source.split(line).length, 2, 'Exact single test registration: ' + line);
}
module.exports = {retainedBackup,
  retainedRecords: source => require('./check-restore-receipts.cjs').retainedRecords(source),
  retainedView: source => require('./check-restore-receipts.cjs').retainedView(source)};
if (require.main === module) {
  const source = require('./check-restore-receipts.cjs').retainedBackup(read(file)); validateSource(source); validateProject(read(projectFile));
  assert.equal(require('./check-restore-receipts.cjs').retainedFixture(read(fixture)), show(approved, fixture), 'Original four authored Swift test methods retained, not executed');
  assert(!read(fixture).includes('HealthFixtureSecrets'), 'Standalone private fixture does not change the large existing test file');
  const android = show('f7028ad1a3b07625b3ac3bad02b4959174b5357e',
    'apps/android/app/src/main/java/com/galaxyssi/chat/HealthRestoreRepository.kt');
  for (const token of ['for (id in selected)', 'plan.stage.sourceLinks(conflictId = id)', 'records.insertRestoredSource(link)'])
    assert(android.includes(token), token);
  const mutations = [
    [call, ''],
    [append + call, call + append],
    ['try restoreSelectedSources(payload, selected: selected', 'try? restoreSelectedSources(payload, selected: selected'],
    ['guard !selected.isEmpty else { return }', ''],
    ['let readings = payload.readings.filter { selected.contains($0.id) }', 'let readings = payload.readings'],
    ['Set(readings.map(\\.id)) == selected, selected.allSatisfy({ current[$0] != nil })', 'true'],
    ['let frames = (payload.sourceFrames ?? []).filter { $0.target.map { selected.contains($0.record) } == true }', 'let frames = payload.sourceFrames ?? []'],
    ['restoreSourceFrames(frames, readings: readings', 'restoreSourceFrames(frames, readings: payload.readings'],
    ['listing: originals.list(lease: lease), staged: staged', 'listing: originals.list(), staged: staged'],
    ['listing: originals.list(lease: lease), staged: staged', 'listing: originals.list(lease: lease), staged: []'],
    ['owners == Set([target])', 'owners.contains(target)'],
    ['archive.draft?.existing?.id != target.record', 'true'],
    ['reserve(slot, for: target)\n        added.append(mapped)', 'added.append(mapped)'],
    ['dateOnlyDecision: source.dateOnlyDecision, excelDate1904: source.excelDate1904)))', 'dateOnlyDecision: nil, excelDate1904: source.excelDate1904)))'],
    ['columns: source.columns, dateOnlyDecision: source.dateOnlyDecision, excelDate1904: source.excelDate1904))', 'columns: source.columns))'],
    ['let candidates = current.lazy.filter { matches($0, reading) }.prefix(2)', 'let candidates = current.lazy.filter { matches($0, reading) }.prefix(1)']
  ];
  for (const [from, to] of mutations) { assert(source.includes(from), from); assert.throws(() => validateSource(source.replace(from, to)), undefined, from); }
  const changedFixture = read(fixture).replace('replacing: [fixture.first.id]', 'replacing: [fixture.second.id]');
  assert.notEqual(changedFixture, read(fixture)); assert.throws(() => assert.equal(changedFixture, show(approved, fixture)));
  for (const line of ownedProjectLines().filter(line => line.includes('in Sources'))) {
    assert.throws(() => validateProject(read(projectFile).replace(line, '')));
  }
  console.log(`Selected restore source/provenance scope, test registration and ${mutations.length + 3} negative source mutations checked; Swift tests NOT executed.`);
}
