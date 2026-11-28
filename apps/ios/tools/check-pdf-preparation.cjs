// Source contracts only; no Swift/PDFKit, password UI, race or lifecycle execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '9b8cd24a9';
const jobs = app + 'GalaxySSIHealthRecognitionJobs.swift', pdf = app + 'GalaxySSIHealthPDFText.swift';
const view = app + 'GalaxySSIHealthOriginalsView.swift', preview = app + 'GalaxySSIHealthOriginalPDFPreview.swift';
const fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthPDFPreparationTests.swift';
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
const oldPreviewStart = '@MainActor\nprivate struct GalaxySSIHealthOriginalPDFPreview: View {';
const historyStart = '}\n\n@MainActor\nstruct OriginalExportHistory: View {';
function retainedView(source) {
  source = structured(view, source);
  if (!source.includes('GalaxySSIHealthOriginalPDFPreview(data: pdf')) {
    assert(!source.includes('    var pdf: Data?')); return source;
  }
  source = once(source, '    var pdf: Data?\n', '    var pdf: PDFDocument?\n');
  source = once(source, 'GalaxySSIHealthOriginalPDFPreview(data: pdf, name: item.name)', 'GalaxySSIHealthOriginalPDFPreview(document: pdf, name: item.name)');
  source = once(source, '        preview = Preview(original: item, pdf: data)\n',
    '        guard let pdf = PDFDocument(data: data), pdf.isLocked || pdf.pageCount > 0 else { error = true; return }\n        preview = Preview(original: item, pdf: pdf)\n');
  assert(!source.includes(oldPreviewStart));
  return once(source, historyStart, between(show(base, view), oldPreviewStart, historyStart) + historyStart);
}
function retainedPDF(source) {
  const start = '  struct Preview: Sendable {', end = '  static func pageCount(';
  const block = between(show(approved, pdf), start, end);
  assert.equal(between(source, start, end), block, 'Display-only renderer wrapper; extraction kernel unchanged');
  source = once(source, block, '');
  return once(source, '    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in\n      clearPassword(); cancel(); selected = nil; files = []\n    }\n', '');
}
function validate(file, source) {
  if (file === jobs) source = structured(file, source);
  if (file === view) {
    source = retainedView(source);
    const resave = path.join(__dirname, 'check-original-export-resave.cjs');
    if (fs.existsSync(resave)) source = require(resave).retained(file, source);
    assert.equal(source, show(base, file), 'All original source selection/save/share/removal UI retained');
  } else if (file === pdf) assert.equal(retainedPDF(source), show(base, pdf), 'Existing decode, extraction permission, OCR and render transforms retained');
  else assert.equal(source, show(approved, file), 'Exact owned preparation/view/fixture source: ' + file);
}
function structured(file, source) {
  const tool = path.join(__dirname, 'check-structured-originals.cjs');
  return fs.existsSync(tool) ? require(tool).retained(file, source) : source;
}
module.exports = {retainedView};
if (require.main === module) {
  for (const file of [jobs, pdf, view, preview, fixture]) validate(file, read(file));
  const source = structured(jobs, read(jobs)), old = show(base, jobs);
  const normalized = once(source, between(source, '  static func pdfPageCount(', '  static func process('),
    between(old, '  static func pdfPageCount(', '  static func process('));
  const boundary = '@MainActor\nstruct GalaxySSIHealthRecognitionJobsView:';
  assert.equal(normalized.slice(0, normalized.indexOf(boundary)), old.slice(0, old.indexOf(boundary)), 'Job/page/line Codable schema and OCR processing untouched');
  const loopStart = '      task = Task {\n', loopEnd = '        if activeRun == run { activeID = nil; activeRun = nil; task = nil; enterQueue() }\n      }\n';
  assert.equal(between(source, loopStart, loopEnd), between(old, loopStart, loopEnd), 'Existing native page loop, commit/identity/crop checks and failure settlement retained verbatim');
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const lines = show(approved, project).split('\n').filter(line => [preview, fixture].some(file => line.includes(path.basename(file))));
  assert.equal(lines.length, 8); for (const line of lines) assert.equal(read(project).split(line).length, 2, line);
  const resource = app + 'zh-Hans.lproj/Localizable.strings';
  const keys = ['recognition.preparing_source', ...['working', 'cancel', 'failed', 'cancelled', 'retry'].map(k => 'originals.preview_' + k)];
  for (const key of keys) {
    const owned = s => s.split('\n').filter(line => line.startsWith('"galaxyssi.health.' + key + '" = '));
    assert.equal(owned(read(resource)).length, 1); assert.deepEqual(owned(read(resource)), owned(show(approved, resource)));
  }
  const android = show('dc510ad52', 'apps/android/app/src/main/java/com/galaxyssi/chat/HealthPdfPasswordUi.kt');
  assert(android.includes('thread(name = "health-protected-pdf")') && android.includes('signal.isCanceled'));
  const mutations = [
    [jobs, 'try Task.checkCancellation()\n    let count = try GalaxySSIHealthPDFText.open', 'let count = try GalaxySSIHealthPDFText.open'],
    [jobs, 'task != nil || preparation != nil', 'task != nil'],
    [jobs, 'preparationID == token', 'true'],
    [jobs, 'records.owner == owner, store.owner == owner', 'true'],
    [jobs, 'store.restoreRecordsFile == dataset', 'true'],
    [jobs, 'try store.validateOriginalSelection([original])', ''],
    [jobs, '$0.version == job.version', 'true'],
    [jobs, 'try store.readCrop(for: original)?.metadata.revision == revision', 'true'],
    [jobs, 'let worker = Task.detached(priority: .userInitiated) { [kind = original.kind]', 'let worker = Task(priority: .userInitiated) { [kind = original.kind]'],
    [jobs, 'onCancel: { worker.cancel() }))', 'onCancel: {}))'],
    [jobs, 'records.cancelRecognitionJob(id: id, expected: version)', 'records.cancelRecognitionJob(id: id, expected: UUID())'],
    [jobs, 'if resumeAutomatic { enterQueue() }', 'enterQueue()'],
    [jobs, 'try startPrepared(job, bytes: bytes, count: count, password: password)', 'run(job, password: password)'],
    [pdf, 'let document = try open(data, password: password)\n    guard index', 'let document = try open(data, password: password, extracting: true)\n    guard index'],
    [pdf, 'if extracting && !document.allowsCopying { throw Failure.extractionRestricted }', ''],
    [pdf, 'clearPassword(); cancel(); selected = nil; files = []', 'cancel(); selected = nil; files = []'],
    [view, '    var pdf: Data?', '    var pdf: PDFDocument?'],
    [preview, 'requestID == token', 'true'],
    [preview, 'password = nil; image = nil; count = 0; status = .idle', 'image = nil; count = 0; status = .idle'],
    [preview, 'onCancel: { worker.cancel() }', 'onCancel: {}'],
    [preview, '.onDisappear(perform: clear)', '.onDisappear {}'],
    [fixture, 'XCTAssertLessThanOrEqual(max(preview.image.width, preview.image.height), 1_600)', 'XCTAssertGreaterThan(max(preview.image.width, preview.image.height), 1_600)']
  ];
  for (const [file, from, to] of mutations) {
    assert(read(file).includes(from), from); assert.throws(() => validate(file, read(file).replace(from, to)), undefined, from);
  }
  console.log(`Off-main PDF preparation/preview source scope, preserved recognition kernel, four authored Swift fixtures and ${mutations.length} negative mutations passed; native NOT executed.`);
}
