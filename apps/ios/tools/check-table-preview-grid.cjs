// Source contracts only; no Swift/parser, UI, task scheduling or native fixture execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'dbbf69126';
const view = app + 'GalaxySSIHealthTableSourceView.swift', grid = app + 'GalaxySSIHealthTablePreviewGrid.swift';
const fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthTablePreviewGridTests.swift';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function between(s, start, end) {
  assert.equal(s.split(start).length, 2, start);
  const a = s.indexOf(start), b = s.indexOf(end, a + start.length);
  assert(b > a, end); return s.slice(a, b);
}
function validate(file, source) {
  assert([view, grid, fixture].includes(file));
  if (file === view) source = structured(file, source);
  assert.equal(source, show(approved, file), 'Exact bounded grid, owned worker/lifecycle and fixture source: ' + file);
}
function structured(file, source) {
  const tool = path.join(__dirname, 'check-structured-originals.cjs');
  return fs.existsSync(tool) ? require(tool).retained(file, source) : source;
}
module.exports = {validate};
if (require.main === module) {
  for (const f of [view, grid, fixture]) validate(f, read(f));
  const source = read(view);
  for (const [start, end] of [
    ['  private func batch()', '  private func reload()'],
    ['  private func linkedReadings(', '  private func selectSheet(']
  ]) assert.equal(between(source, start, end), between(show(base, view), start, end), 'Existing source/export authority retained');
  const tail = s => s.slice(s.indexOf('  private func save()'));
  assert.equal(tail(source), tail(show(base, view)), 'Exact raw save, UTI, confirmation labels and FileDocument implementation');
  for (const name of ['GalaxySSIHealthTableImport', 'GalaxySSIHealthXLSX']) {
    const f = app + name + '.swift';
    assert.equal(structured(f, read(f)), show(base, f), 'Only explicitly owned preview parser extensions; clinical policy retained');
  }
  const oldFixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthRecordsTests.swift';
  const start = '  func testStructuredOriginalPreviewBoundsDoNotMutateSourceTable()',
    end = '  func testXLSXUsesWorksheetRelationshipsPhysicalRowsAndExplicitFormulaConsent()';
  assert.equal(between(read(oldFixture), start, end), between(show(base, oldFixture), start, end), 'Existing legacy 30/12/256 fixture source retained');
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const lines = show(approved, project).split('\n').filter(line => [grid, fixture].some(f => line.includes(path.basename(f))));
  assert.equal(lines.length, 8); for (const line of lines) assert.equal(read(project).split(line).length, 2, line);
  const resource = app + 'zh-Hans.lproj/Localizable.strings';
  for (const key of ['grid_limited', 'loading', 'cancel_preview', 'close_cell']) {
    const owned = s => s.split('\n').filter(line => line.startsWith('"galaxyssi.health.table_source.' + key + '" = '));
    assert.equal(owned(read(resource)).length, 1); assert.deepEqual(owned(read(resource)), owned(show(approved, resource)));
  }
  const android = show('69c58da3a', 'apps/android/app/src/main/java/com/galaxyssi/chat/HealthStructuredOriginalPreview.kt');
  assert(android.includes('HorizontalScrollView') && android.includes('request != generation') &&
    android.includes('Thread.currentThread().isInterrupted'));
  const mutations = [
    [view, 'min(512, max(1, cellLimit))', 'max(1, cellLimit)'],
    [view, 'rowLimit: 20, cellLimit: 512', 'rowLimit: 100, cellLimit: 8192'],
    [view, 'try Task.checkCancellation()', '// cancelled check removed'],
    [view, 'Task.detached(priority: .userInitiated)', 'Task(priority: .userInitiated)'],
    [view, 'onCancel: { worker.cancel() }', 'onCancel: {}'],
    [view, 'requestID == token, !Task.isCancelled, scene == .active', 'scene == .active'],
    [view, 'records.owner == owner, records.isolatedFile == dataset', 'true'],
    [view, 'fresh.id == batch.id, fresh.name == batch.name', 'true'],
    [view, 'GalaxySSIHealthTableImport.digest(fresh.data) == digest', 'true'],
    [view, '    previewEnabled = false\n', '    previewEnabled = true\n'],
    [view, '.onDisappear(perform: invalidate)', '.onDisappear {}'],
    [view, '.galaxySSIRuntimePlaintextWillClear', 'Notification.Name("unused")'],
    [view, 'fresh == linked', 'true'],
    [grid, 'ScrollView([.horizontal, .vertical])', 'ScrollView(.vertical)'],
    [grid, 'width: 156, height: 86', 'width: 44, height: 20'],
    [grid, 'String(sample.rowNumbers[row])', 'String(row + 1)'],
    [grid, '.textSelection(.disabled)', '.textSelection(.enabled)'],
    [grid, '.onChange(of: scene) { if $0 != .active { selected = nil } }', '.onChange(of: scene) { _ in }'],
    [grid, 'guard scene == .active, !text.isEmpty', 'guard !text.isEmpty'],
    [grid, 'selected = nil }\n  }', '// clear removed\n  }']
  ];
  for (const [f, from, to] of mutations) {
    const s = f === view ? structured(f, read(f)) : read(f); assert(s.includes(from), from);
    assert.throws(() => validate(f, s.replace(from, to)), undefined, from);
  }
  console.log('Table preview grid source contracts passed; ' + mutations.length + ' negative source mutations. Native behavior unexecuted.');
}
