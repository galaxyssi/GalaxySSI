// Source contracts only. No Swift, Vision, encrypted storage or native UI execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'dfff021a8';
const draft = app + 'GalaxySSIHealthPhotoDraft.swift', capture = app + 'GalaxySSIHealthPhotoCaptureView.swift';
const store = app + 'GalaxySSIHealthOriginalStore.swift', crop = app + 'GalaxySSIHealthReportCrop.swift';
const fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthPhotoPaperHintTests.swift';
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
  assert([draft, capture, store, crop].includes(file));
  const installed = file === draft ? source.includes('  struct PaperHint:') : file === capture ? source.includes('.inspectCapture(') :
    file === store ? source.includes('paper: GalaxySSIHealthPhotoDraft.PaperHint?') : source.includes('  var initialPaper:');
  if (!installed) { assert(!source.includes('validatedPaper') && !source.includes('initialPaper:') && !source.includes('paper: paper')); return source; }
  const expected = show(approved, file);
  const removeBlock = (start, end) => {
    const block = between(expected, start, end);
    assert.equal(between(source, start, end), block, 'Exact paper hint hook: ' + start);
    source = once(source, block, '');
  };
  if (file === draft) {
    removeBlock('  struct PaperHint:', '  struct Entry:');
    removeBlock('    var paper: PaperHint? = nil\n', '  }\n\n  struct Batch:');
    source = once(source, 'replacing pageID: UUID?,\n                          paper: PaperHint? = nil) throws {', 'replacing pageID: UUID?) throws {');
    source = once(source, '            paper.map({ mode == .report && $0.isValid && $0.sha256 == original.sha256 }) ?? true,\n', '');
    source = once(source, 'original: original, hints: hints, paper: paper)', 'original: original, hints: hints)');
    removeBlock('\n\n  static func inspectCapture(', '\n}');
  } else if (file === store) {
    source = once(source, '                             paper: GalaxySSIHealthPhotoDraft.PaperHint? = nil,\n', '');
    source = once(source, 'batch.install(original, hints: hints, replacing: page, paper: paper)', 'batch.install(original, hints: hints, replacing: page)');
  } else if (file === capture) {
    const pairs = [
      ['GalaxySSIHealthReportCropView(store: originals, initialOriginalID: original.id,\n          initialPaper: draft?.pages.first(where: { $0.original == original })?.validatedPaper)', 'GalaxySSIHealthReportCropView(store: originals, initialOriginalID: original.id)'],
      ['store: originals, bounds: page.validatedPaper?.bounds)', 'store: originals)'],
      ['        if let paper = page.validatedPaper {\n          Text(paper.bounds != nil ? t("edges_found", "Paper edges found") : t("edges_unclear", "Paper edges are unclear; check the original"))\n            .font(.caption).foregroundColor(.secondary)\n        }\n', ''],
      ['        } label: {\n          Label(page.validatedPaper?.bounds != nil ? t("suggested_crop", "Review suggested crop") : t("crop", "Crop page"), systemImage: "crop")\n        }', '        } label: { Label(t("crop", "Crop page"), systemImage: "crop") }'],
      ['GalaxySSIHealthPhotoDraft.inspectCapture(data, mode: request.mode)', 'GalaxySSIHealthPhotoDraft.inspect(data)'],
      ['let inspection = try await withTaskCancellationHandler', 'let hints = try await withTaskCancellationHandler'],
      ['paper: inspection.paper, hints: inspection.hints', 'hints: hints']
    ];
    for (const [from, to] of pairs) source = once(source, from, to);
    const start = '@MainActor\nprivate struct GalaxySSIHealthPhotoThumbnail: View {', end = 'private struct GalaxySSIHealthPhotoAlbum:';
    const block = between(expected, start, end);
    assert.equal(between(source, start, end), block, 'Exact aspect-fit suggestion overlay, no image re-encoding');
    source = once(source, block, between(show(base, file), start, end));
  } else {
    source = once(source, '  var initialPaper: GalaxySSIHealthPhotoDraft.PaperHint? = nil\n', '');
    removeBlock('    if item.id == initialOriginalID, let initialPaper,', '    running = true\n');
  }
  return source;
}
function validate(file, source) {
  if (file === fixture) { assert.equal(source, show(approved, fixture)); return; }
  source = retained(file, source);
  const retention = path.join(__dirname, 'check-photo-original-retention.cjs');
  if (file !== crop && fs.existsSync(retention)) source = require(retention).retained(file, source);
  assert.equal(source, show(base, file), 'All preexisting retention, owner/version, staged storage, crop encoder and detector source retained');
}
module.exports = {retained};
if (require.main === module) {
  for (const file of [draft, capture, store, crop, fixture]) validate(file, read(file));
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const lines = show(approved, project).split('\n').filter(line => line.includes(path.basename(fixture)));
  assert.equal(lines.length, 4); for (const line of lines) assert.equal(read(project).split(line).length, 2, line);
  const resource = app + 'zh-Hans.lproj/Localizable.strings';
  for (const key of ['edges_found', 'edges_unclear', 'suggested_crop']) {
    const owned = s => s.split('\n').filter(line => line.startsWith('"galaxyssi.health.photo_capture.' + key + '" = '));
    assert.equal(owned(read(resource)).length, 1); assert.deepEqual(owned(read(resource)), owned(show(approved, resource)));
  }
  const android = show('1006f6087', 'apps/android/app/src/main/java/com/galaxyssi/chat/HealthCameraActivity.kt');
  assert(android.includes('row.page.quality?.suggestedCrop') && android.includes('HEALTH_REPORT_CROP, suggested?.encode()'));
  const mutations = [
    [draft, 'paper.sha256 == original.sha256', 'true'],
    [draft, 'mode == .report && $0.isValid && $0.sha256 == original.sha256', '$0.isValid'],
    [draft, 'var paper: PaperHint? = nil', 'var paper: PaperHint'],
    [draft, 'hints: hints, paper: paper)', 'hints: hints, paper: nil)'],
    [draft, 'guard mode == .report else', 'guard true else'],
    [draft, 'catch is CancellationError { throw CancellationError() }', 'catch is CancellationError { return .init(hints: hints, paper: nil) }'],
    [draft, 'GalaxySSIHealthLinkedExport.digest(bytes)', 'String(repeating: "a", count: 64)'],
    [draft, 'catch { return .init(hints: hints, paper: nil) }', 'catch { return .init(hints: hints, paper: .init(sha256: GalaxySSIHealthLinkedExport.digest(bytes), bounds: nil)) }'],
    [store, 'replacing: page, paper: paper)', 'replacing: page, paper: nil)'],
    [capture, 'first(where: { $0.original == original })', 'first'],
    [capture, 'bounds.minX * width, y: bounds.minY * height', 'bounds.minX * 52, y: bounds.minY * 52'],
    [capture, 'min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))', '1.0'],
    [capture, 'paper: inspection.paper, hints: inspection.hints', 'paper: nil, hints: inspection.hints'],
    [crop, 'initialPaper.sha256 == item.sha256', 'true'],
    [crop, 'item.id == initialOriginalID, let initialPaper', 'let initialPaper'],
    [crop, 'if !modified, let bounds = initialPaper.bounds', 'if let bounds = initialPaper.bounds'],
    [crop, 'finished = true\n      return', 'finished = true'],
    [fixture, 'XCTAssertNil(batch.pages.last?.validatedPaper)', 'XCTAssertNotNil(batch.pages.last?.validatedPaper)']
  ];
  for (const [file, from, to] of mutations) {
    assert(read(file).includes(from), from); assert.throws(() => validate(file, read(file).replace(from, to)), undefined, from);
  }
  console.log(`Photo paper hint source scope, six authored Swift fixtures, registrations, localization and ${mutations.length} negative mutations passed; Swift/Vision/UI NOT executed.`);
}
