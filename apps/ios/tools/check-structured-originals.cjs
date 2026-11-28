// Source contracts only. No Swift, JSON/CSV/XML execution, persistence, picker or runtime evidence.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const prior = '33af3d3ff', approved = '45aacb52f', base = 'c6bad3465c673dfb2dcecb23b095185c129c7447';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n'), memo = new Map();
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16000000}).replace(/\r\n/g, '\n'));
  return memo.get(key);
}
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function between(s, start, end) {
  assert.equal(s.split(start).length, 2, start); const a = s.indexOf(start), b = s.indexOf(end, a + start.length);
  assert(b > a, end); return s.slice(a, b);
}
const pairs = {
  GalaxySSIHealthOriginalStore: [
    ['  enum Kind: String, Codable, CaseIterable, Sendable { case image, pdf }', '  enum Kind: String, Codable, CaseIterable, Sendable {\n    case image, pdf, structured\n    var isReport: Bool { self == .image || self == .pdf }\n  }'],
    ['    let (kind, fileExtension) = try Self.format(of: data)', '    let (kind, fileExtension) = try Self.format(of: data, fileExtension: URL(fileURLWithPath: name).pathExtension.lowercased())'],
    ['  private static func format(of data: Data) throws -> (Kind, String)', '  private static func format(of data: Data, fileExtension: String = "") throws -> (Kind, String)'],
    ['      return (.image, ext)\n    } else { throw Failure.invalid }', '      return (.image, ext)\n    } else if GalaxySSIHealthStructuredOriginal.extensions.contains(fileExtension) {\n      _ = try GalaxySSIHealthStructuredOriginal.read(data, fileExtension: fileExtension)\n      return (.structured, fileExtension)\n    } else { throw Failure.invalid }'],
    ['    let (kind, ext) = try format(of: data)', '    let (kind, ext) = try format(of: data, fileExtension: item.fileExtension)'],
    ['      !removed.contains(item.id) && (cursor.map {', '      item.kind.isReport && !removed.contains(item.id) && (cursor.map {']
  ],
  GalaxySSIHealthOriginalsView: [
    ['Label(item.name, systemImage: item.kind == .pdf ? "doc.text" : "photo")', 'Label(item.name, systemImage: item.kind == .image ? "photo" : "doc.text")'],
    ['count: available.count - photos).tag("pdf")', 'count: available.count - photos).tag("file")'],
    ['allowedContentTypes: [.image, .pdf]) { result in', 'allowedContentTypes: [.image, .pdf] + GalaxySSIHealthStructuredOriginal.contentTypes) { result in'],
    ['          Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(Text(item.name))\n        }', '          Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(Text(item.name))\n        } else if item.original.kind == .structured {\n          GalaxySSIHealthStructuredOriginalView(store: store, original: item.original)\n        }'],
    ['dateFiltered(originals).filter { filter == "all" || $0.kind.rawValue == filter }', 'dateFiltered(originals).filter { filter == "all" || (filter == "file" ? $0.kind != .image : $0.kind.rawValue == filter) }'],
    ['    guard scene == .active else { return }\n    do {\n      let data = try store.read(item)\n      if item.kind == .pdf {\n', '    guard scene == .active else { return }\n    if item.kind == .structured {\n      preview = Preview(original: item)\n      return\n    }\n    do {\n      let data = try store.read(item)\n      if item.kind == .pdf {\n'],
    ['            (item.kind == .pdf ? type.conforms(to: .pdf) : type.conforms(to: .image))', '            (item.kind == .structured ? GalaxySSIHealthStructuredOriginal.extensions.contains(item.fileExtension) :\n              (item.kind == .pdf ? type.conforms(to: .pdf) : type.conforms(to: .image)))'],
    ['Image(systemName: item.kind == .pdf ? "doc.richtext" : "photo")', 'Image(systemName: item.kind == .image ? "photo" : "doc.richtext")'],
    ['guard scene == .active, !Task.isCancelled, let data = try? store.read(item)', 'guard scene == .active, !Task.isCancelled, item.kind.isReport, let data = try? store.read(item)'],
    ['static var readableContentTypes: [UTType] { [.zip, .pdf, .image] }', 'static var readableContentTypes: [UTType] { [.zip, .pdf, .image] + GalaxySSIHealthStructuredOriginal.contentTypes }']
  ],
  GalaxySSIHealthRecords: [['guard (1...GalaxySSIHealthRecognitionJobs.maximumPages).contains(pageCount),', 'guard original.kind.isReport, (1...GalaxySSIHealthRecognitionJobs.maximumPages).contains(pageCount),']],
  GalaxySSIHealthRecognitionJobs: [
    ['throws -> Page {\n    let result:', 'throws -> Page {\n    guard kind.isReport else { throw GalaxySSIHealthRecords.Failure.invalid }\n    let result:'],
    ['      originals = listing.originals\n', '      originals = listing.originals.filter { $0.kind.isReport }\n']
  ],
  GalaxySSIHealthEncounterDocument: [['    switch kind {\n', '    switch kind {\n    case .structured: throw GalaxySSIHealthRecords.Failure.stale\n']],
  GalaxySSIHealthLinkedExport: [['else if original.sha256 != report.sha256 ||', 'else if !original.kind.isReport || original.sha256 != report.sha256 ||']],
  GalaxySSIHealthPortableBackup: [['            entry.manifest.kind != .pdf || entry.manifest.fileExtension == "pdf" else { throw Failure.invalid }', '            entry.manifest.kind != .pdf || entry.manifest.fileExtension == "pdf",\n            entry.manifest.kind != .structured || GalaxySSIHealthStructuredOriginal.extensions.contains(entry.manifest.fileExtension)\n      else { throw Failure.invalid }']],
  GalaxySSIHealthXLSX: [
    ['  var rows: [GalaxySSIHealthXLSX.SheetRow] = []\n', '  var rows: [GalaxySSIHealthXLSX.SheetRow] = []\n  let sampleOnly: Bool\n  private(set) var sampleComplete = false\n'],
    ['  init(strings: [String]) { self.strings = strings }', '  init(strings: [String], sampleOnly: Bool = false) { self.strings = strings; self.sampleOnly = sampleOnly }'],
    ['    case "row":\n      let next', '    case "row":\n      if sampleOnly, rows.count == 21 { sampleComplete = true; parser.abortParsing(); return }\n      if Task.isCancelled { parser.abortParsing(); return }\n      let next'],
    ['guard next > column, next < 64 else', 'guard next > column, next < (sampleOnly ? 16_384 : 64) else']
  ]
};
function retained(file, source, required = false) {
  const name = path.basename(file, '.swift');
  for (const [old, current] of pairs[name] || []) {
    if (required) assert(source.includes(current), 'Required structured-original hook: ' + current);
    if (source.includes(current)) source = once(source, current, old);
    else assert(source.includes(old), 'Unknown hook variant: ' + file);
  }
  const ranges = {
    GalaxySSIHealthTableImport: [['  private static func parseCSV(', '  private struct JSONRow:']],
    GalaxySSIHealthTableSourceView: [
      ['struct GalaxySSIHealthTableSourceSample: Sendable {', '@MainActor\nstruct GalaxySSIHealthTableSourceView: View {'],
      ['  private func loadPreview() async {', '  private func linkedReadings(']
    ]
  };
  if (ranges[name]) {
    for (const [start, end] of ranges[name]) {
      const old = between(show(prior, file), start, end), current = between(show(approved, file), start, end);
      const found = between(source, start, end);
      if (required || found !== old) { assert.equal(found, current); source = once(source, current, old); }
    }
  }
  if (name === 'GalaxySSIHealthXLSX') {
    const current = between(show(approved, file), '  func previewRows(', '  enum Timestamp {');
    if (required) assert(source.includes(current));
    if (source.includes('  func previewRows(')) source = once(source, current, '');
  }
  return source;
}
function optional(tool, method, ...args) {
  const file = path.join(__dirname, tool + '.cjs');
  return fs.existsSync(file) ? require(file)[method](...args) : args.at(-1);
}
function validate(file, source) {
  const name = path.basename(file, '.swift');
  if (['GalaxySSIHealthStructuredOriginal', 'GalaxySSIHealthStructuredOriginalView', 'GalaxySSIHealthStructuredOriginalTests'].includes(name)) {
    assert.equal(source, show(approved, file)); return;
  }
  source = retained(file, source, true);
  if (['GalaxySSIHealthOriginalStore', 'GalaxySSIHealthRecords'].includes(name))
    source = optional('check-photo-original-retention', 'retained', file, source);
  if (name === 'GalaxySSIHealthOriginalsView') source = optional('check-original-export-resave', 'retained', file, source);
  if (name === 'GalaxySSIHealthPortableBackup') source = optional('check-restore-file-finalization', 'retained', file, source);
  if (name === 'GalaxySSIHealthRecognitionJobs' && source.includes('preparationID')) {
    assert.equal(source, show('9b8cd24a9', file)); source = show(base, file);
  }
  assert.equal(source, show(prior, file), 'No unrelated source changes after explicit companion inverses: ' + file);
}
module.exports = {retained, validate};
if (require.main === module) {
  const own = ['GalaxySSIHealthStructuredOriginal', 'GalaxySSIHealthStructuredOriginalView', 'GalaxySSIHealthTableSourceView', 'GalaxySSIHealthTableImport', ...Object.keys(pairs)];
  for (const name of own) validate(app + name + '.swift', read(app + name + '.swift'));
  const fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthStructuredOriginalTests.swift'; validate(fixture, read(fixture));
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const filenames = ['GalaxySSIHealthStructuredOriginal.swift', 'GalaxySSIHealthStructuredOriginalView.swift', 'GalaxySSIHealthStructuredOriginalTests.swift'];
  const entries = show(approved, project).split('\n').filter(line => filenames.some(name => line.includes(name)));
  assert.equal(entries.length, 12); for (const line of entries) assert.equal(read(project).split(line).length, 2);
  const resources = app + 'zh-Hans.lproj/Localizable.strings';
  for (const key of ['empty_source', 'json_key', 'json_value']) {
    const lines = s => s.split('\n').filter(l => l.startsWith('"galaxyssi.health.table_source.' + key + '" = '));
    assert.equal(lines(read(resources)).length, 1); assert.deepEqual(lines(read(resources)), lines(show(approved, resources)));
  }
  const mutations = [
    ['GalaxySSIHealthStructuredOriginal', 'data.count <= GalaxySSIHealthTableImport.maximumBytes', 'true'],
    ['GalaxySSIHealthStructuredOriginal', 'JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])', 'String(data: data, encoding: .utf8)'],
    ['GalaxySSIHealthStructuredOriginal', 'limit: 21', 'limit: 1000'],
    ['GalaxySSIHealthStructuredOriginal', 'rowLimit: 20, cellLimit: 512', 'rowLimit: 30, cellLimit: 8192'],
    ['GalaxySSIHealthStructuredOriginalView', 'request == token, !Task.isCancelled', 'true'],
    ['GalaxySSIHealthStructuredOriginalView', 'store.owner == owner, store.restoreRecordsFile == dataset', 'true'],
    ['GalaxySSIHealthStructuredOriginalView', 'try store.validateOriginalSelection([original])', '// removed'],
    ['GalaxySSIHealthStructuredOriginalView', 'onCancel: { worker.cancel() }', 'onCancel: {}'],
    ['GalaxySSIHealthStructuredOriginalView', 'enabled = false', 'enabled = true'],
    ['GalaxySSIHealthStructuredOriginalView', '.onDisappear(perform: invalidate)', '.onDisappear {}'],
    ['GalaxySSIHealthTableSourceView', 'guard text.utf16.count > limit', 'guard text.count > limit'],
    ['GalaxySSIHealthOriginalStore', 'format(of: data, fileExtension: item.fileExtension)', 'format(of: data)'],
    ['GalaxySSIHealthOriginalStore', 'item.kind.isReport && !removed.contains(item.id)', '!removed.contains(item.id)'],
    ['GalaxySSIHealthOriginalsView', ' + GalaxySSIHealthStructuredOriginal.contentTypes', ''],
    ['GalaxySSIHealthRecords', 'guard original.kind.isReport,', 'guard'],
    ['GalaxySSIHealthRecognitionJobs', 'guard kind.isReport else { throw GalaxySSIHealthRecords.Failure.invalid }', '// removed'],
    ['GalaxySSIHealthPortableBackup', 'GalaxySSIHealthStructuredOriginal.extensions.contains(entry.manifest.fileExtension)', 'true'],
    ['GalaxySSIHealthTableImport', 'if sampleOnly, rows.count == 21', 'if rows.count == 21'],
    ['GalaxySSIHealthXLSX', 'if sampleOnly, rows.count == 21', 'if rows.count == 21'],
    ['GalaxySSIHealthXLSX', 'if !parser.sampleComplete { throw error }', '/* swallow every error */'],
    ['GalaxySSIHealthLinkedExport', '!original.kind.isReport || ', '']
  ];
  for (const [name, from, to] of mutations) {
    const file = app + name + '.swift', s = read(file); assert(s.includes(from), from);
    assert.throws(() => validate(file, s.replace(from, to)), undefined, from);
  }
  console.log('Structured original source contracts passed; ' + mutations.length + ' negative mutations. Seven authored native fixtures unexecuted.');
}
